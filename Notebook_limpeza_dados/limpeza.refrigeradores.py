import os
import re
from pathlib import Path
import pandas as pd

caminho_projeto = Path.cwd()
if caminho_projeto.name == "Notebook_limpeza_dados":
    caminho_projeto = caminho_projeto.parent

caminho_entrada = caminho_projeto / "Datasets" / "datasetRefrigerador.csv"
caminho_saida = caminho_projeto / "Datasets" / "refrigeradores_limpo.csv"

try:
    df = pd.read_csv(caminho_entrada, encoding='utf-8')
    if len(df.columns) == 1:
        df = pd.read_csv(caminho_entrada, encoding='utf-8', sep=';')
except:
    df = pd.read_csv(caminho_entrada, encoding='latin1', sep=';')

df.columns = df.columns.str.replace('ï»¿', '').str.strip()

df = df.dropna(subset=['Marca', 'Modelo']).drop_duplicates()

if 'Consumo Médio de Energia Mensal (kWh/mês)' in df.columns and 'Consumo de Energia Mensal (kWh/mês)' in df.columns:
    df['Consumo_Mensal_kWh'] = df['Consumo Médio de Energia Mensal (kWh/mês)'].fillna(df['Consumo de Energia Mensal (kWh/mês)'])
elif 'Consumo Médio de Energia Mensal (kWh/mês)' in df.columns:
    df['Consumo_Mensal_kWh'] = df['Consumo Médio de Energia Mensal (kWh/mês)']
else:
    df['Consumo_Mensal_kWh'] = df['Consumo de Energia Mensal (kWh/mês)']

def extrair_volume(modelo):
    match = re.search(r'(\d{2,3})\s*(?:L|Lts|Litros)?\b', str(modelo), re.IGNORECASE)
    return float(match.group(1)) if match else None

df['Volume_Extraido'] = df['Modelo'].apply(extrair_volume)
df['Volume_Total_L'] = df['Volume Total (litros)'].fillna(df['Volume_Extraido'])

df['Consumo_Mensal_kWh'] = df.groupby(['Marca', 'Volume_Total_L'])['Consumo_Mensal_kWh'].transform(lambda x: x.fillna(x.mean()))

df = df.dropna(subset=['Consumo_Mensal_kWh']).copy()

if "Código de Barras" in df.columns:
    df["Código de Barras"] = (
        df["Código de Barras"]
        .fillna("N/A")
        .astype(str)
        .str.replace(r"\.0$", "", regex=True)
    )

df = df.drop(columns=['Volume_Extraido'])
df.to_csv(caminho_saida, index=False, encoding="utf-8")

if caminho_entrada.exists():
    os.remove(caminho_entrada)
    print(f"✓ Arquivo original deletado: {caminho_entrada.name}")

print(f"✓ Dataset limpo salvo em: {caminho_saida}")