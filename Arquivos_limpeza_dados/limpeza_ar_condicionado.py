import os
import re
from pathlib import Path
import pandas as pd

caminho_projeto = Path.cwd()
if caminho_projeto.name == "Notebook_limpeza_dados":
    caminho_projeto = caminho_projeto.parent

caminho_entrada = caminho_projeto / "Datasets" / "Ar-condicionado.csv"
caminho_saida = caminho_projeto / "Datasets" / "ar-condicionado_limpo.csv"

try:
    df = pd.read_csv(caminho_entrada, encoding='utf-8')
    if len(df.columns) == 1:
        df = pd.read_csv(caminho_entrada, encoding='utf-8', sep=';')
except:
    df = pd.read_csv(caminho_entrada, encoding='latin1', sep=';')

df.columns = df.columns.str.replace('ï»¿', '').str.strip()

df = df.dropna(subset=['Marca', 'Modelo']).drop_duplicates()

def extrair_btu(modelo):
    match = re.search(r'(07|09|12|18|22|24|30|36|48|60)', str(modelo))
    return float(match.group(1)) * 1000 if match else None

df['BTU_Extraido'] = df['Modelo'].apply(extrair_btu)
df['Capacidade_BTU'] = df['Capacidade de Refrigeração Nominal (Btu/h)'].fillna(df['BTU_Extraido'])

df['Consumo_Anual_kWh'] = df.groupby(['Marca', 'Capacidade_BTU'])['Consumo Anual de Energia (kWh)'].transform(lambda x: x.fillna(x.mean()))
df['Potencia_W'] = df.groupby(['Marca', 'Capacidade_BTU'])['Potência Consumida a 35 °C e em Carga Total (W)'].transform(lambda x: x.fillna(x.mean()))

df = df.dropna(subset=['Consumo_Anual_kWh', 'Potencia_W'], how='all').copy()

if "Código de Barras" in df.columns:
    df["Código de Barras"] = (
        df["Código de Barras"]
        .fillna("N/A")
        .astype(str)
        .str.replace(r"\.0$", "", regex=True)
    )

df = df.drop(columns=['BTU_Extraido'])
df.to_csv(caminho_saida, index=False, encoding="utf-8")

if caminho_entrada.exists():
    os.remove(caminho_entrada)
    print(f"✓ Arquivo original deletado: {caminho_entrada.name}")

print(f"✓ Dataset limpo salvo em: {caminho_saida}")