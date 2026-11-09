import sys

import pandas as pd

from config import caminho_raw, salvar_processado

ARQUIVO = "anp_preco_glp_uf.csv"
SAIDA = "preco_glp_uf_limpo.csv"
FONTE = "ANP, Anuario Estatistico 2026, tabela 3.22 (preco medio do GLP ao consumidor, R$/kg)"
SIGLAS = {
    "Acre": "AC", "Alagoas": "AL", "Amapá": "AP", "Amazonas": "AM", "Bahia": "BA", "Ceará": "CE",
    "Distrito Federal": "DF", "Espírito Santo": "ES", "Goiás": "GO", "Maranhão": "MA", "Mato Grosso": "MT",
    "Mato Grosso do Sul": "MS", "Minas Gerais": "MG", "Pará": "PA", "Paraíba": "PB", "Paraná": "PR",
    "Pernambuco": "PE", "Piauí": "PI", "Rio de Janeiro": "RJ", "Rio Grande do Norte": "RN",
    "Rio Grande do Sul": "RS", "Rondônia": "RO", "Roraima": "RR", "Santa Catarina": "SC", "São Paulo": "SP",
    "Sergipe": "SE", "Tocantins": "TO",
}


def tratar(df):
    df = df.rename(columns=lambda c: c.strip())
    estado, preco, ano = df.columns[1], df.columns[2], df.columns[3]
    saida = pd.DataFrame({
        "uf": df[estado].str.strip().map(SIGLAS),
        "estado": df[estado].str.strip(),
        "ano": pd.to_numeric(df[ano], errors="coerce").astype("Int64"),
        "preco_kg": pd.to_numeric(df[preco].astype(str).str.replace(",", ".", regex=False), errors="coerce"),
    })
    sem_sigla = saida["uf"].isna() & saida["estado"].notna()
    if sem_sigla.any():
        raise ValueError(f"estado sem sigla: {sorted(saida.loc[sem_sigla, 'estado'].unique())}")
    saida = saida.dropna(subset=["uf", "ano", "preco_kg"])
    saida = saida[saida["preco_kg"] > 0].drop_duplicates(subset=["uf", "ano"]).sort_values(["uf", "ano"])
    saida["fonte"] = FONTE
    return saida.reset_index(drop=True)


def main():
    try:
        df = pd.read_csv(caminho_raw(ARQUIVO), sep=";", encoding="utf-8-sig")
        saida = tratar(df)
        ultimo = saida.groupby("uf").tail(1)
        print(f"✓ {saida['uf'].nunique()} estados, anos {saida['ano'].min()}-{saida['ano'].max()}; "
              f"ultimo ano: R$ {ultimo['preco_kg'].min():.2f} a R$ {ultimo['preco_kg'].max():.2f} por kg")
        salvar_processado(saida, SAIDA)
    except Exception as erro:
        print(f"\n[ERRO NA EXECUÇÃO]: {erro}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
