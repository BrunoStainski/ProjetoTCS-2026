"""Limpeza do dataset INMETRO de chuveiros elétricos.

Fonte: datasets/raw/chuveiros-eletricos.csv (tabela extraída do PDF
datasets/raw/chuveiros-eletricos.pdf publicado pelo INMETRO).
"""

import pandas as pd

from config import ler_csv_inmetro, salvar_processado

df = ler_csv_inmetro("chuveiros-eletricos.csv")
qtd_inicial = len(df)

# Remove espaços extras só nos textos (sem transformar nulos na string "nan")
for col in df.select_dtypes(include=["object"]).columns:
    df[col] = df[col].str.strip()

# Correção de typo identificado na fonte
df["Modelo"] = df["Modelo"].replace(
    {"JET CONROL MULTITEMPERATURAS": "JET CONTROL MULTITEMPERATURAS"}
)

df = df.rename(columns={
    "Marca": "marca",
    "Família": "familia",
    "Modelo": "modelo",
    "Tensão (V)": "tensao_v",
    "Potência (W)": "potencia_w",
    "Consumo mensal máximo (kWh/mês)": "consumo_mensal_max_kwh",
    "Elevação de temperatura (°C)": "elevacao_temperatura_c",
    "Consumo mensal mínimo (kWh/mês)": "consumo_mensal_min_kwh",
    "Vazão (l/min)": "vazao_l_min",
})

df = df.dropna(subset=["marca", "modelo"]).drop_duplicates()

# Tipos numéricos (Int64 aceita nulos, ao contrário de int)
colunas_numericas = [
    "tensao_v", "potencia_w", "consumo_mensal_max_kwh",
    "elevacao_temperatura_c", "consumo_mensal_min_kwh", "vazao_l_min",
]
for col in colunas_numericas:
    df[col] = pd.to_numeric(df[col].astype("string").str.replace(",", "."), errors="coerce")
df["tensao_v"] = df["tensao_v"].astype("Int64")
df["potencia_w"] = df["potencia_w"].astype("Int64")

print(f"- Linhas processadas: {qtd_inicial}")
print(f"- Linhas removidas: {qtd_inicial - len(df)}")
salvar_processado(df, "chuveiros_eletricos_limpo.csv")
