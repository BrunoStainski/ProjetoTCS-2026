"""Limpeza do dataset INMETRO de fornos elétricos comerciais."""

import pandas as pd

from config import filter_included_models, read_csv_inmetro, save_processed

ADMINISTRATIVE_COLUMNS = ["Status do Modelo", "Código de Barras", "Status do Registro", "Número do Registro"]
COL_CONSUMPTION = "Consumo de Energia Elétrica (kWh)"
COL_POWER = "Potência Nominal (kW)"

df = read_csv_inmetro("fornos-eletricos-comerciais.csv")
print("Dados originais:", df.shape)

df = filter_included_models(df)
df = df.drop(columns=ADMINISTRATIVE_COLUMNS, errors="ignore")
df = df.dropna(subset=["Marca", "Modelo"]).drop_duplicates()

for col in (COL_CONSUMPTION, COL_POWER):
    df[col] = pd.to_numeric(df[col].astype(str).str.replace(",", "."), errors="coerce")
    # Imputa pela média da própria marca
    df[col] = df.groupby("Marca")[col].transform(lambda x: x.fillna(x.mean()))

df = df.dropna(subset=[COL_CONSUMPTION])
df = df.drop_duplicates(subset=["Marca", "Modelo"])

save_processed(df, "fornos-eletricos-comerciais_limpo.csv")
