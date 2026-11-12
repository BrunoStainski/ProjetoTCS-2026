"""
Contrato da API (src/main.py), do jeito que o app Flutter usa.

Os testes com o fixture "api" leem o PostgreSQL e sao pulados se ele nao estiver no ar.
Todo POST /calcular manda registrar=false, para nao gravar no historico (tabela consultas).
"""

import pytest

import banco


# Fixtures que dependem dos dados ----------------------------------------------------------

@pytest.fixture
def shower_5500(con):
    df = banco.query(con, "SELECT id FROM aparelhos WHERE categoria = ? AND potencia_w = ? "
                             "ORDER BY id LIMIT 1", ("chuveiro", 5500))
    if df.empty:
        pytest.skip("nenhum chuveiro de 5500 W no catalogo")
    return int(df.iloc[0]["id"])


@pytest.fixture
def category_id(con):
    def search(category):
        df = banco.query(con, "SELECT id FROM aparelhos WHERE categoria = ? ORDER BY id LIMIT 1", (category,))
        return int(df.iloc[0]["id"])
    return search


@pytest.fixture
def copel(api):
    item_list = api.get("/distribuidoras", params={"busca": "copel"}).json()
    assert item_list, "Copel nao encontrada nas distribuidoras com tarifa vigente"
    return item_list[0]


def calculate(api, **body):
    return api.post("/calcular", json={"registrar": False, **body})


# Sistema e listas ---------------------------------------------------------------------------

@pytest.mark.banco
def test_health(api):
    assert api.get("/saude").json() == {"status": "ok"}


@pytest.mark.banco
def test_appliance_search(api):
    r = api.get("/aparelhos", params={"busca": "brastemp"})
    assert r.status_code == 200
    item_list = r.json()
    assert item_list and all("brastemp" in a["marca"].lower() for a in item_list)
    assert set(item_list[0]) >= {"id", "categoria", "marca", "modelo", "total_categoria"}


@pytest.mark.banco
def test_search_returns_all_brand_types(api):
    """Brastemp tem maquina de lavar, micro-ondas e geladeira: antes so a 1a (lavar) aparecia."""
    item_list = api.get("/aparelhos", params={"busca": "brastemp", "limite": 3}).json()
    types = {a["categoria"] for a in item_list}
    assert {"maquina_de_lavar", "microondas", "refrigerador"} <= types
    for kind in types:
        from_type = [a for a in item_list if a["categoria"] == kind]
        assert len(from_type) <= 3 and all(a["total_categoria"] >= len(from_type) for a in from_type)


@pytest.mark.banco
def test_type_brands_without_uppercase_duplicates(api):
    """O Inmetro tem 'Agratto' e 'AGRATTO' no ar-condicionado: a lista mostra a marca uma vez."""
    brands = api.get("/marcas", params={"categoria": "ar_condicionado"}).json()
    names = [m["marca"].strip().upper() for m in brands]
    assert len(brands) > 10 and len(names) == len(set(names)) and names == sorted(names)
    assert "AGRATTO" in names and all(m["modelos"] > 0 for m in brands)
    assert api.get("/marcas", params={"categoria": "nao_existe"}).json() == []


@pytest.mark.banco
def test_brand_models(api):
    brand = next(m for m in api.get("/marcas", params={"categoria": "ar_condicionado"}).json() if m["marca"].upper() == "AGRATTO")
    item_list = api.get("/modelos", params={"categoria": "ar_condicionado", "marca": "agratto", "limite": 5}).json()
    assert 0 < len(item_list) <= 5
    assert all(a["categoria"] == "ar_condicionado" and a["marca"].strip().upper() == "AGRATTO" for a in item_list)
    assert all(a["total_categoria"] == brand["modelos"] for a in item_list)  # as duas grafias juntas
    assert api.get("/modelos", params={"categoria": "ar_condicionado", "marca": ""}).status_code == 422


@pytest.mark.banco
def test_search_filters_by_category(api):
    item_list = api.get("/aparelhos", params={"busca": "lorenzetti", "categoria": "chuveiro"}).json()
    assert item_list and {a["categoria"] for a in item_list} == {"chuveiro"}


@pytest.mark.banco
def test_too_short_search_is_rejected(api):
    assert api.get("/aparelhos", params={"busca": "a"}).status_code == 422


@pytest.mark.banco
def test_distributors_by_uf(api):
    item_list = api.get("/distribuidoras", params={"uf": "pr"}).json()
    assert item_list and {d["uf"] for d in item_list} == {"PR"}
    assert all(d["tarifa_kwh"] > 0 for d in item_list)


@pytest.mark.banco
def test_invalid_uf_is_rejected(api):
    assert api.get("/distribuidoras", params={"uf": "P1"}).status_code == 422


@pytest.mark.banco
def test_auxiliary_lists(api):
    assert "chuveiro" in api.get("/categorias").json()
    assert "PR" in api.get("/ufs").json()


# Pergunta de uso (o que a tela do app pergunta) ------------------------------------------

@pytest.mark.banco
def test_shower_asks_required_hours(api, shower_5500):
    usage = api.get(f"/aparelhos/{shower_5500}/uso").json()
    assert usage["pergunta"] == "horas"
    assert usage["padrao"] is None
    assert usage["opcional"] is False


@pytest.mark.banco
def test_catalog_fan_asks_speed_and_hours(api, category_id):
    appliance_id = category_id("ventilador_de_mesa")
    assert api.get(f"/aparelhos/{appliance_id}/uso").json()["perguntar_horas"]
    body = {"aparelho_id": appliance_id, "tarifa_manual": 1.0, "velocidade": "media", "registrar": False}
    one = api.post("/calcular", json={**body, "horas_dia": 1}).json()["kwh_mes"]
    eight = api.post("/calcular", json={**body, "horas_dia": 8}).json()["kwh_mes"]
    assert eight == pytest.approx(8 * one, rel=0.01)


@pytest.mark.banco
def test_air_conditioner_asks_optional_hours(api, category_id):
    """padrao=None com opcional=True: o app deve aceitar em branco (fica o valor do Inmetro)."""
    usage = api.get(f"/aparelhos/{category_id('ar_condicionado')}/uso").json()
    assert usage == {"pergunta": "horas", "opcoes": None, "padrao": None, "opcional": True, "perguntar_horas": False}


@pytest.mark.banco
def test_tv_asks_optional_hours(api, category_id):
    usage = api.get(f"/aparelhos/{category_id('televisor')}/uso").json()
    assert usage["pergunta"] == "horas" and usage["opcional"] is True


@pytest.mark.banco
def test_missing_appliance_returns_404(api):
    assert api.get("/aparelhos/999999999/uso").status_code == 404


# POST /calcular ---------------------------------------------------------------------------------

@pytest.mark.banco
def test_calculate_copel_reference_example(api, shower_5500, copel):
    r = calculate(api, aparelho_id=shower_5500, distribuidora_id=copel["id"], horas_dia=0.25)
    assert r.status_code == 200
    res = r.json()
    assert res["kwh_mes"] == pytest.approx(41.25)
    assert res["custo_mes"] == pytest.approx(round(41.25 * copel["tarifa_kwh"], 2))
    assert res["uf"] == "PR"
    assert res["avisos"]


@pytest.mark.banco
def test_calculate_with_bill_tariff(api, shower_5500):
    res = calculate(api, aparelho_id=shower_5500, tarifa_manual=1.0, horas_dia=0.25).json()
    assert res["custo_mes"] == pytest.approx(41.25)
    assert "usuario" in res["origem_tarifa"]


@pytest.mark.banco
def test_register_false_does_not_save_history(api, con, shower_5500):
    count = lambda: banco.run(con, "SELECT COUNT(*) FROM consultas").scalar_one()
    before = count()
    calculate(api, aparelho_id=shower_5500, tarifa_manual=1.0, horas_dia=0.25)
    con.commit()  # encerra a transacao de leitura para enxergar o estado atual
    assert count() == before


@pytest.mark.parametrize("body", [
    {"aparelho_id": 1, "tarifa_manual": 1.0, "distribuidora_id": 1},  # as duas tarifas
    {"aparelho_id": 1},                                                # nenhuma tarifa
    {"aparelho_id": 1, "tarifa_manual": 0},                            # tarifa zero
    {"aparelho_id": 1, "tarifa_manual": 1.0, "horas_dia": 30},         # mais de 24 h
    {"aparelho_id": 1, "tarifa_manual": 1.0, "velocidade": "turbo"},   # velocidade invalida
])
@pytest.mark.banco
def test_calculate_valid_input(api, body):
    """Validacao do pydantic -> 422. Obs.: o FastAPI abre a conexao (Depends) antes de validar
    o corpo, entao sem banco essas rotas respondem 503, por isso o teste precisa do banco."""
    assert api.post("/calcular", json={"registrar": False, **body}).status_code == 422


@pytest.mark.banco
def test_calculate_shower_without_hours_returns_422(api, shower_5500):
    r = calculate(api, aparelho_id=shower_5500, tarifa_manual=1.0)
    assert r.status_code == 422
    assert "horas" in r.json()["detail"]


@pytest.mark.banco
def test_calculate_missing_appliance_or_distributor_returns_404(api, shower_5500):
    assert calculate(api, aparelho_id=999999999, tarifa_manual=1.0, horas_dia=1).status_code == 404
    assert calculate(api, aparelho_id=shower_5500, distribuidora_id=999999999, horas_dia=1).status_code == 404


# POST /classificar (nao usa banco) --------------------------------------------------------------

def test_classify(client):
    r = client.post("/classificar", json={"moradores": 3, "itens": [
        {"categoria": "chuveiro", "kwh_mes": 82.5}, {"categoria": "refrigerador", "kwh_mes": 30}]})
    assert r.status_code == 200
    res = r.json()
    assert res["perfil"] in {"Consciente", "Moderado", "Ineficiente"}
    assert res["kwh_por_morador"] == pytest.approx(37.5)
    assert set(res["comparacao_media"]) == {"mediana_kwh_por_morador", "diferenca_percentual", "texto"}


@pytest.mark.parametrize("body", [
    {"moradores": 0, "itens": [{"categoria": "chuveiro", "kwh_mes": 10}]},
    {"moradores": 2, "itens": []},
    {"moradores": 2, "itens": [{"categoria": "chuveiro", "kwh_mes": -1}]},
    {"moradores": 2, "itens": [{"categoria": "chuveiro", "kwh_mes": 0}]},
    {"itens": [{"categoria": "chuveiro", "kwh_mes": 10}]},
])
def test_classify_rejects_invalid_input(client, body):
    assert client.post("/classificar", json=body).status_code == 422
