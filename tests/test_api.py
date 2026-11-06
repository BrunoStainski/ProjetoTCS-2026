"""
Contrato da API (src/main.py), do jeito que o app Flutter usa.

Os testes com o fixture "api" leem o PostgreSQL e sao pulados se ele nao estiver no ar.
Todo POST /calcular manda registrar=false, para nao gravar no historico (tabela consultas).
"""

import pytest

import banco


# Fixtures que dependem dos dados ----------------------------------------------------------

@pytest.fixture
def chuveiro_5500(con):
    df = banco.consulta(con, "SELECT id FROM aparelhos WHERE categoria = ? AND potencia_w = ? "
                             "ORDER BY id LIMIT 1", ("chuveiro", 5500))
    if df.empty:
        pytest.skip("nenhum chuveiro de 5500 W no catalogo")
    return int(df.iloc[0]["id"])


@pytest.fixture
def id_da_categoria(con):
    def buscar(categoria):
        df = banco.consulta(con, "SELECT id FROM aparelhos WHERE categoria = ? ORDER BY id LIMIT 1", (categoria,))
        return int(df.iloc[0]["id"])
    return buscar


@pytest.fixture
def copel(api):
    lista = api.get("/distribuidoras", params={"busca": "copel"}).json()
    assert lista, "Copel nao encontrada nas distribuidoras com tarifa vigente"
    return lista[0]


def calcular(api, **corpo):
    return api.post("/calcular", json={"registrar": False, **corpo})


# Sistema e listas ---------------------------------------------------------------------------

@pytest.mark.banco
def test_saude(api):
    assert api.get("/saude").json() == {"status": "ok"}


@pytest.mark.banco
def test_busca_de_aparelhos(api):
    r = api.get("/aparelhos", params={"busca": "brastemp"})
    assert r.status_code == 200
    lista = r.json()
    assert lista and all("brastemp" in a["marca"].lower() for a in lista)
    assert set(lista[0]) >= {"id", "categoria", "marca", "modelo"}


@pytest.mark.banco
def test_busca_filtra_por_categoria(api):
    lista = api.get("/aparelhos", params={"busca": "lorenzetti", "categoria": "chuveiro"}).json()
    assert lista and {a["categoria"] for a in lista} == {"chuveiro"}


@pytest.mark.banco
def test_busca_muito_curta_e_rejeitada(api):
    assert api.get("/aparelhos", params={"busca": "a"}).status_code == 422


@pytest.mark.banco
def test_distribuidoras_por_uf(api):
    lista = api.get("/distribuidoras", params={"uf": "pr"}).json()
    assert lista and {d["uf"] for d in lista} == {"PR"}
    assert all(d["tarifa_kwh"] > 0 for d in lista)


@pytest.mark.banco
def test_uf_invalida_e_rejeitada(api):
    assert api.get("/distribuidoras", params={"uf": "P1"}).status_code == 422


@pytest.mark.banco
def test_listas_auxiliares(api):
    assert "chuveiro" in api.get("/categorias").json()
    assert "PR" in api.get("/ufs").json()


# Pergunta de uso (o que a tela do app pergunta) ------------------------------------------

@pytest.mark.banco
def test_chuveiro_pede_horas_obrigatorias(api, chuveiro_5500):
    uso = api.get(f"/aparelhos/{chuveiro_5500}/uso").json()
    assert uso["pergunta"] == "horas"
    assert uso["padrao"] is None
    assert uso["opcional"] is False


@pytest.mark.banco
def test_ar_condicionado_pede_horas_opcionais(api, id_da_categoria):
    """padrao=None com opcional=True: o app deve aceitar em branco (fica o valor do Inmetro)."""
    uso = api.get(f"/aparelhos/{id_da_categoria('ar_condicionado')}/uso").json()
    assert uso == {"pergunta": "horas", "opcoes": None, "padrao": None, "opcional": True}


@pytest.mark.banco
def test_aparelho_inexistente_da_404(api):
    assert api.get("/aparelhos/999999999/uso").status_code == 404


# POST /calcular ---------------------------------------------------------------------------------

@pytest.mark.banco
def test_calcular_exemplo_de_referencia_copel(api, chuveiro_5500, copel):
    r = calcular(api, aparelho_id=chuveiro_5500, distribuidora_id=copel["id"], horas_dia=0.25)
    assert r.status_code == 200
    res = r.json()
    assert res["kwh_mes"] == pytest.approx(41.25)
    assert res["custo_mes"] == pytest.approx(round(41.25 * copel["tarifa_kwh"], 2))
    assert res["uf"] == "PR"
    assert res["avisos"]


@pytest.mark.banco
def test_calcular_com_tarifa_da_conta(api, chuveiro_5500):
    res = calcular(api, aparelho_id=chuveiro_5500, tarifa_manual=1.0, horas_dia=0.25).json()
    assert res["custo_mes"] == pytest.approx(41.25)
    assert "usuario" in res["origem_tarifa"]


@pytest.mark.banco
def test_registrar_false_nao_grava_no_historico(api, con, chuveiro_5500):
    contar = lambda: banco.executar(con, "SELECT COUNT(*) FROM consultas").scalar_one()
    antes = contar()
    calcular(api, aparelho_id=chuveiro_5500, tarifa_manual=1.0, horas_dia=0.25)
    con.commit()  # encerra a transacao de leitura para enxergar o estado atual
    assert contar() == antes


@pytest.mark.parametrize("corpo", [
    {"aparelho_id": 1, "tarifa_manual": 1.0, "distribuidora_id": 1},  # as duas tarifas
    {"aparelho_id": 1},                                                # nenhuma tarifa
    {"aparelho_id": 1, "tarifa_manual": 0},                            # tarifa zero
    {"aparelho_id": 1, "tarifa_manual": 1.0, "horas_dia": 30},         # mais de 24 h
    {"aparelho_id": 1, "tarifa_manual": 1.0, "velocidade": "turbo"},   # velocidade invalida
])
@pytest.mark.banco
def test_calcular_valida_a_entrada(api, corpo):
    """Validacao do pydantic -> 422. Obs.: o FastAPI abre a conexao (Depends) antes de validar
    o corpo, entao sem banco essas rotas respondem 503, por isso o teste precisa do banco."""
    assert api.post("/calcular", json={"registrar": False, **corpo}).status_code == 422


@pytest.mark.banco
def test_calcular_chuveiro_sem_horas_da_422(api, chuveiro_5500):
    r = calcular(api, aparelho_id=chuveiro_5500, tarifa_manual=1.0)
    assert r.status_code == 422
    assert "horas" in r.json()["detail"]


@pytest.mark.banco
def test_calcular_aparelho_ou_distribuidora_inexistente_da_404(api, chuveiro_5500):
    assert calcular(api, aparelho_id=999999999, tarifa_manual=1.0, horas_dia=1).status_code == 404
    assert calcular(api, aparelho_id=chuveiro_5500, distribuidora_id=999999999, horas_dia=1).status_code == 404


# POST /classificar (nao usa banco) --------------------------------------------------------------

def test_classificar(client):
    r = client.post("/classificar", json={"moradores": 3, "itens": [
        {"categoria": "chuveiro", "kwh_mes": 82.5}, {"categoria": "refrigerador", "kwh_mes": 30}]})
    assert r.status_code == 200
    res = r.json()
    assert res["perfil"] in {"Consciente", "Moderado", "Ineficiente"}
    assert res["kwh_por_morador"] == pytest.approx(37.5)
    assert set(res["comparacao_media"]) == {"mediana_kwh_por_morador", "diferenca_percentual", "texto"}


@pytest.mark.parametrize("corpo", [
    {"moradores": 0, "itens": [{"categoria": "chuveiro", "kwh_mes": 10}]},
    {"moradores": 2, "itens": []},
    {"moradores": 2, "itens": [{"categoria": "chuveiro", "kwh_mes": -1}]},
    {"moradores": 2, "itens": [{"categoria": "chuveiro", "kwh_mes": 0}]},
    {"itens": [{"categoria": "chuveiro", "kwh_mes": 10}]},
])
def test_classificar_rejeita_entrada_invalida(client, corpo):
    assert client.post("/classificar", json=corpo).status_code == 422
