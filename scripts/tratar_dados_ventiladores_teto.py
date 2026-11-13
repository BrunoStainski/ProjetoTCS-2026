
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

# Consumo impossível ------------------------------------------------------------------------
# O kWh/mês do Inmetro é de 1 h por dia (potência x 30 h). Acima de 8 kWh o motor teria mais de 260 W,
# e a distribuição tem um vazio entre 8 e 10: os valores acima (até 65 kWh) são erro de cadastro.
# A potência do próprio ensaio (vazão / eficiência) refaz o consumo quando dá um motor plausível;
# senão, a velocidade fica sem consumo. A linha fica marcada em consumo_imputado (o app avisa e
# não sugere o modelo) e o motivo em correcao_consumo. O valor original continua no arquivo bruto.
MAX_KWH_MONTH = 8.0
# o valor refeito e uma segunda estimativa (a vazao ou a eficiencia tambem podem estar erradas),
# entao a regua e mais rigida que o teto de 8 kWh (266 W)
PLAUSIBLE_POWER_W = (10, 200)
SPEEDS = {"alta": "alta", "média": "media", "baixa": "baixa"}


def _number(series):
    return pd.to_numeric(series.astype(str).str.replace(",", ".", regex=False), errors="coerce")


df["correcao_consumo"] = ""
for name in SPEEDS:
    consumption = f"Consumo de energia mensal na vel. {name} (kWh/mês)"
    power = (_number(df[f"Vazão média de ar na velocidade {name} (m³/s)"])
             / _number(df[f"Eficiência na velocidade {name} [(m³/s)/W]"]).where(lambda e: e > 0))
    impossible = df[consumption] > MAX_KWH_MONTH
    recomputed = impossible & power.between(*PLAUSIBLE_POWER_W)
    df.loc[recomputed, consumption] = (power[recomputed] * 30 / 1000).round(2)
    df.loc[impossible & ~recomputed, consumption] = np.nan
    df.loc[recomputed, "correcao_consumo"] += f"vel. {name}: refeito pela vazão / eficiência; "
    df.loc[impossible & ~recomputed, "correcao_consumo"] += f"vel. {name}: apagado (sem potência plausível); "
    print(f"Velocidade {name}: {impossible.sum()} acima de {MAX_KWH_MONTH:g} kWh/mês "
          f"({recomputed.sum()} refeitos pela vazão / eficiência, {(impossible & ~recomputed).sum()} apagados)")
df["correcao_consumo"] = df["correcao_consumo"].str.rstrip("; ")
df["consumo_imputado"] = df["correcao_consumo"] != ""

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
