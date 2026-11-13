
import pandas as pd
from config import read_csv_inmetro, save_processed

df = read_csv_inmetro("televisores.csv")

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

# Converter consumo para número
consumption_column = "Consumo (kWh/mês)"

df[consumption_column] = pd.to_numeric(
    df[consumption_column], errors="coerce"
)

# Remover registros sem consumo válido
df = df[
    df[consumption_column].notna()
    & (df[consumption_column] > 0)
].copy()

# Manter o registro mais completo por marca e modelo
df["_completude"] = df.notna().sum(axis=1)

df = (
    df.sort_values("_completude", ascending=False)
    .drop_duplicates(subset=["Marca", "Modelo"])
    .drop(columns=["_completude"])
)

# Consumo com a virgula deslocada ------------------------------------------------------
# Comparando kWh/mes por polegada, alguns registros estao 10x acima (ex.: 43" com 84 kWh)
# ou 10x abaixo (ex.: 65" com 1,71 kWh) do resto. Erro de digitacao no cadastro do Inmetro.
# Regra: mais de 4x a mediana -> divide por 10; menos de 1/4 da mediana -> multiplica por 10.
# A linha fica marcada em consumo_imputado, e o app avisa que o valor foi corrigido.
inch_column = "Diagonal em polegadas"
df[inch_column] = pd.to_numeric(df[inch_column], errors="coerce")
by_inch = df[consumption_column] / df[inch_column].where(df[inch_column] > 0)
median = by_inch.median()
too_high = by_inch > median * 4
low = by_inch < median / 4
df.loc[too_high, consumption_column] = df.loc[too_high, consumption_column] / 10
df.loc[low, consumption_column] = df.loc[low, consumption_column] * 10
df["consumo_imputado"] = too_high | low
df["correcao_consumo"] = ""
df.loc[too_high, "correcao_consumo"] = "dividido por 10 (virgula deslocada)"
df.loc[low, "correcao_consumo"] = "multiplicado por 10 (virgula deslocada)"
print(f"Consumo corrigido: {too_high.sum()} divididos por 10, {low.sum()} multiplicados por 10 "
      f"(mediana {median:.3f} kWh/mes por polegada)")

# Stand-by suspeito --------------------------------------------------------------------
# Acima de 10 W em espera quase sempre e a potencia LIGADA digitada no campo errado
# (TVs atuais ficam abaixo de 1 W). Marcado pelo grupo; o valor original fica no raw.
standby_column = "Potência Modo Espera (Stand-by) (W)"
df[standby_column] = pd.to_numeric(df[standby_column], errors="coerce")
df["standby_suspeito"] = df[standby_column] > 10
df.loc[df["standby_suspeito"], standby_column] = pd.NA
print(f"Stand-by suspeito (> 10 W) apagado em {df['standby_suspeito'].sum()} modelos")

save_processed(df, "televisores_limpo.csv")

print("\nLimpeza concluída!")
print("Dados finais:", df.shape)
