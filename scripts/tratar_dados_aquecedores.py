"""Limpeza do dataset INMETRO de aquecedores de água a gás."""

import pandas as pd

from config import filter_included_models, read_csv_inmetro, save_processed

ADMINISTRATIVE_COLUMNS = ["Status do Modelo", "Código de Barras", "Status do Registro", "Número do Registro"]

df = read_csv_inmetro("aquecedores-de-agua-e-gas.csv")
print("Dados originais:", df.shape)

df = filter_included_models(df)
df = df.drop(columns=ADMINISTRATIVE_COLUMNS, errors="ignore")
df = df.dropna(subset=["Marca", "Modelo"]).drop_duplicates()

col_consumption = next((c for c in df.columns if "Consumo" in c), None)
col_flow = next((c for c in df.columns if "Vazão" in c or "Capacidade" in c), None)

if col_consumption and col_flow:
    for col in (col_consumption, col_flow):
        df[col] = pd.to_numeric(df[col].astype(str).str.replace(",", "."), errors="coerce")
    # Imputa consumo pela média de aparelhos da mesma marca e mesma vazão
    df[col_consumption] = df.groupby(["Marca", col_flow])[col_consumption].transform(lambda x: x.fillna(x.mean()))

df = df.drop_duplicates(subset=["Marca", "Modelo"])

save_processed(df, "aquecedores-de-agua-e-gas_limpo.csv")
