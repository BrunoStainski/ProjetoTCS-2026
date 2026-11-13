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
    assert usage == {"pergunta": "horas", "opcoes": None, "padrao": None, "opcional": True, "perguntar_horas": False,
                     "perguntar_dias": True}


@pytest.mark.banco
def test_air_conditioner_days_of_use_change_cost_and_suggestions(api, category_id):
    """dias_mes no /calcular e no /sugestoes: 15 dias = metade de 30 (mesma conta nos modelos sugeridos)."""
    body = {"aparelho_id": category_id("ar_condicionado"), "tarifa_manual": 1.0, "horas_dia": 8}
    month = api.post("/calcular", json={**body, "registrar": False}).json()["kwh_mes"]
    half = api.post("/calcular", json={**body, "dias_mes": 15, "registrar": False}).json()["kwh_mes"]
    assert half == pytest.approx(month / 2, rel=0.01)
    assert api.post("/calcular", json={**body, "dias_mes": 0}).status_code == 422
    current = api.post("/sugestoes", json={**body, "dias_mes": 15}).json()["atual"]["kwh_mes"]
    assert current == pytest.approx(half, rel=0.01)


@pytest.mark.banco
def test_days_of_use_reach_the_estimate(api):
    """Ar fora do catalogo, com a potencia da plaqueta: 1000 W x 8 h x 10 dias = 80 kWh."""
    r = api.post("/calcular/estimado", json={"categoria": "ar_condicionado", "valor_etiqueta": 1000,
                                             "campo_etiqueta": "potencia_w", "medida": 9000, "horas_dia": 8,
                                             "dias_mes": 10, "tarifa_manual": 1.0, "registrar": False})
    assert r.status_code == 200, r.text
    assert r.json()["kwh_mes"] == pytest.approx(80.0)


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
    assert "usuário" in res["origem_tarifa"]


@pytest.mark.banco
def test_register_false_does_not_save_history(api, con, shower_5500):
    count = lambda: banco.run(con, "SELECT COUNT(*) FROM consultas").scalar_one()
    before = count()
    calculate(api, aparelho_id=shower_5500, tarifa_manual=1.0, horas_dia=0.25)
    con.commit()  # encerra a transacao de leitura para enxergar o estado atual
    assert count() == before


@pytest.mark.parametrize("category, usage", [
    ("lampada_led", {"horas_dia": 0}),
    ("televisor", {"horas_dia": 0}),
    ("maquina_de_lavar", {"ciclos_mes": 0}),
])
@pytest.mark.banco
def test_suggestions_with_zero_use_explain_instead_of_error_500(api, category_id, category, usage):
    """O app aceita 0 h 0 min (e 0 ciclos): a economia em % dividia por zero e a API respondia 500."""
    r = api.post("/sugestoes", json={"aparelho_id": category_id(category), "tarifa_manual": 1.0, **usage})
    assert r.status_code == 200
    body = r.json()
    assert body["sugestoes"] == [] and body["atual"]["kwh_mes"] == 0
    assert "não gasta energia" in body["mensagem"]


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


@pytest.mark.banco
def test_suggestions_keep_the_same_voltage(api, con, copel):
    """Quem tem a maquina de 127 V nao recebe sugestao que so existe em 220 V."""
    df = banco.query(con, "SELECT id FROM aparelhos WHERE categoria = 'maquina_de_lavar' AND tensao = '127' "
                          "AND origem_dado = 'informado' ORDER BY kwh_ciclo DESC LIMIT 1")
    if df.empty:
        pytest.skip("nenhuma maquina de lavar de 127 V no catalogo")
    r = api.post("/sugestoes", json={"aparelho_id": int(df.iloc[0]["id"]), "distribuidora_id": copel["id"],
                                     "ciclos_mes": 12, "limite": 10})
    assert r.status_code == 200
    ids = [s["id"] for s in r.json()["sugestoes"]]
    assert ids, "a maquina que mais gasta deveria ter sugestao"
    volts = banco.query(con, f"SELECT DISTINCT tensao FROM aparelhos WHERE id IN ({', '.join('?' for _ in ids)})", ids)
    assert set(volts["tensao"]) <= {"", "127"}


@pytest.mark.banco
def test_database_knows_which_catalog_it_has(con):
    """Depois da carga, a impressao do catalogo esta em `cargas`: a API nao recarrega a toa."""
    import main
    from criar_banco import catalog_fingerprint
    assert banco.run(con, "SELECT 1 FROM cargas WHERE arquivo = ?", (catalog_fingerprint(),)).first()
    assert main.database_loaded(con)


def test_absurd_tariff_or_cycles_are_refused(client):
    """Tarifa ou ciclos absurdos davam custo vazio (null) e quebravam o app: agora a API recusa (422)."""
    for body in [{"aparelho_id": 1, "tarifa_manual": 1e308, "horas_dia": 1},
                 {"aparelho_id": 1, "tarifa_manual": 0.8, "ciclos_mes": 1e308}]:
        assert client.post("/calcular", json=body).status_code == 422


def test_validation_errors_in_portuguese_with_the_field(client):
    """Erro de validacao vinha em ingles do Pydantic; em portugues, sai traduzido e com o nome do campo."""
    r = client.post("/calcular", json={"aparelho_id": 1, "tarifa_manual": 50})
    assert r.status_code == 422
    assert r.json()["detail"][0]["msg"] == "tarifa_manual: precisa ser no máximo 10"
    r = client.post("/calcular", json={"tarifa_manual": 0.8})
    assert any(d["msg"] == "aparelho_id: campo obrigatório" for d in r.json()["detail"])
    r = client.post("/calcular", json={"aparelho_id": 1, "tarifa_manual": 50}, headers={"Accept-Language": "en"})
    assert r.json()["detail"][0]["msg"].startswith("tarifa_manual: Input should be less than or equal to 10")


@pytest.mark.banco
def test_ids_do_not_change_when_the_catalog_reloads(con):
    """O id gravado e o calculado pelo nome: recarregar o catalogo nao muda os ids."""
    from criar_banco import stable_id
    rows = banco.run(con, "SELECT id, categoria, marca, modelo, tensao FROM aparelhos ORDER BY random() LIMIT 50").all()
    assert all(r.id == stable_id(r.categoria, r.marca, r.modelo, r.tensao) for r in rows)


@pytest.mark.banco
def test_history_keeps_days_and_detail(con):
    """O historico guarda os dias de uso do ar e o detalhe (que separa as versoes 127 V e 220 V)."""
    con.exec_driver_sql(banco.HISTORY_MIGRATION)
    con.commit()
    r = {"categoria": "ar_condicionado", "marca": "TESTE-HISTORICO", "modelo": "X", "detalhe": "12000 BTU/h · 220 V",
         "uf": "PR", "distribuidora": "-", "kwh_mes": 50.0, "metodo": "teste", "tarifa_kwh": 0.8,
         "origem_tarifa": "teste", "custo_mes": 40.0}
    try:
        banco.register_query(con, r, daily_hours=8, days_per_month=12)
        row = banco.run(con, "SELECT dias_mes, detalhe FROM consultas WHERE marca = 'TESTE-HISTORICO'").first()
        assert row.dias_mes == 12 and row.detalhe == "12000 BTU/h · 220 V"
    finally:
        banco.run(con, "DELETE FROM consultas WHERE marca = 'TESTE-HISTORICO'")
        con.commit()


def test_eco_coach_limit_per_address(client, monkeypatch):
    """Cada plano gasta a cota gratuita do Gemini: depois do limite, o mesmo endereco espera (429)."""
    import main
    monkeypatch.setattr(main, "ECO_COACH_LIMIT", 2)
    monkeypatch.setattr(main, "_eco_calls", {})
    headers = {"X-Forwarded-For": "203.0.113.7"}
    invalid = {"moradores": 2, "itens": []}  # recusado na validacao: nao chama o Gemini, mas conta no limite
    codes = [client.post("/eco-coach", json=invalid, headers=headers).status_code for _ in range(3)]
    assert codes[:2] != [429, 429] and codes[2] == 429
    other = client.post("/eco-coach", json=invalid, headers={"X-Forwarded-For": "198.51.100.9"}).status_code
    assert other != 429  # outro endereco continua
