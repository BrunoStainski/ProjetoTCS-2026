import os
import re
from pathlib import Path
import pandas as pd

caminho_projeto = Path.cwd()
if caminho_projeto.name == "Notebook_limpeza_dados":
    caminho_projeto = caminho_projeto.parent

caminho_entrada = caminho_projeto / "Datasets" / "fornos-eletricos-comerciais.csv"
caminho_saida = caminho_projeto / "Datasets" / "fornos-eletricos-comerciais_limpo.csv"

try:
    df = pd.read_csv(caminho_entrada, encoding='utf-8')
    if len(df.columns) == 1:
        df = pd.read_csv(caminho_entrada, encoding='utf-8', sep=';')
except:
    df = pd.read_csv(caminho_entrada, encoding='latin1', sep=';')

df.columns = df.columns.str.replace('ï»¿', '').str.strip()

df = df.dropna(subset=['Marca', 'Modelo']).drop_duplicates()

if 'Consumo de Energia Elétrica (kWh)' in df.columns:
    df['Consumo de Energia Elétrica (kWh)'] = pd.to_numeric(df['Consumo de Energia Elétrica (kWh)'].astype(str).str.replace(',', '.'), errors='coerce')

if 'Potência Nominal (kW)' in df.columns:
    df['Potência Nominal (kW)'] = pd.to_numeric(df['Potência Nominal (kW)'].astype(str).str.replace(',', '.'), errors='coerce')

if 'Consumo de Energia Elétrica (kWh)' in df.columns:
    df['Consumo de Energia Elétrica (kWh)'] = df.groupby('Marca')['Consumo de Energia Elétrica (kWh)'].transform(lambda x: x.fillna(x.mean()))
    
if 'Potência Nominal (kW)' in df.columns:
    df['Potência Nominal (kW)'] = df.groupby('Marca')['Potência Nominal (kW)'].transform(lambda x: x.fillna(x.mean()))

if 'Consumo de Energia Elétrica (kWh)' in df.columns:
    df = df.dropna(subset=['Consumo de Energia Elétrica (kWh)']).copy()

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