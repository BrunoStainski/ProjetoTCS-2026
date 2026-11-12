
from pathlib import Path
import pandas as pd
from config import read_csv_inmetro, save_processed
import numpy as np

df = read_csv_inmetro("ventiladores-de-teto.csv")

print("Dados originais:", df.shape)

# Remover colunas administrativas
remove_columns = [
    "Código de Barras",
    "Status do Modelo",
    "Status do Registro",
    "Número do Registro"
]

df = df.drop(columns=remove_columns, errors="ignore")

# Remover duplicatas exatas
df = df.drop_duplicates()

# Colunas de consumo
consumption_columns = [
    "Consumo de energia mensal na vel. alta (kWh/mês)",
    "Consumo de energia mensal na vel. média (kWh/mês)",
    "Consumo de energia mensal na vel. baixa (kWh/mês)"
]

# Converter consumos para números
for column in consumption_columns:
    df[column] = pd.to_numeric(
        df[column], errors="coerce"
    )

# Valores negativos são inválidos
for column in consumption_columns:
    df.loc[df[column] < 0, column] = np.nan

# Remover linhas sem nenhum consumo informado
df = df.dropna(subset=consumption_columns, how="all")

# Manter o registro mais completo por marca e modelo
df["_completude"] = df.notna().sum(axis=1)

df = (
    df.sort_values("_completude", ascending=False)
    .drop_duplicates(subset=["Marca", "Modelo"])
    .drop(columns=["_completude"])
)

save_processed(df, "ventiladores_teto_limpo.csv")

print("\nLimpeza concluída!")
print("Dados finais:", df.shape)
