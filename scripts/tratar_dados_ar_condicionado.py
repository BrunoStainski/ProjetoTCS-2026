"""Limpeza do dataset INMETRO de ar-condicionado.

Além de padronizar e completar o que falta, confere três números do cadastro que precisam combinar
entre si (capacidade, potência e consumo anual) e corrige os que não combinam. As linhas mexidas ficam
marcadas em `consumo_imputado` (o app avisa e elas não entram nas sugestões de troca), com o motivo
em `correcao_consumo` / `correcao_capacidade`. O valor original continua no arquivo bruto.
"""

import re

import numpy as np
import pandas as pd

from config import filter_included_models, read_csv_inmetro, save_processed

ADMINISTRATIVE_COLUMNS = ["Status do Modelo", "Código de Barras", "Status do Registro", "Número do Registro"]
COL_BTU = "Capacidade de Refrigeração Nominal (Btu/h)"
COL_CAPACITY_W = "Capacidade de Refrigeração Nominal (W)"
COL_CONSUMPTION = "Consumo Anual de Energia (kWh)"
COL_POWER = "Potência Consumida a 35 °C e em Carga Total (W)"
COL_ROTATION = "Rotação"  # "Velocidade Fixa" ou "Velocidade Variável" (inverter)

CAPACITIES_BTU = "07|09|12|18|22|24|30|36|48|60"
BTU_PER_WATT = 3.412

# Faixas do que é possível, medidas nos próprios dados (a distribuição tem um vazio antes e depois):
# - capacidade residencial e comercial leve;
# - consumo anual por 1.000 BTU/h: os modelos normais ficam entre 25 e 100. Abaixo de 10 estão os que
#   trazem o kWh/mês da etiqueta antiga (1 h por dia) no campo do consumo anual (ex.: 9.000 BTU/h com 17 kWh);
# - eficiência em carga total (capacidade em W / potência em W): fora da faixa, a potência está com a
#   vírgula deslocada (ex.: 10.000 BTU/h com 96 W).
BTU_RANGE = (5000, 80000)
KWH_PER_1000_BTU_RANGE = (20, 110)
EFFICIENCY_RANGE = (2, 8)


def extract_btu(model) -> float | None:
    """Extrai a capacidade do nome do modelo (ex.: 'XYZ12FC' -> 12000).

    Só aceita o número isolado (sem outros dígitos colados), para não
    confundir códigos como '2012' ou '120' com 12.000 BTU.
    """
    match = re.search(rf"(?<!\d)({CAPACITIES_BTU})(?!\d)", str(model))
    return float(match.group(1)) * 1000 if match else None


def fix_capacity(df: pd.DataFrame) -> pd.Series:
    """Capacidade em BTU/h conferida com a capacidade em W do mesmo cadastro.

    - os dois campos trocados (BTU/h no campo de W e vice-versa): destroca;
    - BTU/h fora da faixa (ex.: 12 no lugar de 12.000): usa a capacidade em W x 3,412;
    - sem nenhum dos dois: o número que aparece no nome do modelo.
    """
    btu, capacity_w = df[COL_BTU].copy(), df[COL_CAPACITY_W]
    reason = pd.Series("", index=df.index)

    swapped = (capacity_w / btu).between(BTU_PER_WATT * 0.9, BTU_PER_WATT * 1.1)
    btu[swapped] = capacity_w[swapped]
    reason[swapped] = "BTU/h e W estavam trocados"

    out_of_range = btu.notna() & ~btu.between(*BTU_RANGE)
    from_watts = (capacity_w * BTU_PER_WATT / 500).round() * 500
    recovered = out_of_range & from_watts.between(*BTU_RANGE)
    btu[recovered] = from_watts[recovered]
    btu[out_of_range & ~recovered] = np.nan
    reason[out_of_range] = "BTU/h fora da faixa; calculado pela capacidade em W ou pelo nome do modelo"

    df["correcao_capacidade"] = reason
    return btu.fillna(df["Modelo"].apply(extract_btu))


def check_consumption_and_power(df: pd.DataFrame) -> tuple[pd.Series, pd.Series]:
    """Consumo anual e potência com os valores impossíveis corrigidos (NaN onde não dá para corrigir).

    Os dois se ligam pelas horas por ano em carga total (consumo / potência), que quase não mudam entre
    modelos da mesma rotação (mediana: ~775 h nos de velocidade fixa e ~415 h nos inverter). Quando só um
    dos dois está fora da faixa, ele é refeito pelo outro com essa mediana.
    """
    capacity = df["Capacidade_BTU"]
    consumption, power = df[COL_CONSUMPTION], df[COL_POWER]
    per_btu = consumption / (capacity / 1000)
    efficiency = (capacity / BTU_PER_WATT) / power
    bad_consumption = per_btu.notna() & ~per_btu.between(*KWH_PER_1000_BTU_RANGE)
    bad_power = efficiency.notna() & ~efficiency.between(*EFFICIENCY_RANGE)

    trusted = consumption.notna() & power.notna() & ~bad_consumption & ~bad_power
    hours = (consumption * 1000 / power)[trusted]
    rotation = df[COL_ROTATION].fillna("")
    typical_hours = rotation.map(hours.groupby(rotation[trusted]).median()).fillna(hours.median())
    print("Horas por ano em carga total (mediana dos modelos normais):",
          hours.groupby(rotation[trusted]).median().round(0).to_dict())

    only_consumption = bad_consumption & ~bad_power & power.notna()
    only_power = bad_power & ~bad_consumption & consumption.notna()
    both = (bad_consumption | bad_power) & ~only_consumption & ~only_power

    consumption, power = consumption.copy(), power.copy()
    consumption[only_consumption] = power[only_consumption] * typical_hours[only_consumption] / 1000
    power[only_power] = consumption[only_power] * 1000 / typical_hours[only_power]
    consumption[both] = np.nan
    power[both] = np.nan

    df["correcao_consumo"] = ""
    df.loc[only_consumption, "correcao_consumo"] = (
        "consumo anual fora da faixa; refeito pela potência x horas típicas da mesma rotação")
    df.loc[only_power, "correcao_consumo"] = (
        "potência fora da faixa; refeita pelo consumo anual / horas típicas da mesma rotação")
    df.loc[both, "correcao_consumo"] = "consumo e potência fora da faixa; completados pela média da marca"
    print(f"Fora da faixa: {only_consumption.sum()} consumos refeitos pela potência, "
          f"{only_power.sum()} potências refeitas pelo consumo, {both.sum()} com os dois descartados")
    return consumption, power


df = read_csv_inmetro("ar-condicionado.csv")
print("Dados originais:", df.shape)

df = filter_included_models(df)
df = df.drop(columns=ADMINISTRATIVE_COLUMNS, errors="ignore")
df = df.dropna(subset=["Marca", "Modelo"]).drop_duplicates()

for col in (COL_BTU, COL_CAPACITY_W, COL_CONSUMPTION, COL_POWER):
    df[col] = pd.to_numeric(df[col].astype(str).str.replace(",", "."), errors="coerce")

# Capacidade: usa o valor oficial conferido; só recorre ao nome do modelo quando falta
df["Capacidade_BTU"] = fix_capacity(df)
print(f"Capacidade corrigida em {(df['correcao_capacidade'] != '').sum()} modelos")

consumption, power = check_consumption_and_power(df)

# Imputa consumo/potência pela média de aparelhos da mesma marca e capacidade
# (a média usa só os valores conferidos, para um erro de cadastro não se espalhar pela marca)
groups = [df["Marca"], df["Capacidade_BTU"]]
df["Consumo_Anual_kWh"] = consumption.fillna(consumption.groupby(groups).transform("mean"))
df["Potencia_W"] = power.fillna(power.groupby(groups).transform("mean"))
# verdadeiro quando o consumo ou a potência não são os do cadastro (o app avisa e não sugere o modelo)
df["consumo_imputado"] = df[COL_CONSUMPTION].isna() | (df["correcao_consumo"] != "")

# sem consumo não há o que mostrar (antes só saía a linha sem consumo e sem potência)
df = df.dropna(subset=["Consumo_Anual_kWh", "Potencia_W"])
df = df.drop_duplicates(subset=["Marca", "Modelo"])

save_processed(df, "ar-condicionado_limpo.csv")
