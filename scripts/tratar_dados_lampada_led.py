
from pathlib import Path
import pandas as pd
from config import ler_csv_inmetro, salvar_processado
import numpy as np

df = ler_csv_inmetro("lampadas-led-dispositivo-integrado-a-base.csv")

print("Dados originais:", df.shape)

# 3. Manter somente modelos incluídos e registros ativos
df = df[
    (df["Status do Modelo"] == "Incluido") &
    (df["Status do Registro"] == "Ativo")
].copy()

# 4. Remover colunas administrativas e equivalências
colunas_remover = [
    "Status do Modelo",
    "Status do Registro",
    "Código de Barras",
    "Número do Registro",
    "Equivalência lâmpada Incandescente",
    "Equivalência lâmpada fluorescente compacta"
]

df = df.drop(columns=colunas_remover, errors="ignore")

# 5. Converter colunas numéricas
colunas_numericas = [
    "Tensão (V)",
    "Potência (W)",
    "Fluxo Luminoso (lm)",
    "TCC (K)",
    "IRC",
    "Vida Útil Nominal (horas)",
    "Eficiência Luminosa (lm/W)",
    "Fator de Potência (cos ?)"
]

for coluna in colunas_numericas:
    if coluna in df.columns:
        df[coluna] = pd.to_numeric(
            df[coluna], errors="coerce"
        )

# 6. Remover registros sem potência válida
df = df[
    df["Potência (W)"].notna() &
    (df["Potência (W)"] > 0)
].copy()

# 7. Tratar valores numéricos inválidos
for coluna in colunas_numericas:
    if coluna != "Potência (W)" and coluna in df.columns:
        df.loc[df[coluna] <= 0, coluna] = np.nan

# 8. Remover duplicatas exatas
df = df.drop_duplicates()

# 9. Manter o registro mais completo por marca e modelo
df["_completude"] = df.notna().sum(axis=1)

df = (
    df.sort_values("_completude", ascending=False)
    .drop_duplicates(subset=["Marca", "Modelo"])
    .drop(columns=["_completude"])
)

salvar_processado(df, "lampadas_led_limpo.csv")

print("\nLimpeza concluída!")
print("Dados finais:", df.shape)
print("\nColunas mantidas:")
print(df.columns.tolist())
