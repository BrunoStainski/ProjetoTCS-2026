
from pathlib import Path
import pandas as pd
from config import ler_csv_inmetro, salvar_processado

df = ler_csv_inmetro("televisores.csv")

print("Dados originais:", df.shape)

# Remover colunas administrativas
colunas_remover = [
    "Código de Barras",
    "Status do Modelo",
    "Status do Registro",
    "Número do Registro"
]

df = df.drop(columns=colunas_remover, errors="ignore")

# Remover duplicatas exatas
df = df.drop_duplicates()

# Converter consumo para número
coluna_consumo = "Consumo (kWh/mês)"

df[coluna_consumo] = pd.to_numeric(
    df[coluna_consumo], errors="coerce"
)

# Remover registros sem consumo válido
df = df[
    df[coluna_consumo].notna()
    & (df[coluna_consumo] > 0)
].copy()

# Manter o registro mais completo por marca e modelo
df["_completude"] = df.notna().sum(axis=1)

df = (
    df.sort_values("_completude", ascending=False)
    .drop_duplicates(subset=["Marca", "Modelo"])
    .drop(columns=["_completude"])
)

salvar_processado(df, "televisores_limpo.csv")

print("\nLimpeza concluída!")
print("Dados finais:", df.shape)
