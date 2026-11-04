import os
from pathlib import Path
import pandas as pd
from sqlalchemy import create_engine, text

# 1. Configuração dos Caminhos (Robusto a qualquer diretório de execução)
# Localiza a raiz 'ProjetoTCS' subindo um nível a partir de 'Scripts/'
raiz_projeto = Path(__file__).resolve().parent.parent
pasta_datasets = raiz_projeto / "Datasets"

# 2. String de Conexão do PostgreSQL no Docker
# (Ajuste a porta 5433 ou 5432 e as credenciais conforme seu docker-compose.yml)
DATABASE_URL = ("postgresql+psycopg2://admin:admin123@localhost:5434/banco_projeto")
engine = create_engine(DATABASE_URL)


def resetar_banco(conn):
    """Limpa o schema public, removendo todas as tabelas anteriores."""
    print("🧹 Apagando tabelas existentes no banco de dados...")
    conn.execute(text("DROP SCHEMA public CASCADE; CREATE SCHEMA public;"))
    conn.commit()
    print("✓ Banco de dados limpo com sucesso!\n")


def importar_csvs():
    if not pasta_datasets.exists():
        print(f"❌ [ERRO] A pasta 'Datasets' não foi encontrada em: {pasta_datasets}")
        return

    # Busca todos os arquivos .csv na pasta Datasets
    arquivos_csv = sorted(list(pasta_datasets.glob("*.csv")))

    if not arquivos_csv:
        print(f"⚠️ [AVISO] Nenhum arquivo CSV encontrado em: {pasta_datasets}")
        return

    print(f"🚀 Encontrados {len(arquivos_csv)} arquivos CSV para importar.\n")

    # Conecta ao banco de dados e reseta as tabelas
    with engine.connect() as conn:
        resetar_banco(conn)

        for caminho_csv in arquivos_csv:
            # Padroniza o nome da tabela (ex: chuveiros-eletricos_limpo.csv -> chuveiros_eletricos_limpo)
            nome_tabela = caminho_csv.stem.replace("-", "_")

            print(f"📦 Importando '{caminho_csv.name}' -> Tabela '{nome_tabela}'...")

            try:
                # Lê o CSV com UTF-8
                df = pd.read_csv(caminho_csv, encoding="utf-8")
                
                # Envia para o PostgreSQL
                df.to_sql(nome_tabela, con=conn, if_exists="replace", index=False)
                
                print(f"   ✓ Sucesso: {len(df)} linhas inseridas.\n")
            except Exception as e:
                print(f"   ❌ Erro ao importar {caminho_csv.name}: {e}\n")

    print("🎉 Processo de importação concluído com sucesso!")


if __name__ == "__main__":
    importar_csvs()