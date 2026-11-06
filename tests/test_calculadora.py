"""Regras de calculo (calculadora_residencial.py). Nao precisam de banco."""

import pytest

from calculadora_residencial import (
    AVISO_PADRAO, AVISO_TARIFA_USUARIO, HORAS_OPCIONAIS, HORAS_REFERENCIA_INMETRO, PREMISSAS,
    consumo_mensal_kwh, montar_resultado, normalizar,
)
from conftest import aparelho


# Regra 3: potencia x horas ---------------------------------------------------------------

def test_chuveiro_exemplo_de_referencia():
    """Exemplo do CLAUDE.md: 5500 W, 15 min/dia, 30 dias = 41,25 kWh."""
    r = consumo_mensal_kwh(aparelho("chuveiro", potencia_w=5500), horas_dia=0.25)
    assert r["kwh_mes"] == pytest.approx(41.25)
    assert r["premissa"] is False


def test_chuveiro_exige_horas_do_usuario():
    with pytest.raises(ValueError, match="horas"):
        consumo_mensal_kwh(aparelho("chuveiro", potencia_w=5500))


def test_lampada_usa_premissa_do_grupo_e_avisa():
    horas = PREMISSAS["lampada_led"]["horas_dia"]
    r = consumo_mensal_kwh(aparelho("lampada_led", potencia_w=10))
    assert r["kwh_mes"] == pytest.approx(10 * horas * 30 / 1000)
    assert r["premissa"] is True
    assert "estimativa do grupo" in r["metodo"]


def test_standby_e_somado():
    r = consumo_mensal_kwh(aparelho("microondas", potencia_w=1000, standby_kwh_mes=0.5), horas_dia=0.5)
    assert r["kwh_mes"] == pytest.approx(1000 * 0.5 * 30 / 1000 + 0.5)


@pytest.mark.parametrize("horas", [-1, 24.5, 30])
def test_horas_fora_de_0_a_24_sao_rejeitadas(horas):
    with pytest.raises(ValueError, match="entre 0 e 24"):
        consumo_mensal_kwh(aparelho("chuveiro", potencia_w=5500), horas_dia=horas)


# Regra 1: kWh/mes do Inmetro --------------------------------------------------------------

def test_geladeira_usa_kwh_mes_do_inmetro():
    r = consumo_mensal_kwh(aparelho("refrigerador", kwh_mes=30.5))
    assert r["kwh_mes"] == pytest.approx(30.5)
    assert r["premissa"] is False


def test_ventilador_usa_a_velocidade_escolhida():
    v = aparelho("ventilador_de_mesa", kwh_mes=2.0, kwh_mes_baixa=1.0, kwh_mes_media=2.0, kwh_mes_alta=3.0)
    assert consumo_mensal_kwh(v, velocidade="alta")["kwh_mes"] == pytest.approx(3.0)
    assert consumo_mensal_kwh(v, velocidade="baixa")["kwh_mes"] == pytest.approx(1.0)


def test_ar_condicionado_sem_horas_usa_inmetro_e_com_horas_usa_potencia():
    ar = aparelho("ar_condicionado", kwh_mes=64.0, potencia_w=1000)
    assert consumo_mensal_kwh(ar)["kwh_mes"] == pytest.approx(64.0)
    assert consumo_mensal_kwh(ar, horas_dia=8)["kwh_mes"] == pytest.approx(1000 * 8 * 30 / 1000)


def test_tv_sem_horas_usa_inmetro_e_com_horas_reescala_pelo_ensaio():
    """Ensaio da TV: 6,59 h/dia ligada. 12 kWh/mes a 3 h/dia -> 12 x 3 / 6,59."""
    tv = aparelho("televisor", kwh_mes=12.0)
    assert HORAS_REFERENCIA_INMETRO["televisor"] == 6.59
    assert "televisor" in HORAS_OPCIONAIS
    assert consumo_mensal_kwh(tv)["kwh_mes"] == pytest.approx(12.0)
    r = consumo_mensal_kwh(tv, horas_dia=3)
    assert r["kwh_mes"] == pytest.approx(12 * 3 / 6.59)
    assert "6.59" in r["metodo"]


# Regra 2: kWh/ciclo x ciclos ------------------------------------------------------------

def test_maquina_de_lavar_com_ciclos_informados():
    r = consumo_mensal_kwh(aparelho("maquina_de_lavar", kwh_ciclo=0.27), ciclos_mes=20)
    assert r["kwh_mes"] == pytest.approx(5.4)
    assert r["premissa"] is False


def test_maquina_de_lavar_sem_ciclos_usa_premissa():
    ciclos = PREMISSAS["maquina_de_lavar"]["ciclos_mes"]
    r = consumo_mensal_kwh(aparelho("maquina_de_lavar", kwh_ciclo=0.27))
    assert r["kwh_mes"] == pytest.approx(0.27 * ciclos)
    assert r["premissa"] is True


def test_aparelho_sem_nenhum_dado_de_consumo():
    with pytest.raises(ValueError, match="sem dados"):
        consumo_mensal_kwh(aparelho("televisor"))


# Resultado ------------------------------------------------------------------------------

def test_custo_mensal_e_anual():
    a = aparelho("chuveiro", potencia_w=5500)
    consumo = consumo_mensal_kwh(a, horas_dia=0.25)
    r = montar_resultado(a, consumo, 0.768, "COPEL-DIS", "ANEEL", "PR", horas_dia=0.25)
    assert r["kwh_mes"] == 41.25
    assert r["custo_mes"] == pytest.approx(31.68)
    assert r["custo_ano"] == pytest.approx(31.68 * 12)
    assert AVISO_PADRAO in r["avisos"]


def test_tarifa_da_conta_troca_o_aviso_de_impostos():
    a = aparelho("refrigerador", kwh_mes=30)
    r = montar_resultado(a, consumo_mensal_kwh(a), 0.9, None, "conta", None, tarifa_do_usuario=True)
    assert AVISO_TARIFA_USUARIO in r["avisos"]
    assert AVISO_PADRAO not in r["avisos"]
    assert r["distribuidora"] == "-" and r["uf"] == "-"


def test_premissa_e_consumo_imputado_geram_avisos():
    a = aparelho("lampada_led", potencia_w=10, origem_dado="derivado ou estimado na limpeza")
    r = montar_resultado(a, consumo_mensal_kwh(a), 0.8, "X", "ANEEL", "SP")
    assert any("estimativa do grupo" in aviso for aviso in r["avisos"])
    assert any("completado na limpeza" in aviso for aviso in r["avisos"])


def test_normalizar_tira_acento_e_simbolos():
    assert normalizar("  Geladeira BRASTEMP/Frost-Free ") == "geladeira brastemp frost free"
    assert normalizar("Ação Ônibus") == "acao onibus"
