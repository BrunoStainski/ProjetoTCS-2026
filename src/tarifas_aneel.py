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


def _sem_acento(texto):
    return unicodedata.normalize("NFKD", str(texto)).encode("ascii", "ignore").decode().lower().strip()


def _chave_coluna(nome):
    return re.sub(r"[^a-z0-9]", "", _sem_acento(nome))


def _coluna(df, candidatos, contem=None, nao_contem=None):
    """Acha a coluna pelo nome, ignorando maiuscula, acento, espaco e _."""
    chaves = {_chave_coluna(c): c for c in df.columns}
    for cand in candidatos:
        if cand in chaves:
            return chaves[cand]
    if contem:
        for chave, original in chaves.items():
            if all(p in chave for p in contem) and not any(p in chave for p in (nao_contem or [])):
                return original
    return None


def _numero(serie):
    valor = serie.fillna("").astype(str).str.strip()
    tem_virgula = valor.str.contains(",", regex=False)  # "1.234,56" -> 1234.56; "245.67" fica igual
    valor = valor.where(~tem_virgula, valor.str.replace(".", "", regex=False).str.replace(",", "."))
    return pd.to_numeric(valor, errors="coerce")


def ler_csv(caminho):
    for enc in ("utf-8-sig", "latin-1"):
        try:
            return pd.read_csv(caminho, sep=None, engine="python", encoding=enc, dtype=str)
        except UnicodeDecodeError:
            continue
    raise ValueError(f"nao consegui ler {caminho}")


def detectar_colunas(df):
    return {
        "nome": _coluna(df, ["sigagente", "agente", "distribuidora", "nomagente", "nomedistribuidora"],
                        contem=["agente"], nao_contem=["acessante", "cnpj"]),
        "tarifa": _coluna(df, ["tarifakwh", "tarifa", "valorkwh", "tarifatotal", "tarifarkwh", "tarifafinal"]),
        "tusd": _coluna(df, ["vlrtusd", "tusd", "valortusd"], contem=["tusd"]),
        "te": _coluna(df, ["vlrte", "te", "valorte", "tarifate"]),
        "inicio": _coluna(df, ["datiniciovigencia", "iniciovigencia", "vigenciainicio", "datainicio"],
                          contem=["inicio"]),
        "base": _coluna(df, ["dscbasetarifaria", "basetarifaria"], contem=["base", "tarif"]),
        "subgrupo": _coluna(df, ["dscsubgrupo", "subgrupo"], contem=["subgrupo"]),
        "modalidade": _coluna(df, ["dscmodalidadetarifaria", "modalidadetarifaria", "modalidade"],
                              contem=["modalidade"]),
        "classe": _coluna(df, ["dscclasse", "classe"]),
        "subclasse": _coluna(df, ["dscsubclasse", "subclasse"]),
        "detalhe": _coluna(df, ["dscdetalhe", "detalhe"]),
        "posto": _coluna(df, ["nompostotarifario", "postotarifario", "posto"], contem=["posto"]),
    }


# coluna -> valor aceito (comparado sem acento e em minusculo)
FILTROS = {
    "base": "tarifa de aplicacao",
    "subgrupo": "b1",
    "modalidade": "convencional",
    "classe": "residencial",
    "subclasse": "residencial",   # tira baixa renda
    "detalhe": "nao se aplica",
    "posto": "nao se aplica",
}


def ler_tarifas_residenciais(caminho=None, mostrar=False):
    """Devolve DataFrame [nome, tarifa_kwh, vigencia_inicio, fonte], com historico de vigencias."""
    caminho = caminho or config.TARIFAS_CSV
    df = ler_csv(caminho)
    col = detectar_colunas(df)

    if not col["nome"] or not (col["tarifa"] or (col["tusd"] and col["te"])):
        raise KeyError(
            f"nao reconheci as colunas de {caminho.name}. Preciso de uma coluna com o nome da "
            f"distribuidora e de tarifa (ou TUSD + TE).\nColunas do arquivo: {list(df.columns)}"
        )

    aplicados = []
    for chave, aceito in FILTROS.items():
        nome_col = col[chave]
        if not nome_col:
            continue
        valores = df[nome_col].map(_sem_acento)
        if (valores == aceito).any():  # so filtra se o valor existe (o arquivo pode ja vir filtrado)
            df = df[valores == aceito]
            aplicados.append(f"{nome_col} = {aceito}")

    if col["tarifa"]:
        tarifa = _numero(df[col["tarifa"]])
    else:
        tarifa = _numero(df[col["tusd"]]) + _numero(df[col["te"]])
    if tarifa.median() > 10:  # R$/MWh -> R$/kWh
        tarifa = tarifa / 1000

    vigencia = None
    if col["inicio"]:
        datas = df[col["inicio"]].fillna("").astype(str).str.strip().str[:10]
        dia_primeiro = datas.str.contains("/", regex=False).any()  # 24/06/2026 ou 2026-06-24
        vigencia = pd.to_datetime(datas, errors="coerce", dayfirst=dia_primeiro).dt.strftime("%Y-%m-%d")

    saida = pd.DataFrame({
        "nome": df[col["nome"]].astype(str).str.strip(),
        "tarifa_kwh": tarifa.round(5),
        "vigencia_inicio": vigencia,
        "fonte": f"ANEEL tarifas homologadas, B1 residencial ({caminho.name})",
    })
    saida = saida[saida["tarifa_kwh"] > 0]
    saida = saida.drop_duplicates(subset=["nome", "vigencia_inicio"], keep="first")

    if mostrar:
        print(f"Arquivo: {caminho}")
        print("Colunas reconhecidas:")
        for chave, nome_col in col.items():
            print(f"  {chave:<11} -> {nome_col or '(nao encontrada)'}")
        print(f"Filtros aplicados: {', '.join(aplicados) or 'nenhum (arquivo ja filtrado?)'}")
        print(f"Distribuidoras com tarifa: {saida['nome'].nunique()}")
        print(f"Faixa da tarifa: R$ {saida['tarifa_kwh'].min():.4f} a R$ {saida['tarifa_kwh'].max():.4f} por kWh")
    return saida.reset_index(drop=True)


if __name__ == "__main__":
    try:
        tarifas = ler_tarifas_residenciais(mostrar=True)
    except (KeyError, FileNotFoundError, ValueError) as erro:
        print(f"Erro: {erro}")
        sys.exit(1)
    print("\nExemplo (5 primeiras):")
    print(tarifas.head().to_string(index=False))
