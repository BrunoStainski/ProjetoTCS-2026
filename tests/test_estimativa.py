import math

import pandas as pd
import pytest

import estimativa
import servico
from calculadora_residencial import NUM_COLUMNS

CRM45 = {"kind": "duplex", "frost_free": True, "volume_total_l": 407, "freezer_volume_l": 90,
         "purchase_year": 2014, "reference_year": 2026}
CRM45_LABEL = 52.5


@pytest.fixture(scope="module")
def model():
    try:
        return estimativa.load_model()
    except FileNotFoundError:
        pytest.skip("models/refrigerador.pkl nao existe (rode scripts/treinar_refrigerador.py)")


@pytest.fixture
def duplex_conversion(model):
    return estimativa._conversion(model, "Refrigerador-Congelador", True)


def test_formula_2006_reproduces_table_2001(model):
    assert model["ie_2001"]["media"] == pytest.approx(1.0, abs=0.01)


def test_crm_45_adjusted_volume_and_default_consumption():
    av = estimativa.adjusted_volume_2006(317, {3: 90}, frost_free=True)
    assert av == pytest.approx(580.2)
    assert estimativa.default_consumption_2006("Combinado frost free", av) == pytest.approx(68.93, abs=0.01)


def test_crm_45_without_label_range_contains_label(model, duplex_conversion):
    r = estimativa.estimated_refrigerator_consumption(**CRM45, model=model)
    label_in_same_scale = CRM45_LABEL * duplex_conversion["mediana"] * r["fator_idade"]
    assert r["kwh_min"] <= label_in_same_scale <= r["kwh_max"]
    assert r["kwh_min"] < r["kwh_mes"] < r["kwh_max"]
    assert r["aproximado"] and "regra de 2006" in r["metodo"]


def test_crm_45_with_label_uses_label_value(model, duplex_conversion):
    r = estimativa.estimated_refrigerator_consumption(**CRM45, kwh_label=CRM45_LABEL, model=model)
    assert r["fator_idade"] == 1.30
    assert r["kwh_mes"] == pytest.approx(CRM45_LABEL * duplex_conversion["mediana"] * 1.30)
    assert r["kwh_min"] <= r["kwh_mes"] <= r["kwh_max"]


def test_new_label_is_not_converted(model):
    r = estimativa.estimated_refrigerator_consumption("duplex", True, 407, 2024, kwh_label=30,
                                                 reference_year=2026, model=model)
    assert r["kwh_mes"] == pytest.approx(30.0)


def test_fridge_before_2006_uses_2001_table(model):
    r = estimativa.estimated_refrigerator_consumption("1_porta", False, 300, 2001, reference_year=2026, model=model)
    assert "tabela Inmetro 2001" in r["metodo"]
    assert any("vida util" in notice for notice in r["avisos"])


def test_recent_fridge_uses_random_forest(model):
    r = estimativa.estimated_refrigerator_consumption("duplex", True, 407, 2024, reference_year=2026, model=model)
    assert "Random Forest" in r["metodo"]
    assert r["fator_idade"] == 1.00


def test_without_freezer_volume_uses_typical_proportion(model):
    r = estimativa.estimated_refrigerator_consumption("duplex", True, 407, 2014, reference_year=2026, model=model)
    assert r["kwh_mes"] > 0


@pytest.mark.parametrize("age, factor", [(0, 1.00), (5, 1.00), (6, 1.10), (10, 1.10), (11, 1.30), (30, 1.30)])
def test_age_factor(age, factor):
    assert estimativa.age_factor(age) == factor


@pytest.mark.parametrize("change", [
    {"kind": "geladeira"},
    {"freezer_volume_l": 500},
    {"purchase_year": 2030},
    {"volume_total_l": 0},
])
def test_invalid_inputs(model, change):
    with pytest.raises(ValueError):
        estimativa.estimated_refrigerator_consumption(**{**CRM45, **change}, model=model)


DEFAULT_AIR_FRYER = {"categoria": "air_fryer", "nome": "Air fryer", "potencia_w": 1500, "horas_dia": 0.5,
                    "dias_mes": 15, "fonte": "premissa do grupo"}


def test_resistive_with_default_values():
    r = estimativa.resistive_consumption(DEFAULT_AIR_FRYER)
    assert r["kwh_mes"] == pytest.approx(1500 / 1000 * 0.5 * 15)
    assert r["premissa"] and r["aproximado"] and r["avisos"]


def test_resistive_shower_matches_project_example():
    shower = {**DEFAULT_AIR_FRYER, "categoria": "chuveiro", "nome": "Chuveiro elétrico"}
    r = estimativa.resistive_consumption(shower, power_w=5500, daily_hours=0.25, days_per_month=30)
    assert r["kwh_mes"] == pytest.approx(41.25)
    assert not r["premissa"] and not r["aproximado"] and not r["avisos"]


def test_invalid_resistive():
    with pytest.raises(ValueError):
        estimativa.resistive_consumption(DEFAULT_AIR_FRYER, daily_hours=30)


def test_catalog_converts_old_methodology_fridges(model):
    import calculadora_residencial as calc
    fridges = calc.load_catalog().query("categoria == 'refrigerador'")
    converted = fridges[fridges["origem_dado"] == calc.CONVERTED_ORIGIN]
    assert len(converted) > 0
    assert fridges["kwh_mes"].notna().all()
    crm50 = fridges[fridges["modelo"].str.contains("CRM50MBANA", regex=False)].iloc[0]
    assert crm50["origem_dado"] == "informado" and crm50["kwh_mes"] == pytest.approx(32.1)


def test_result_warns_when_consumption_was_converted():
    import calculadora_residencial as calc
    from conftest import appliance
    a = appliance("refrigerador", kwh_mes=26.6, origem_dado=calc.CONVERTED_ORIGIN)
    consumption = calc.monthly_consumption_kwh(a)
    r = calc.build_result(a, consumption, 0.8, "COPEL", "ANEEL", "PR")
    assert calc.CONVERTED_NOTICE in r["avisos"]


@pytest.fixture
def api_without_database(client):
    import main
    client.app.dependency_overrides[main.connection] = lambda: None
    yield client
    client.app.dependency_overrides.clear()


def test_api_old_refrigerator(api_without_database, model):
    response = api_without_database.post("/calcular/refrigerador-antigo", json={
        "tipo": "duplex", "frost_free": True, "volume_total_l": 407, "volume_congelador_l": 90,
        "ano_compra": 2014, "kwh_etiqueta": CRM45_LABEL, "marca": "Consul", "modelo": "CRM45",
        "tarifa_manual": 0.8, "registrar": False})
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["aproximado"] and body["modelo"] == "CRM45"
    assert body["custo_mes"] == pytest.approx(body["kwh_mes"] * 0.8, abs=0.01)
    assert body["custo_min_mes"] <= body["custo_mes"] <= body["custo_max_mes"]


@pytest.mark.banco
def test_resistive_api(api):
    response = api.post("/calcular/resistivo", json={
        "categoria": "chuveiro", "potencia_w": 5500, "horas_dia": 0.25, "dias_mes": 30,
        "tarifa_manual": 0.768, "registrar": False})
    assert response.status_code == 200, response.text
    assert response.json()["kwh_mes"] == pytest.approx(41.25)
    assert response.json()["marca"] == "Chuveiro elétrico" and response.json()["modelo"] == "(estimativa)"


@pytest.mark.banco
def test_api_small_appliance_list_comes_from_database(api):
    smallAppliances = {r["categoria"]: r for r in api.get("/resistivos").json()}
    assert {"air_fryer", "secador_cabelo", "liquidificador", "aspirador_po"} <= set(smallAppliances)
    assert all(r["fonte"] for r in smallAppliances.values())


@pytest.mark.banco
def test_api_unknown_small_appliance_returns_404(api):
    response = api.post("/calcular/resistivo", json={"categoria": "teletransporte", **TARIFF})
    assert response.status_code == 404


TARIFF = {"tarifa_manual": 0.768, "registrar": False}


@pytest.mark.banco
def test_estimable_categories_cover_catalog(api):
    categories = {c["categoria"]: c for c in api.get("/estimativa/categorias").json()}
    assert {"refrigerador", "maquina_de_lavar", "ar_condicionado", "televisor", "chuveiro"} <= set(categories)
    assert categories["maquina_de_lavar"]["tipos"] and categories["maquina_de_lavar"]["uso"]["pergunta"] == "ciclos"
    assert categories["chuveiro"]["valor_obrigatorio"]
    washing = categories["maquina_de_lavar"]
    assert washing["tipos"][0] == {"valor": "Top Load (automatica)", "nome": "Automática que abre por cima",
                                 "descricao": "Tampa em cima. Lava, enxágua e centrifuga sozinha."}
    assert [f["campo"] for f in categories["televisor"]["formas"]] == ["potencia_w", "kwh_mes"]
    assert categories["ventilador_de_mesa"]["uso"]["perguntar_horas"]
    assert categories["ventilador_de_teto"]["medida"] is None and not categories["ventilador_de_teto"]["tamanhos"]


@pytest.mark.banco
@pytest.mark.parametrize("body", [
    {"categoria": "maquina_de_lavar", "tipo": "Top Load (automatica)", "medida": 12, "ciclos_mes": 12},
    {"categoria": "ar_condicionado", "tipo": "Split Hi-Wall", "medida": 12000, "horas_dia": 8},
    {"categoria": "televisor", "medida": 50},
    {"categoria": "ventilador_de_mesa", "medida": 40, "velocidade": "media", "horas_dia": 8},
    {"categoria": "ventilador_de_teto", "velocidade": "media", "horas_dia": 8},
])
def test_estimate_from_similar_models(api, body):
    response = api.post("/calcular/estimado", json={**body, **TARIFF})
    assert response.status_code == 200, response.text
    r = response.json()
    assert r["aproximado"] and r["kwh_min"] <= r["kwh_mes"] <= r["kwh_max"]
    assert r["capacidade"] == body.get("medida")


@pytest.mark.banco
def test_estimated_fan_multiplies_by_usage_hours(api):
    body = {"categoria": "ventilador_de_mesa", "medida": 40, "velocidade": "media", **TARIFF}
    one_hour = api.post("/calcular/estimado", json={**body, "horas_dia": 1}).json()
    eight_hours = api.post("/calcular/estimado", json={**body, "horas_dia": 8}).json()
    assert eight_hours["kwh_mes"] == pytest.approx(8 * one_hour["kwh_mes"], rel=0.01)


@pytest.mark.banco
@pytest.mark.parametrize("body, kwh", [
    ({"categoria": "televisor", "campo_etiqueta": "potencia_w", "valor_etiqueta": 120, "horas_dia": 5}, 18.0),
    ({"categoria": "ar_condicionado", "campo_etiqueta": "potencia_w", "valor_etiqueta": 1100, "horas_dia": 8}, 264.0),
    ({"categoria": "ventilador_de_teto", "campo_etiqueta": "potencia_w", "valor_etiqueta": 130, "horas_dia": 8,
      "velocidade": "alta"}, 31.2),
    ({"categoria": "maquina_de_lavar", "valor_etiqueta": 0.25, "ciclos_mes": 15}, 3.75),
])
def test_value_written_on_appliance_also_works_for_old_ones(api, body, kwh):
    r = api.post("/calcular/estimado", json={**body, **TARIFF}).json()
    assert r["kwh_mes"] == pytest.approx(kwh)
    assert r["kwh_min"] == r["kwh_max"] == r["kwh_mes"]


@pytest.mark.banco
@pytest.mark.parametrize("body", [
    {"categoria": "ar_condicionado", "campo_etiqueta": "potencia_w", "valor_etiqueta": 1100},
    {"categoria": "ar_condicionado", "campo_etiqueta": "kwh_mes", "valor_etiqueta": 30, "horas_dia": 8},
    {"categoria": "televisor", "campo_etiqueta": "potencia_w", "valor_etiqueta": 5000, "horas_dia": 5},
    {"categoria": "chuveiro", "medida": 10, "horas_dia": 0.25},
])
def test_invalid_value_written_on_appliance_is_rejected(api, body):
    assert api.post("/calcular/estimado", json={**body, **TARIFF}).status_code == 422


@pytest.mark.banco
def test_estimate_text_uses_same_kwh_per_cycle_as_calculation(api):
    r = api.post("/calcular/estimado", json={"categoria": "maquina_de_lavar", "tipo": "Top Load (automatica)",
                                              "medida": 8, "ciclos_mes": 15, **TARIFF}).json()
    kwh_per_cycle = float(r["metodo"].split("Uso: ")[1].split(" kWh por ciclo")[0])
    assert kwh_per_cycle * 15 == pytest.approx(r["kwh_mes"], abs=0.005)
    assert r["kwh_min"] <= kwh_per_cycle * 15 <= r["kwh_max"]
    assert r["detalhe"] == "Automática que abre por cima, 8 kg" and ".csv" not in r["origem_tarifa"]


def test_few_similar_models_use_smallest_and_largest(monkeypatch):
    tres = pd.DataFrame([{**{c: math.nan for c in NUM_COLUMNS}, "categoria": "maquina_de_lavar", "kwh_ciclo": v}
                         for v in (0.2, 0.3, 0.5)])
    monkeypatch.setattr(servico, "_equivalent", lambda *_: (tres, 0.1, False))
    r = servico.estimate_from_equivalents(None, "maquina_de_lavar", measure=8, monthly_cycles=10)
    assert (r["kwh_min"], r["kwh_mes"], r["kwh_max"]) == pytest.approx((2, 3, 5))
    assert "menor e o maior" in r["metodo"] and "0.3 kWh por ciclo x 10" in r["metodo"]


@pytest.mark.banco
def test_estimate_with_label_value_is_exact(api):
    r = api.post("/calcular/estimado", json={"categoria": "chuveiro", "valor_etiqueta": 5500,
                                              "horas_dia": 0.25, **TARIFF}).json()
    assert r["kwh_mes"] == pytest.approx(41.25)
    assert r["kwh_min"] == r["kwh_max"] and r["detalhe"] == "5500 W"


@pytest.mark.banco
def test_estimate_without_measure_or_label_is_rejected(api):
    assert api.post("/calcular/estimado", json={"categoria": "televisor", **TARIFF}).status_code == 422


@pytest.mark.banco
def test_estimated_fridge_receives_suggestions_and_compares(api):
    g = api.post("/calcular/refrigerador-antigo", json={
        "tipo": "duplex", "frost_free": True, "volume_total_l": 407, "volume_congelador_l": 90,
        "ano_compra": 2014, "kwh_etiqueta": CRM45_LABEL, **TARIFF}).json()
    s = api.post("/sugestoes/estimado", json={"categoria": "refrigerador", "capacidade": g["capacidade"],
                                               "tipo": g["tipo"], "kwh_mes": g["kwh_mes"], "tarifa_manual": 0.768}).json()
    assert s["sugestoes"] and all(x["kwh_mes"] < g["kwh_mes"] for x in s["sugestoes"])
    c = api.post("/comparar/estimado", json={"categoria": "refrigerador", "kwh_mes": g["kwh_mes"],
                                              "alternativa_id": s["sugestoes"][0]["id"], "preco_novo": 3500,
                                              "tarifa_manual": 0.768}).json()
    assert c["economia_mes"] == pytest.approx(s["sugestoes"][0]["economia_mes"], abs=0.02)
    assert c["payback"]["meses"] > 0


def test_api_requires_tariff(api_without_database):
    response = api_without_database.post("/calcular/resistivo", json={"categoria": "chuveiro", "registrar": False})
    assert response.status_code == 422


@pytest.mark.banco
def test_suggestions_for_appliance_estimated_by_similar_do_not_claim_it_is_economical(api):
    body = {"categoria": "maquina_de_lavar", "tipo": "Top Load (automatica)", "ciclos_mes": 15, **TARIFF}
    r = api.post("/calcular/estimado", json={**body, "medida": 8}).json()
    assert r["pelos_parecidos"]
    s = api.post("/sugestoes/estimado", json={
        **body, "capacidade": r["capacidade"], "kwh_mes": r["kwh_mes"], "pelos_parecidos": True}).json()
    assert s["sugestoes"] == [] and "calculado pelos modelos atuais parecidos" in s["mensagem"]
    assert "já está entre os mais econômicos" not in s["mensagem"]


@pytest.mark.banco
def test_label_value_keeps_type_and_size_for_compare(api):
    r = api.post("/calcular/estimado", json={
        "categoria": "maquina_de_lavar", "tipo": "Top Load (automatica)", "medida": 8,
        "valor_etiqueta": 0.4, "ciclos_mes": 15, **TARIFF}).json()
    assert not r["pelos_parecidos"] and r["kwh_mes"] == pytest.approx(6.0)
    assert r["capacidade"] == 8 and r["detalhe"] == "Automática que abre por cima, 8 kg"
    s = api.post("/sugestoes/estimado", json={
        "categoria": "maquina_de_lavar", "tipo": "Top Load (automatica)", "capacidade": 8, "kwh_mes": 6.0,
        "ciclos_mes": 15, **TARIFF}).json()
    assert s["sugestoes"] and all(x["kwh_mes"] < 6.0 for x in s["sugestoes"])
