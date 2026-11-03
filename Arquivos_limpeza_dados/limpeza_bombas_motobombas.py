import os
import re
from pathlib import Path
import pandas as pd

caminho_projeto = Path.cwd()
if caminho_projeto.name == "Notebook_limpeza_dados":
    caminho_projeto = caminho_projeto.parent

caminho_entrada = caminho_projeto / "Datasets" / "Bombas-e-motobombas-centrifuga.csv"
caminho_saida = caminho_projeto / "Datasets" / "bombas-e-motobombas_limpo.csv"

try:
    df = pd.read_csv(caminho_entrada, encoding='utf-8')
    if len(df.columns) == 1:
        df = pd.read_csv(caminho_entrada, encoding='utf-8', sep=';')
except:
    df = pd.read_csv(caminho_entrada, encoding='latin1', sep=';')

df.columns = df.columns.str.replace('ï»¿', '').str.strip()

df = df.dropna(subset=['Marca', 'Modelo']).drop_duplicates()

if "Código de Barras" in df.columns:
    df["Código de Barras"] = (
        df["Código de Barras"]
        .fillna("N/A")
        .astype(str)
        .str.replace(r"\.0$", "", regex=True)
    )

df.to_csv(caminho_saida, index=False, encoding="utf-8")

if caminho_entrada.exists():
    os.remove(caminho_entrada)
    print(f"✓ Arquivo original deletado: {caminho_entrada.name}")

print(f"✓ Dataset limpo salvo em: {caminho_saida}")