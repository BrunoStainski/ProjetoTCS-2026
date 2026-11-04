"""Limpeza do dataset INMETRO de fornos elétricos comerciais."""

import pandas as pd

from config import filtrar_modelos_incluidos, ler_csv_inmetro, salvar_processado

COLUNAS_ADMINISTRATIVAS = ["Status do Modelo", "Código de Barras", "Status do Registro", "Número do Registro"]
COL_CONSUMO = "Consumo de Energia Elétrica (kWh)"
COL_POTENCIA = "Potência Nominal (kW)"

df = ler_csv_inmetro("fornos-eletricos-comerciais.csv")
print("Dados originais:", df.shape)

df = filtrar_modelos_incluidos(df)
df = df.drop(columns=COLUNAS_ADMINISTRATIVAS, errors="ignore")
df = df.dropna(subset=["Marca", "Modelo"]).drop_duplicates()

for col in (COL_CONSUMO, COL_POTENCIA):
    df[col] = pd.to_numeric(df[col].astype(str).str.replace(",", "."), errors="coerce")
    # Imputa pela média da própria marca
    df[col] = df.groupby("Marca")[col].transform(lambda x: x.fillna(x.mean()))

df = df.dropna(subset=[COL_CONSUMO])
df = df.drop_duplicates(subset=["Marca", "Modelo"])

salvar_processado(df, "fornos-eletricos-comerciais_limpo.csv")
