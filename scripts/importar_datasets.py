"""Carrega os CSVs de datasets/processed no PostgreSQL (uma tabela por arquivo).

Só substitui as tabelas dos próprios datasets; outras tabelas do banco
(clientes, inventário etc.) não são tocadas.
"""

import sys

import pandas as pd
from sqlalchemy import create_engine

from config import PASTA_PROCESSED, database_url


def nome_tabela(caminho) -> str:
    """'ar-condicionado_limpo.csv' -> 'ar_condicionado_limpo'."""
    return caminho.stem.replace("-", "_").lower()


def importar_csvs() -> int:
    arquivos_csv = sorted(PASTA_PROCESSED.glob("*.csv"))
    if not arquivos_csv:
        print(f"❌ Nenhum CSV encontrado em: {PASTA_PROCESSED}")
        return 1

    print(f"🚀 {len(arquivos_csv)} arquivos CSV para importar.\n")
    engine = create_engine(database_url())
    falhas = []

    for caminho_csv in arquivos_csv:
        tabela = nome_tabela(caminho_csv)
        print(f"📦 '{caminho_csv.name}' -> tabela '{tabela}'")
        try:
            df = pd.read_csv(caminho_csv, encoding="utf-8")
            # Uma transação por tabela: se falhar, a versão anterior é mantida
            with engine.begin() as conn:
                df.to_sql(tabela, con=conn, if_exists="replace", index=False)
            print(f"   ✓ {len(df)} linhas inseridas.")
        except Exception as erro:
            print(f"   ❌ Erro: {erro}")
            falhas.append(caminho_csv.name)

    if falhas:
        print(f"\n⚠️ Importação concluída com {len(falhas)} falha(s): {', '.join(falhas)}")
        return 1

    print("\n🎉 Importação concluída com sucesso!")
    return 0


if __name__ == "__main__":
    sys.exit(importar_csvs())
