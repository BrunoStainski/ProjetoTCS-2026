import pytest

import gas

TARIFA_GAS = {"registrar": False}


def test_boca_mais_eficiente_gasta_menos_gas():
    assert gas.kg_por_hora_da_boca(68) < gas.kg_por_hora_da_boca(63) < gas.kg_por_hora_da_boca(58)
    assert gas.kg_por_hora_da_boca() == pytest.approx(1.75 / 12.8)


def test_consumo_soma_bocas_e_forno():
    fogao = {"rendimento_pct": 63, "consumo_forno_kg_h": 0.13}
    c = gas.consumo_gas(fogao, horas_bocas_dia=1, horas_forno_dia=0.5, dias_mes=30)
    assert c["kg_bocas"] == pytest.approx(1.75 / 12.8 * 30)
    assert c["kg_forno"] == pytest.approx(0.13 * 0.5 * 30)
    assert c["kg_mes"] == pytest.approx(c["kg_bocas"] + c["kg_forno"])
    assert "30 min/dia" in c["metodo"]


def test_sem_modelo_usa_medianas_e_avisa():
    c = gas.consumo_gas()
    assert gas.AVISO_SEM_MODELO in c["avisos"] and gas.AVISO_USO_PADRAO in c["avisos"]


def test_resultado_em_reais_e_botijoes():
    c = gas.consumo_gas(None, 1, 0, 30)
    r = gas.resultado_gas(c, 9.0, "teste")
    assert r["custo_mes"] == pytest.approx(round(c["kg_mes"] * 9.0, 2))
    assert r["botijoes_mes"] == pytest.approx(round(c["kg_mes"] / 13, 2))
    assert r["preco_botijao"] == 117.0


def test_tempo_invalido():
    with pytest.raises(ValueError):
        gas.consumo_gas(None, horas_bocas_dia=25)


@pytest.mark.banco
def test_api_precos_do_glp_por_estado(api):
    precos = {p["uf"]: p for p in api.get("/gas/precos").json()}
    assert len(precos) == 27 and precos["PR"]["preco_kg"] > 0 and "ANP" in precos["PR"]["fonte"]


@pytest.mark.banco
def test_api_gas_com_fogao_do_catalogo(api):
    fogao = api.get("/fogoes", params={"busca": "itatiaia"}).json()[0]
    r = api.post("/calcular/gas", json={"fogao_id": fogao["id"], "horas_bocas_dia": 1, "horas_forno_dia": 0.25,
                                        "dias_mes": 30, "uf": "PR", **TARIFA_GAS})
    assert r.status_code == 200, r.text
    j = r.json()
    assert j["custo_mes"] > 0 and j["botijoes_mes"] > 0 and j["uf"] == "PR"
    assert "ANP" in j["origem_preco"]


@pytest.mark.banco
def test_api_gas_com_preco_do_botijao(api):
    j = api.post("/calcular/gas", json={"preco_botijao": 130, **TARIFA_GAS}).json()
    assert j["preco_kg"] == pytest.approx(10.0) and j["modelo"] == "(estimativa)"


@pytest.mark.banco
def test_api_gas_sem_estado_nem_preco(api):
    assert api.post("/calcular/gas", json=TARIFA_GAS).status_code == 422
