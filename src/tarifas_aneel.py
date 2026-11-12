"""
Le o tarifas_aneel_limpo.csv e devolve a tarifa residencial de cada distribuidora.

Aceita os dois formatos mais comuns:
  - colunas no estilo da ANEEL (SigAgente, VlrTUSD, VlrTE, DscClasse...), com ou sem renomear;
  - arquivo ja simplificado (distribuidora + tarifa_kwh).
Os filtros (B1, residencial, convencional, sem baixa renda) so sao aplicados quando a
coluna existe. Valores acima de R$ 10 sao tratados como R$/MWh e divididos por 1000.

Para conferir o que o script entendeu do arquivo de voces:
  python tarifas_aneel.py
"""

import re
import sys
import unicodedata

import pandas as pd

import config


def _without_accent(text):
    return unicodedata.normalize("NFKD", str(text)).encode("ascii", "ignore").decode().lower().strip()


def _column_key(name):
    return re.sub(r"[^a-z0-9]", "", _without_accent(name))


def _column(df, candidates, contains=None, does_not_contain=None):
    """Acha a coluna pelo nome, ignorando maiuscula, acento, espaco e _."""
    keys = {_column_key(c): c for c in df.columns}
    for cand in candidates:
        if cand in keys:
            return keys[cand]
    if contains:
        for key, original in keys.items():
            if all(p in key for p in contains) and not any(p in key for p in (does_not_contain or [])):
                return original
    return None


def _number(series):
    value = series.fillna("").astype(str).str.strip()
    has_comma = value.str.contains(",", regex=False)  # "1.234,56" -> 1234.56; "245.67" fica igual
    value = value.where(~has_comma, value.str.replace(".", "", regex=False).str.replace(",", "."))
    return pd.to_numeric(value, errors="coerce")


def read_csv(path):
    for enc in ("utf-8-sig", "latin-1"):
        try:
            return pd.read_csv(path, sep=None, engine="python", encoding=enc, dtype=str)
        except UnicodeDecodeError:
            continue
    raise ValueError(f"nao consegui ler {path}")


def detect_columns(df):
    return {
        "nome": _column(df, ["sigagente", "agente", "distribuidora", "nomagente", "nomedistribuidora"],
                        contains=["agente"], does_not_contain=["acessante", "cnpj"]),
        "tarifa": _column(df, ["tarifakwh", "tarifa", "valorkwh", "tarifatotal", "tarifarkwh", "tarifafinal"]),
        "tusd": _column(df, ["vlrtusd", "tusd", "valortusd"], contains=["tusd"]),
        "te": _column(df, ["vlrte", "te", "valorte", "tarifate"]),
        "inicio": _column(df, ["datiniciovigencia", "iniciovigencia", "vigenciainicio", "datainicio"],
                          contains=["inicio"]),
        "base": _column(df, ["dscbasetarifaria", "basetarifaria"], contains=["base", "tarif"]),
        "subgrupo": _column(df, ["dscsubgrupo", "subgrupo"], contains=["subgrupo"]),
        "modalidade": _column(df, ["dscmodalidadetarifaria", "modalidadetarifaria", "modalidade"],
                              contains=["modalidade"]),
        "classe": _column(df, ["dscclasse", "classe"]),
        "subclasse": _column(df, ["dscsubclasse", "subclasse"]),
        "detalhe": _column(df, ["dscdetalhe", "detalhe"]),
        "posto": _column(df, ["nompostotarifario", "postotarifario", "posto"], contains=["posto"]),
    }


# coluna -> valor aceito (comparado sem acento e em minusculo)
FILTERS = {
    "base": "tarifa de aplicacao",
    "subgrupo": "b1",
    "modalidade": "convencional",
    "classe": "residencial",
    "subclasse": "residencial",   # tira baixa renda
    "detalhe": "nao se aplica",
    "posto": "nao se aplica",
}


def read_residential_tariffs(path=None, display=False):
    """Devolve DataFrame [nome, tarifa_kwh, vigencia_inicio, fonte], com historico de vigencias."""
    path = path or config.TARIFFS_CSV
    df = read_csv(path)
    col = detect_columns(df)

    if not col["nome"] or not (col["tarifa"] or (col["tusd"] and col["te"])):
        raise KeyError(
            f"nao reconheci as colunas de {path.name}. Preciso de uma coluna com o nome da "
            f"distribuidora e de tarifa (ou TUSD + TE).\nColunas do arquivo: {list(df.columns)}"
        )

    applied = []
    for key, accepted in FILTERS.items():
        col_name = col[key]
        if not col_name:
            continue
        values = df[col_name].map(_without_accent)
        if (values == accepted).any():  # so filtra se o valor existe (o arquivo pode ja vir filtrado)
            df = df[values == accepted]
            applied.append(f"{col_name} = {accepted}")

    if col["tarifa"]:
        tariff = _number(df[col["tarifa"]])
    else:
        tariff = _number(df[col["tusd"]]) + _number(df[col["te"]])
    if tariff.median() > 10:  # R$/MWh -> R$/kWh
        tariff = tariff / 1000

    validity = None
    if col["inicio"]:
        datas = df[col["inicio"]].fillna("").astype(str).str.strip().str[:10]
        first_day = datas.str.contains("/", regex=False).any()  # 24/06/2026 ou 2026-06-24
        validity = pd.to_datetime(datas, errors="coerce", dayfirst=first_day).dt.strftime("%Y-%m-%d")

    output = pd.DataFrame({
        "nome": df[col["nome"]].astype(str).str.strip(),
        "tarifa_kwh": tariff.round(5),
        "vigencia_inicio": validity,
        "fonte": "ANEEL – tarifas homologadas, B1 residencial",
    })
    output = output[output["tarifa_kwh"] > 0]
    output = output.drop_duplicates(subset=["nome", "vigencia_inicio"], keep="first")

    if display:
        print(f"Arquivo: {path}")
        print("Colunas reconhecidas:")
        for key, col_name in col.items():
            print(f"  {key:<11} -> {col_name or '(nao encontrada)'}")
        print(f"Filtros aplicados: {', '.join(applied) or 'nenhum (arquivo ja filtrado?)'}")
        print(f"Distribuidoras com tarifa: {output['nome'].nunique()}")
        print(f"Faixa da tarifa: R$ {output['tarifa_kwh'].min():.4f} a R$ {output['tarifa_kwh'].max():.4f} por kWh")
    return output.reset_index(drop=True)


if __name__ == "__main__":
    try:
        tariffs = read_residential_tariffs(display=True)
    except (KeyError, FileNotFoundError, ValueError) as error:
        print(f"Erro: {error}")
        sys.exit(1)
    print("\nExemplo (5 primeiras):")
    print(tariffs.head().to_string(index=False))
