"""Limpeza do dataset INMETRO de aquecedores de água a gás."""

import pandas as pd

from config import filtrar_modelos_incluidos, ler_csv_inmetro, salvar_processado

COLUNAS_ADMINISTRATIVAS = ["Status do Modelo", "Código de Barras", "Status do Registro", "Número do Registro"]

df = ler_csv_inmetro("aquecedores-de-agua-e-gas.csv")
print("Dados originais:", df.shape)

df = filtrar_modelos_incluidos(df)
df = df.drop(columns=COLUNAS_ADMINISTRATIVAS, errors="ignore")
df = df.dropna(subset=["Marca", "Modelo"]).drop_duplicates()

col_consumo = next((c for c in df.columns if "Consumo" in c), None)
col_vazao = next((c for c in df.columns if "Vazão" in c or "Capacidade" in c), None)

if col_consumo and col_vazao:
    for col in (col_consumo, col_vazao):
        df[col] = pd.to_numeric(df[col].astype(str).str.replace(",", "."), errors="coerce")
    # Imputa consumo pela média de aparelhos da mesma marca e mesma vazão
    df[col_consumo] = df.groupby(["Marca", col_vazao])[col_consumo].transform(lambda x: x.fillna(x.mean()))

df = df.drop_duplicates(subset=["Marca", "Modelo"])

salvar_processado(df, "aquecedores-de-agua-e-gas_limpo.csv")
