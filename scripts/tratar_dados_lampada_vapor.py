
from pathlib import Path
import pandas as pd
from config import read_csv_inmetro, save_processed

df = read_csv_inmetro("lampadas-de-vapor-de-sodio-de-alta-pressao.csv")

print("Dados originais:", df.shape)

# Manter somente registros ativos
df = df[df["Status do Registro"] == "Ativo"].copy()

# Converter potência e tensão
df["Potência (W)"] = pd.to_numeric(
    df["Potência (W)"], errors="coerce"
)

df["Tensão (V)"] = pd.to_numeric(
    df["Tensão (V)"], errors="coerce"
)

# Remover registros sem potência válida
df = df[
    df["Potência (W)"].notna()
    & (df["Potência (W)"] > 0)
]

# Manter somente colunas úteis
df = df[
    ["Marca", "Modelo", "Tensão (V)", "Potência (W)"]
].copy()

# Remover duplicatas
df = df.drop_duplicates(subset=["Marca", "Modelo"])

save_processed(df, "lampadas_vapor_sodio_limpo.csv")

print("\nLimpeza concluída!")
print("Dados finais:", df.shape)
