
from pathlib import Path
import pandas as pd
from config import read_csv_inmetro, save_processed
import numpy as np

df = read_csv_inmetro("lampadas-led-dispositivo-integrado-a-base.csv")

print("Dados originais:", df.shape)

# 3. Manter somente modelos incluídos e registros ativos
df = df[
    (df["Status do Modelo"] == "Incluido") &
    (df["Status do Registro"] == "Ativo")
].copy()

# 4. Remover colunas administrativas e equivalências
remove_columns = [
    "Status do Modelo",
    "Status do Registro",
    "Código de Barras",
    "Número do Registro",
    "Equivalência lâmpada Incandescente",
    "Equivalência lâmpada fluorescente compacta"
]

df = df.drop(columns=remove_columns, errors="ignore")

# 5. Converter colunas numéricas
numeric_columns = [
    "Tensão (V)",
    "Potência (W)",
    "Fluxo Luminoso (lm)",
    "TCC (K)",
    "IRC",
    "Vida Útil Nominal (horas)",
    "Eficiência Luminosa (lm/W)",
    "Fator de Potência (cos ?)"
]

for column in numeric_columns:
    if column in df.columns:
        df[column] = pd.to_numeric(
            df[column], errors="coerce"
        )

# 6. Remover registros sem potência válida
df = df[
    df["Potência (W)"].notna() &
    (df["Potência (W)"] > 0)
].copy()

# 7. Tratar valores numéricos inválidos
for column in numeric_columns:
    if column != "Potência (W)" and column in df.columns:
        df.loc[df[column] <= 0, column] = np.nan

# 8. Remover duplicatas exatas
df = df.drop_duplicates()

# 9. Manter o registro mais completo por marca e modelo
df["_completude"] = df.notna().sum(axis=1)

df = (
    df.sort_values("_completude", ascending=False)
    .drop_duplicates(subset=["Marca", "Modelo"])
    .drop(columns=["_completude"])
)

save_processed(df, "lampadas_led_limpo.csv")

print("\nLimpeza concluída!")
print("Dados finais:", df.shape)
print("\nColunas mantidas:")
print(df.columns.tolist())
