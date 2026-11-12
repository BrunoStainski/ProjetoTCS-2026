"""Catalogo montado dos CSVs limpos: valores impossiveis nao podem voltar. Nao precisam de banco.

Os limites sao os mesmos dos scripts de limpeza (scripts/tratar_dados_*.py).
"""

import pytest

from calculadora_residencial import load_catalog


@pytest.fixture(scope="module")
def catalog():
    return load_catalog()


def test_air_conditioner_consumption_matches_capacity(catalog):
    """Caso real: GREE GWH09QB-D3NNB4C (9.000 BTU/h) vinha com 17 kWh/ano, o app mostrava R$ 1 por mes."""
    ar = catalog[catalog["categoria"] == "ar_condicionado"]
    per_1000_btu = ar["kwh_mes"] * 12 / (ar["capacidade"] / 1000)
    assert ar["capacidade"].between(5000, 80000).all()
    assert per_1000_btu.between(20, 110).all(), ar[~per_1000_btu.between(20, 110)][["marca", "modelo"]]
    efficiency = (ar["capacidade"] / 3.412) / ar["potencia_w"]
    assert efficiency.between(2, 8).all()


def test_corrected_air_conditioner_is_not_suggested(catalog):
    """Valor refeito na limpeza nao e do Inmetro: o app avisa e o modelo nao entra nas sugestoes."""
    gree = catalog[(catalog["categoria"] == "ar_condicionado") & (catalog["modelo"] == "GWH09QB-D3NNB4C")].iloc[0]
    assert 40 < gree["kwh_mes"] < 70
    assert gree["origem_dado"] != "informado"


def test_ceiling_fan_consumption_is_possible(catalog):
    """kWh/mes de 1 h por dia: acima de 8 seria um motor de mais de 260 W (havia ate 65 kWh)."""
    fans = catalog[catalog["categoria"] == "ventilador_de_teto"]
    speeds = fans[["kwh_mes_baixa", "kwh_mes_media", "kwh_mes_alta"]]
    assert (speeds.max(axis=1) <= 8).all()
    assert fans["kwh_mes"].notna().all()
