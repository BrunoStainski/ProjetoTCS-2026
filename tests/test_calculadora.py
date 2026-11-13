"""Regras de calculo (calculadora_residencial.py). Nao precisam de banco."""

import pytest

from calculadora_residencial import (
    DEFAULT_NOTICE, USER_TARIFF_NOTICE, OPTIONAL_HOURS, INMETRO_REFERENCE_HOURS, ASSUMPTIONS,
    monthly_consumption_kwh, build_result, normalize,
)
from conftest import appliance


# Regra 3: potencia x horas ---------------------------------------------------------------

def test_shower_reference_example():
    """Exemplo do CLAUDE.md: 5500 W, 15 min/dia, 30 dias = 41,25 kWh."""
    r = monthly_consumption_kwh(appliance("chuveiro", potencia_w=5500), daily_hours=0.25)
    assert r["kwh_mes"] == pytest.approx(41.25)
    assert r["premissa"] is False


def test_shower_requires_user_hours():
    with pytest.raises(ValueError, match="horas"):
        monthly_consumption_kwh(appliance("chuveiro", potencia_w=5500))


def test_lamp_uses_group_assumption_and_warns():
    hours = ASSUMPTIONS["lampada_led"]["horas_dia"]
    r = monthly_consumption_kwh(appliance("lampada_led", potencia_w=10))
    assert r["kwh_mes"] == pytest.approx(10 * hours * 30 / 1000)
    assert r["premissa"] is True
    assert "estimativa do grupo" in r["metodo"]


def test_standby_is_summed():
    r = monthly_consumption_kwh(appliance("microondas", potencia_w=1000, standby_kwh_mes=0.5), daily_hours=0.5)
    assert r["kwh_mes"] == pytest.approx(1000 * 0.5 * 30 / 1000 + 0.5)


@pytest.mark.parametrize("hours", [-1, 24.5, 30])
def test_hours_outside_0_24_are_rejected(hours):
    with pytest.raises(ValueError, match="entre 0 e 24"):
        monthly_consumption_kwh(appliance("chuveiro", potencia_w=5500), daily_hours=hours)


# Regra 1: kWh/mes do Inmetro --------------------------------------------------------------

def test_fridge_uses_inmetro_monthly_kwh():
    r = monthly_consumption_kwh(appliance("refrigerador", kwh_mes=30.5))
    assert r["kwh_mes"] == pytest.approx(30.5)
    assert r["premissa"] is False


def test_fan_uses_chosen_speed():
    v = appliance("ventilador_de_mesa", kwh_mes=2.0, kwh_mes_baixa=1.0, kwh_mes_media=2.0, kwh_mes_alta=3.0)
    assert monthly_consumption_kwh(v, speed="alta")["kwh_mes"] == pytest.approx(3.0)
    assert monthly_consumption_kwh(v, speed="baixa")["kwh_mes"] == pytest.approx(1.0)


def test_fan_multiplies_inmetro_1_hour_consumption_by_hours():
    v = appliance("ventilador_de_mesa", kwh_mes=2.0, kwh_mes_baixa=1.0, kwh_mes_media=2.0, kwh_mes_alta=3.0)
    assert INMETRO_REFERENCE_HOURS["ventilador_de_mesa"] == 1.0
    r = monthly_consumption_kwh(v, speed="alta", daily_hours=8)
    assert r["kwh_mes"] == pytest.approx(24.0)
    assert "velocidade alta" in r["metodo"] and "8 h/dia" in r["metodo"]
    assert monthly_consumption_kwh(v, daily_hours=8)["kwh_mes"] == pytest.approx(16.0)


def test_air_conditioner_without_hours_uses_inmetro_and_with_hours_uses_power():
    ar = appliance("ar_condicionado", kwh_mes=64.0, potencia_w=1000)
    assert monthly_consumption_kwh(ar)["kwh_mes"] == pytest.approx(64.0)
    assert monthly_consumption_kwh(ar, daily_hours=8)["kwh_mes"] == pytest.approx(1000 * 8 * 30 / 1000)


def test_tv_without_hours_uses_inmetro_and_with_hours_rescales_by_lab_test():
    """Ensaio da TV: 6,59 h/dia ligada. 12 kWh/mes a 3 h/dia -> 12 x 3 / 6,59."""
    tv = appliance("televisor", kwh_mes=12.0)
    assert INMETRO_REFERENCE_HOURS["televisor"] == 6.59
    assert "televisor" in OPTIONAL_HOURS
    assert monthly_consumption_kwh(tv)["kwh_mes"] == pytest.approx(12.0)
    r = monthly_consumption_kwh(tv, daily_hours=3)
    assert r["kwh_mes"] == pytest.approx(12 * 3 / 6.59)
    assert "6.59" in r["metodo"]


# Regra 2: kWh/ciclo x ciclos ------------------------------------------------------------

def test_washing_machine_with_given_cycles():
    r = monthly_consumption_kwh(appliance("maquina_de_lavar", kwh_ciclo=0.27), monthly_cycles=20)
    assert r["kwh_mes"] == pytest.approx(5.4)
    assert r["premissa"] is False


def test_washing_machine_without_cycles_uses_assumption():
    cycles = ASSUMPTIONS["maquina_de_lavar"]["ciclos_mes"]
    r = monthly_consumption_kwh(appliance("maquina_de_lavar", kwh_ciclo=0.27))
    assert r["kwh_mes"] == pytest.approx(0.27 * cycles)
    assert r["premissa"] is True


def test_appliance_without_any_consumption_data():
    with pytest.raises(ValueError, match="sem dados"):
        monthly_consumption_kwh(appliance("televisor"))


# Resultado ------------------------------------------------------------------------------

def test_monthly_and_yearly_cost():
    a = appliance("chuveiro", potencia_w=5500)
    consumption = monthly_consumption_kwh(a, daily_hours=0.25)
    r = build_result(a, consumption, 0.768, "COPEL-DIS", "ANEEL", "PR", daily_hours=0.25)
    assert r["kwh_mes"] == 41.25
    assert r["custo_mes"] == pytest.approx(31.68)
    assert r["custo_ano"] == pytest.approx(31.68 * 12)
    assert DEFAULT_NOTICE in r["avisos"]


def test_bill_tariff_changes_tax_notice():
    a = appliance("refrigerador", kwh_mes=30)
    r = build_result(a, monthly_consumption_kwh(a), 0.9, None, "conta", None, user_tariff=True)
    assert USER_TARIFF_NOTICE in r["avisos"]
    assert DEFAULT_NOTICE not in r["avisos"]
    assert r["distribuidora"] == "-" and r["uf"] == "-"


def test_assumption_and_imputed_consumption_generate_notices():
    a = appliance("lampada_led", potencia_w=10, origem_dado="derivado ou estimado na limpeza")
    r = build_result(a, monthly_consumption_kwh(a), 0.8, "X", "ANEEL", "SP")
    assert any("estimativa do grupo" in notice for notice in r["avisos"])
    assert any("completado na limpeza" in notice for notice in r["avisos"])


def test_normalize_removes_accent_and_symbols():
    assert normalize("  Geladeira BRASTEMP/Frost-Free ") == "geladeira brastemp frost free"
    assert normalize("Ação Ônibus") == "acao onibus"


# Tensao (127 V x 220 V) --------------------------------------------------------------------------

def _versions(*rows):
    import pandas as pd
    columns = ["categoria", "marca", "modelo", "tensao", "detalhe", "kwh_mes", "kwh_ciclo", "potencia_w", "standby_kwh_mes"]
    return pd.DataFrame([dict(zip(columns, r)) for r in rows])


def test_voltage_versions_that_use_different_power_are_both_kept():
    from calculadora_residencial import keep_voltage_versions
    nan = float("nan")
    catalog = keep_voltage_versions(_versions(
        ("chuveiro", "CARDAL", "DUCHA", "127", "5500 W", nan, nan, 5500, nan),
        ("chuveiro", "CARDAL", "DUCHA", "220", "7600 W", nan, nan, 7600, nan),
        ("chuveiro", "CARDAL", "DUCHA", "220", "7600 W", nan, nan, 7600, nan),  # linha repetida no Inmetro
    ))
    assert list(catalog["detalhe"]) == ["5500 W · 127 V", "7600 W · 220 V"]
    assert list(catalog["tensao"]) == ["127", "220"]


def test_same_consumption_in_both_voltages_is_one_row_for_both():
    from calculadora_residencial import keep_voltage_versions
    nan = float("nan")
    catalog = keep_voltage_versions(_versions(
        ("maquina_de_lavar", "LG", "WM", "127", "12 kg", nan, 0.2, nan, nan),
        ("maquina_de_lavar", "LG", "WM", "220", "12 kg", nan, 0.2, nan, nan),
    ))
    assert len(catalog) == 1
    assert catalog.iloc[0]["tensao"] == "" and catalog.iloc[0]["detalhe"] == "12 kg"


def test_model_sold_in_one_voltage_keeps_it_and_other_categories_have_none():
    from calculadora_residencial import keep_voltage_versions
    nan = float("nan")
    catalog = keep_voltage_versions(_versions(
        ("maquina_de_lavar", "LG", "SO220", "220", "16 kg", nan, 0.3, nan, nan),
        ("refrigerador", "CONSUL", "CRM", "", "375 L", 40, nan, nan, nan),
        ("refrigerador", "CONSUL", "CRM", "", "375 L", 41, nan, nan, nan),  # sem tensao: fica a 1a, como antes
    ))
    assert list(catalog["tensao"]) == ["220", ""]
    assert list(catalog["detalhe"]) == ["16 kg · 220 V", "375 L"]
