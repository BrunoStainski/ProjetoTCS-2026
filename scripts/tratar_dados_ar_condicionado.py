"""Limpeza do dataset INMETRO de ar-condicionado."""

import re

import pandas as pd

from config import filter_included_models, read_csv_inmetro, save_processed

ADMINISTRATIVE_COLUMNS = ["Status do Modelo", "Código de Barras", "Status do Registro", "Número do Registro"]
COL_BTU = "Capacidade de Refrigeração Nominal (Btu/h)"
COL_CONSUMPTION = "Consumo Anual de Energia (kWh)"
COL_POWER = "Potência Consumida a 35 °C e em Carga Total (W)"

CAPACITIES_BTU = "07|09|12|18|22|24|30|36|48|60"


def extract_btu(model) -> float | None:
    """Extrai a capacidade do nome do modelo (ex.: 'XYZ12FC' -> 12000).

    Só aceita o número isolado (sem outros dígitos colados), para não
    confundir códigos como '2012' ou '120' com 12.000 BTU.
    """
    match = re.search(rf"(?<!\d)({CAPACITIES_BTU})(?!\d)", str(model))
    return float(match.group(1)) * 1000 if match else None


df = read_csv_inmetro("ar-condicionado.csv")
print("Dados originais:", df.shape)

df = filter_included_models(df)
df = df.drop(columns=ADMINISTRATIVE_COLUMNS, errors="ignore")
df = df.dropna(subset=["Marca", "Modelo"]).drop_duplicates()

for col in (COL_BTU, COL_CONSUMPTION, COL_POWER):
    df[col] = pd.to_numeric(df[col].astype(str).str.replace(",", "."), errors="coerce")

# Capacidade: usa o valor oficial; só recorre ao nome do modelo quando falta
df["Capacidade_BTU"] = df[COL_BTU].fillna(df["Modelo"].apply(extract_btu))

# Imputa consumo/potência pela média de aparelhos da mesma marca e capacidade
groups = df.groupby(["Marca", "Capacidade_BTU"])
df["Consumo_Anual_kWh"] = groups[COL_CONSUMPTION].transform(lambda x: x.fillna(x.mean()))
df["Potencia_W"] = groups[COL_POWER].transform(lambda x: x.fillna(x.mean()))

df = df.dropna(subset=["Consumo_Anual_kWh", "Potencia_W"], how="all")
df = df.drop_duplicates(subset=["Marca", "Modelo"])

save_processed(df, "ar-condicionado_limpo.csv")
