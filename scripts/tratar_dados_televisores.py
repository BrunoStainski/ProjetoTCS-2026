
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

# Consumo com a virgula deslocada ------------------------------------------------------
# Comparando kWh/mes por polegada, alguns registros estao 10x acima (ex.: 43" com 84 kWh)
# ou 10x abaixo (ex.: 65" com 1,71 kWh) do resto. Erro de digitacao no cadastro do Inmetro.
# Regra: mais de 4x a mediana -> divide por 10; menos de 1/4 da mediana -> multiplica por 10.
# A linha fica marcada em consumo_imputado, e o app avisa que o valor foi corrigido.
coluna_polegadas = "Diagonal em polegadas"
df[coluna_polegadas] = pd.to_numeric(df[coluna_polegadas], errors="coerce")
por_polegada = df[coluna_consumo] / df[coluna_polegadas].where(df[coluna_polegadas] > 0)
mediana = por_polegada.median()
alto = por_polegada > mediana * 4
baixo = por_polegada < mediana / 4
df.loc[alto, coluna_consumo] = df.loc[alto, coluna_consumo] / 10
df.loc[baixo, coluna_consumo] = df.loc[baixo, coluna_consumo] * 10
df["consumo_imputado"] = alto | baixo
df["correcao_consumo"] = ""
df.loc[alto, "correcao_consumo"] = "dividido por 10 (virgula deslocada)"
df.loc[baixo, "correcao_consumo"] = "multiplicado por 10 (virgula deslocada)"
print(f"Consumo corrigido: {alto.sum()} divididos por 10, {baixo.sum()} multiplicados por 10 "
      f"(mediana {mediana:.3f} kWh/mes por polegada)")

# Stand-by suspeito --------------------------------------------------------------------
# Acima de 10 W em espera quase sempre e a potencia LIGADA digitada no campo errado
# (TVs atuais ficam abaixo de 1 W). Marcado pelo grupo; o valor original fica no raw.
coluna_standby = "Potência Modo Espera (Stand-by) (W)"
df[coluna_standby] = pd.to_numeric(df[coluna_standby], errors="coerce")
df["standby_suspeito"] = df[coluna_standby] > 10
df.loc[df["standby_suspeito"], coluna_standby] = pd.NA
print(f"Stand-by suspeito (> 10 W) apagado em {df['standby_suspeito'].sum()} modelos")

salvar_processado(df, "televisores_limpo.csv")

print("\nLimpeza concluída!")
print("Dados finais:", df.shape)
