import pytest

import estimativa

CRM45 = {"tipo": "duplex", "frost_free": True, "volume_total_l": 407, "volume_congelador_l": 90,
         "ano_compra": 2014, "ano_referencia": 2026}
CRM45_ETIQUETA = 52.5


@pytest.fixture(scope="module")
def modelo():
    try:
        return estimativa.carregar_modelo()
    except FileNotFoundError:
        pytest.skip("models/refrigerador.pkl nao existe (rode scripts/treinar_refrigerador.py)")


@pytest.fixture
def conversao_duplex(modelo):
    return estimativa._conversao(modelo, "Refrigerador-Congelador", True)


def test_formula_de_2006_reproduz_a_tabela_de_2001(modelo):
    assert modelo["ie_2001"]["media"] == pytest.approx(1.0, abs=0.01)


def test_volume_ajustado_e_consumo_padrao_da_crm45():
    av = estimativa.volume_ajustado_2006(317, {3: 90}, frost_free=True)
    assert av == pytest.approx(580.2)
    assert estimativa.consumo_padrao_2006("Combinado frost free", av) == pytest.approx(68.93, abs=0.01)


def test_crm45_sem_etiqueta_tem_a_etiqueta_dentro_da_faixa(modelo, conversao_duplex):
    r = estimativa.consumo_refrigerador_estimado(**CRM45, modelo=modelo)
    etiqueta_na_mesma_escala = CRM45_ETIQUETA * conversao_duplex["mediana"] * r["fator_idade"]
    assert r["kwh_min"] <= etiqueta_na_mesma_escala <= r["kwh_max"]
    assert r["kwh_min"] < r["kwh_mes"] < r["kwh_max"]
    assert r["aproximado"] and "regra de 2006" in r["metodo"]


def test_crm45_com_etiqueta_usa_o_valor_da_etiqueta(modelo, conversao_duplex):
    r = estimativa.consumo_refrigerador_estimado(**CRM45, kwh_etiqueta=CRM45_ETIQUETA, modelo=modelo)
    assert r["fator_idade"] == 1.30
    assert r["kwh_mes"] == pytest.approx(CRM45_ETIQUETA * conversao_duplex["mediana"] * 1.30)
    assert r["kwh_min"] <= r["kwh_mes"] <= r["kwh_max"]


def test_etiqueta_nova_nao_e_convertida(modelo):
    r = estimativa.consumo_refrigerador_estimado("duplex", True, 407, 2024, kwh_etiqueta=30,
                                                 ano_referencia=2026, modelo=modelo)
    assert r["kwh_mes"] == pytest.approx(30.0)


def test_geladeira_anterior_a_2006_usa_a_tabela_de_2001(modelo):
    r = estimativa.consumo_refrigerador_estimado("1_porta", False, 300, 2001, ano_referencia=2026, modelo=modelo)
    assert "tabela Inmetro 2001" in r["metodo"]
    assert any("vida util" in aviso for aviso in r["avisos"])


def test_geladeira_recente_usa_o_random_forest(modelo):
    r = estimativa.consumo_refrigerador_estimado("duplex", True, 407, 2024, ano_referencia=2026, modelo=modelo)
    assert "Random Forest" in r["metodo"]
    assert r["fator_idade"] == 1.00


def test_sem_volume_do_freezer_usa_a_proporcao_tipica(modelo):
    r = estimativa.consumo_refrigerador_estimado("duplex", True, 407, 2014, ano_referencia=2026, modelo=modelo)
    assert r["kwh_mes"] > 0


@pytest.mark.parametrize("idade, fator", [(0, 1.00), (5, 1.00), (6, 1.10), (10, 1.10), (11, 1.30), (30, 1.30)])
def test_fator_de_idade(idade, fator):
    assert estimativa.fator_idade(idade) == fator


@pytest.mark.parametrize("mudanca", [
    {"tipo": "geladeira"},
    {"volume_congelador_l": 500},
    {"ano_compra": 2030},
    {"volume_total_l": 0},
])
def test_entradas_invalidas(modelo, mudanca):
    with pytest.raises(ValueError):
        estimativa.consumo_refrigerador_estimado(**{**CRM45, **mudanca}, modelo=modelo)


def test_resistivo_com_valores_padrao():
    r = estimativa.consumo_resistivo("air_fryer")
    assert r["kwh_mes"] == pytest.approx(1500 / 1000 * 0.5 * 15)
    assert r["premissa"] and r["aproximado"] and r["avisos"]


def test_chuveiro_resistivo_bate_com_o_exemplo_do_projeto():
    r = estimativa.consumo_resistivo("chuveiro", potencia_w=5500, horas_dia=0.25, dias_mes=30)
    assert r["kwh_mes"] == pytest.approx(41.25)
    assert not r["premissa"] and not r["aproximado"] and not r["avisos"]


def test_resistivo_invalido():
    with pytest.raises(ValueError):
        estimativa.consumo_resistivo("torradeira")


def test_catalogo_converte_geladeiras_da_metodologia_antiga(modelo):
    import calculadora_residencial as calc
    geladeiras = calc.carregar_catalogo().query("categoria == 'refrigerador'")
    convertidas = geladeiras[geladeiras["origem_dado"] == calc.ORIGEM_CONVERTIDA]
    assert len(convertidas) > 0
    assert geladeiras["kwh_mes"].notna().all()
    crm50 = geladeiras[geladeiras["modelo"].str.contains("CRM50MBANA", regex=False)].iloc[0]
    assert crm50["origem_dado"] == "informado" and crm50["kwh_mes"] == pytest.approx(32.1)


def test_resultado_avisa_quando_o_consumo_foi_convertido():
    import calculadora_residencial as calc
    from conftest import aparelho
    a = aparelho("refrigerador", kwh_mes=26.6, origem_dado=calc.ORIGEM_CONVERTIDA)
    consumo = calc.consumo_mensal_kwh(a)
    r = calc.montar_resultado(a, consumo, 0.8, "COPEL", "ANEEL", "PR")
    assert calc.AVISO_CONVERTIDO in r["avisos"]


@pytest.fixture
def api_sem_banco(client):
    import main
    client.app.dependency_overrides[main.conexao] = lambda: None
    yield client
    client.app.dependency_overrides.clear()


def test_api_refrigerador_antigo(api_sem_banco, modelo):
    resposta = api_sem_banco.post("/calcular/refrigerador-antigo", json={
        "tipo": "duplex", "frost_free": True, "volume_total_l": 407, "volume_congelador_l": 90,
        "ano_compra": 2014, "kwh_etiqueta": CRM45_ETIQUETA, "marca": "Consul", "modelo": "CRM45",
        "tarifa_manual": 0.8, "registrar": False})
    assert resposta.status_code == 200, resposta.text
    corpo = resposta.json()
    assert corpo["aproximado"] and corpo["modelo"] == "CRM45"
    assert corpo["custo_mes"] == pytest.approx(corpo["kwh_mes"] * 0.8, abs=0.01)
    assert corpo["custo_min_mes"] <= corpo["custo_mes"] <= corpo["custo_max_mes"]


def test_api_resistivo(api_sem_banco):
    resposta = api_sem_banco.post("/calcular/resistivo", json={
        "categoria": "chuveiro", "potencia_w": 5500, "horas_dia": 0.25, "dias_mes": 30,
        "tarifa_manual": 0.768, "registrar": False})
    assert resposta.status_code == 200, resposta.text
    assert resposta.json()["kwh_mes"] == pytest.approx(41.25)


def test_api_lista_resistivos(api_sem_banco):
    resposta = api_sem_banco.get("/resistivos")
    assert {r["categoria"] for r in resposta.json()} == set(estimativa.RESISTIVOS)


def test_api_exige_uma_tarifa(api_sem_banco):
    resposta = api_sem_banco.post("/calcular/resistivo", json={"categoria": "chuveiro", "registrar": False})
    assert resposta.status_code == 422
