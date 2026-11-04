"""Limpeza do dataset INMETRO de ar-condicionado."""

import re

import pandas as pd

from config import filtrar_modelos_incluidos, ler_csv_inmetro, salvar_processado

COLUNAS_ADMINISTRATIVAS = ["Status do Modelo", "Código de Barras", "Status do Registro", "Número do Registro"]
COL_BTU = "Capacidade de Refrigeração Nominal (Btu/h)"
COL_CONSUMO = "Consumo Anual de Energia (kWh)"
COL_POTENCIA = "Potência Consumida a 35 °C e em Carga Total (W)"

CAPACIDADES_BTU = "07|09|12|18|22|24|30|36|48|60"


def extrair_btu(modelo) -> float | None:
    """Extrai a capacidade do nome do modelo (ex.: 'XYZ12FC' -> 12000).

    Só aceita o número isolado (sem outros dígitos colados), para não
    confundir códigos como '2012' ou '120' com 12.000 BTU.
    """
    match = re.search(rf"(?<!\d)({CAPACIDADES_BTU})(?!\d)", str(modelo))
    return float(match.group(1)) * 1000 if match else None


df = ler_csv_inmetro("ar-condicionado.csv")
print("Dados originais:", df.shape)

df = filtrar_modelos_incluidos(df)
df = df.drop(columns=COLUNAS_ADMINISTRATIVAS, errors="ignore")
df = df.dropna(subset=["Marca", "Modelo"]).drop_duplicates()

for col in (COL_BTU, COL_CONSUMO, COL_POTENCIA):
    df[col] = pd.to_numeric(df[col].astype(str).str.replace(",", "."), errors="coerce")

# Capacidade: usa o valor oficial; só recorre ao nome do modelo quando falta
df["Capacidade_BTU"] = df[COL_BTU].fillna(df["Modelo"].apply(extrair_btu))

# Imputa consumo/potência pela média de aparelhos da mesma marca e capacidade
grupos = df.groupby(["Marca", "Capacidade_BTU"])
df["Consumo_Anual_kWh"] = grupos[COL_CONSUMO].transform(lambda x: x.fillna(x.mean()))
df["Potencia_W"] = grupos[COL_POTENCIA].transform(lambda x: x.fillna(x.mean()))

df = df.dropna(subset=["Consumo_Anual_kWh", "Potencia_W"], how="all")
df = df.drop_duplicates(subset=["Marca", "Modelo"])

salvar_processado(df, "ar-condicionado_limpo.csv")
