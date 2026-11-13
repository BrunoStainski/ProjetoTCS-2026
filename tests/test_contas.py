"""
Contas e casas na nuvem (src/contas.py e as rotas /contas, /login, /conta, /casas).

Os testes com "api_contas" usam o PostgreSQL (pulados sem ele). Cada teste cria contas com e-mail
aleatorio e apaga no fim, para nao deixar lixo no banco.
"""

import uuid

import pytest

import banco
import contas


# Sem banco ----------------------------------------------------------------------------------

def test_senha_vira_hash_com_sal():
    first, second = contas.hash_password("segredo123"), contas.hash_password("segredo123")
    assert first != second  # sal diferente a cada vez
    assert "segredo123" not in first
    assert contas.check_password("segredo123", first)
    assert not contas.check_password("segredo124", first)


def test_hash_estragado_nao_entra():
    assert not contas.check_password("qualquer", "lixo")
    assert not contas.check_password("qualquer", "scrypt$1$2$3$zz$zz")


# Com banco ----------------------------------------------------------------------------------

@pytest.fixture
def api_contas(api, con):
    contas.create_tables(con)
    created = []

    def new_account(name="Maria Teste", password="senha-forte-1"):
        email = f"teste-{uuid.uuid4().hex[:10]}@exemplo.com"
        r = api.post("/contas", json={"nome": name, "email": email, "senha": password, "aceite_privacidade": True})
        assert r.status_code == 201, r.text
        body = r.json()
        created.append(body["token"])
        return email, {"Authorization": f"Bearer {body['token']}"}, body

    yield api, new_account
    for token in created:
        api.delete("/conta", headers={"Authorization": f"Bearer {token}"})


def item(category="chuveiro", kwh=41.25, cost=31.68, quantity=1):
    return {"quantidade": quantity, "categoria": category, "kwh_mes": kwh, "custo_mes": cost,
            "dados": {"consulta": {"aparelho_id": 1}, "resultado": {"kwh_mes": kwh, "custo_mes": cost}}}


@pytest.mark.banco
def test_cadastro_exige_aceite_do_aviso(api_contas):
    api, _ = api_contas
    r = api.post("/contas", json={"nome": "Ana", "email": "ana@exemplo.com", "senha": "senha-forte-1",
                                  "aceite_privacidade": False})
    assert r.status_code == 422


@pytest.mark.banco
def test_cadastro_login_e_conta(api_contas, con):
    api, new_account = api_contas
    email, auth, body = new_account()
    assert body["conta"]["email"] == email
    assert body["conta"]["versao_aviso"] == contas.PRIVACY_VERSION
    assert "senha" not in body["conta"]

    # a senha nao e gravada em texto
    stored = con.exec_driver_sql("SELECT senha_hash FROM usuarios WHERE email = %(e)s", {"e": email}).scalar_one()
    assert stored.startswith("scrypt$") and "senha-forte-1" not in stored

    # e-mail repetido (maiusculas tambem)
    r = api.post("/contas", json={"nome": "Outra", "email": email.upper(), "senha": "senha-forte-1",
                                  "aceite_privacidade": True})
    assert r.status_code == 409

    assert api.post("/login", json={"email": email, "senha": "errada-123"}).status_code == 401
    assert api.post("/login", json={"email": "ninguem@exemplo.com", "senha": "errada-123"}).status_code == 401
    r = api.post("/login", json={"email": f"  {email.upper()} ", "senha": "senha-forte-1"})
    assert r.status_code == 200 and r.json()["token"]

    assert api.get("/conta", headers=auth).json()["nome"] == "Maria Teste"
    assert api.patch("/conta", headers=auth, json={"nome": "Maria Souza"}).json()["nome"] == "Maria Souza"


@pytest.mark.banco
def test_senha_curta_e_email_invalido(api_contas):
    api, _ = api_contas
    base = {"nome": "Ana", "aceite_privacidade": True}
    assert api.post("/contas", json={**base, "email": "ana@exemplo.com", "senha": "curta"}).status_code == 422
    assert api.post("/contas", json={**base, "email": "sem-arroba", "senha": "senha-forte-1"}).status_code == 422


@pytest.mark.banco
def test_rotas_da_conta_pedem_token(api_contas):
    api, _ = api_contas
    assert api.get("/casas").status_code == 401
    assert api.get("/conta", headers={"Authorization": "Bearer token-inventado"}).status_code == 401


@pytest.mark.banco
def test_varias_casas_na_mesma_conta(api_contas):
    api, new_account = api_contas
    _, auth, _ = new_account()

    home = api.post("/casas", headers=auth, json={"nome": "Casa", "moradores": 3}).json()
    beach = api.post("/casas", headers=auth, json={"nome": "Casa da praia"}).json()
    assert [c["nome"] for c in api.get("/casas", headers=auth).json()] == ["Casa", "Casa da praia"]
    assert beach["moradores"] == 2 and beach["itens"] == []

    tariff = {"distribuidora_id": 7, "descricao": "COPEL-DIS"}
    r = api.put(f"/casas/{home['id']}", headers=auth, json={
        "nome": "Casa", "moradores": 3, "ultima_tarifa": tariff,
        "itens": [item(), item("geladeira", 30.0, 23.0, quantity=2)]})
    assert r.status_code == 200, r.text
    saved = r.json()
    assert [i["categoria"] for i in saved["itens"]] == ["chuveiro", "geladeira"]
    assert saved["itens"][1]["quantidade"] == 2
    assert saved["itens"][0]["dados"]["consulta"] == {"aparelho_id": 1}
    assert saved["ultima_tarifa"] == tariff

    # gravar de novo substitui a lista (removeu o chuveiro)
    r = api.put(f"/casas/{home['id']}", headers=auth, json={"nome": "Casa", "moradores": 3,
                                                             "itens": [item("geladeira")]})
    assert [i["categoria"] for i in r.json()["itens"]] == ["geladeira"]
    # a outra casa nao mudou
    assert api.get("/casas", headers=auth).json()[1]["itens"] == []

    assert api.delete(f"/casas/{beach['id']}", headers=auth).status_code == 204
    assert [c["nome"] for c in api.get("/casas", headers=auth).json()] == ["Casa"]

    exported = api.get("/conta/dados", headers=auth).json()
    assert exported["casas"][0]["itens"][0]["categoria"] == "geladeira"
    assert "senha" not in str(exported)


@pytest.mark.banco
def test_ninguem_ve_a_casa_do_outro(api_contas):
    api, new_account = api_contas
    _, maria, _ = new_account("Maria")
    _, joao, _ = new_account("Joao")
    house = api.post("/casas", headers=maria, json={"nome": "Casa da Maria"}).json()

    assert api.get("/casas", headers=joao).json() == []
    assert api.put(f"/casas/{house['id']}", headers=joao, json={"nome": "Minha", "itens": []}).status_code == 404
    assert api.delete(f"/casas/{house['id']}", headers=joao).status_code == 404
    assert api.get("/casas", headers=maria).json()[0]["nome"] == "Casa da Maria"


@pytest.mark.banco
def test_sair_e_apagar_a_conta(api_contas, con):
    api, new_account = api_contas
    email, auth, body = new_account()
    api.post("/casas", headers=auth, json={"nome": "Casa"})

    login = api.post("/login", json={"email": email, "senha": "senha-forte-1"}).json()
    other_device = {"Authorization": f"Bearer {login['token']}"}
    assert api.post("/logout", headers=auth).status_code == 204
    assert api.get("/casas", headers=auth).status_code == 401
    assert api.get("/casas", headers=other_device).status_code == 200  # o outro aparelho continua

    assert api.delete("/conta", headers=other_device).status_code == 204
    assert api.get("/casas", headers=other_device).status_code == 401
    user_id = body["conta"]["id"]
    for table in ("usuarios", "sessoes", "casas"):
        column = "id" if table == "usuarios" else "usuario_id"
        assert con.exec_driver_sql(f"SELECT COUNT(*) FROM {table} WHERE {column} = %(u)s",
                                   {"u": user_id}).scalar_one() == 0


@pytest.mark.banco
def test_old_appliance_id_is_fixed_by_name(con):
    """Recarregar o catalogo muda os ids: o item salvo volta com o id certo do mesmo aparelho."""
    a = banco.run(con, "SELECT id, categoria, marca, modelo, detalhe FROM aparelhos "
                       "WHERE categoria = 'refrigerador' ORDER BY id LIMIT 1").mappings().one()
    other = banco.run(con, "SELECT id FROM aparelhos WHERE categoria = 'televisor' ORDER BY id LIMIT 1").scalar_one()

    def item(appliance, estimate=None):
        return {"consulta": {"aparelho": appliance, "estimativa": estimate}, "resultado": {}}

    moved = contas.refresh_appliance_id(con, item({**a, "id": other}))  # id antigo que hoje e de outro aparelho
    gone = contas.refresh_appliance_id(con, item({"id": other, "categoria": "refrigerador", "marca": "NAO EXISTE", "modelo": "X"}))
    estimated = contas.refresh_appliance_id(con, item({"id": 0, "categoria": "refrigerador", "marca": "Geladeira", "modelo": ""},
                                                      {"rota": "/calcular/refrigerador-antigo", "dados": {}}))
    same = contas.refresh_appliance_id(con, item(dict(a)))
    assert moved["consulta"]["aparelho"]["id"] == a["id"]
    assert gone["consulta"]["aparelho"]["id"] == 0
    assert estimated["consulta"]["aparelho"]["id"] == 0
    assert same["consulta"]["aparelho"]["id"] == a["id"]


@pytest.mark.banco
def test_old_id_of_the_other_voltage_is_fixed(con):
    """Mesmo nome nas versoes 127 V e 220 V: o id que hoje e da outra versao volta para a certa (pelo detalhe)."""
    rows = banco.run(con, "SELECT id, categoria, marca, modelo, detalhe, tensao FROM aparelhos "
                          "WHERE marca = 'CARDAL' AND modelo = 'DUCHA 5 LUXO' ORDER BY tensao").mappings().all()
    if len(rows) != 2:
        pytest.skip("Cardal Ducha 5 Luxo nao esta nas duas tensoes")
    v127, v220 = rows
    saved = {**{k: v220[k] for k in ("categoria", "marca", "modelo", "detalhe")}, "id": v127["id"]}
    fixed = contas.refresh_appliance_id(con, {"consulta": {"aparelho": saved, "estimativa": None}})
    assert fixed["consulta"]["aparelho"]["id"] == v220["id"]


@pytest.mark.banco
def test_too_many_wrong_passwords_wait(api_contas):
    """5 senhas erradas seguidas: a 6a tentativa espera (429), mesmo com a senha certa."""
    api, new_account = api_contas
    email, _, _ = new_account()
    try:
        for _ in range(contas.MAX_FAILURES):
            assert api.post("/login", json={"email": email, "senha": "errada-123"}).status_code == 401
        r = api.post("/login", json={"email": email, "senha": "senha-forte-1"})
        assert r.status_code == 429 and "15 minutos" in r.json()["detail"]
    finally:
        contas._failures.pop(email, None)
    # depois da espera (aqui, zerada), a senha certa entra e zera a contagem
    assert api.post("/login", json={"email": email, "senha": "senha-forte-1"}).status_code == 200


@pytest.mark.banco
def test_password_with_invalid_unicode_does_not_break(api):
    """Senha com um caractere Unicode invalido (um surrogate escapado no JSON) dava erro 500 no cadastro e no login."""
    password = "abc" + chr(0xD800) + "defgh"
    assert contas.check_password(password, contas.hash_password(password))
    bs = chr(92)
    body = ('{"email": "ninguem-unicode@exemplo.com", "senha": "abc' + bs + 'ud800defgh"}').encode()
    r = api.post("/login", content=body, headers={"Content-Type": "application/json"})
    assert r.status_code == 422  # o validador recusa; antes a resposta de erro quebrava (500)


@pytest.mark.banco
def test_validation_error_does_not_echo_the_password(api):
    """O 422 nao devolve o que foi enviado (antes uma senha longa demais voltava inteira na resposta)."""
    secret = "segredo-" + "x" * 200
    r = api.post("/login", json={"email": "a@exemplo.com", "senha": secret})
    assert r.status_code == 422
    assert "segredo-" not in r.text and r.json()["detail"][0]["msg"]


@pytest.mark.banco
def test_changing_the_email_asks_for_the_password(api_contas):
    """Trocar o e-mail pede a senha atual (403 se errada ou faltando); trocar so o nome nao pede."""
    api, new_account = api_contas
    email, auth, _ = new_account()
    new_email = "trocado-" + email
    assert api.patch("/conta", headers=auth, json={"nome": "Maria Souza"}).status_code == 200
    assert api.patch("/conta", headers=auth, json={"email": new_email}).status_code == 403
    assert api.patch("/conta", headers=auth, json={"email": new_email, "senha_atual": "errada-123"}).status_code == 403
    r = api.patch("/conta", headers=auth, json={"email": new_email, "senha_atual": "senha-forte-1"})
    assert r.status_code == 200 and r.json()["email"] == new_email
    # mesmo e-mail (so maiusculas diferentes) nao e troca: nao pede senha
    assert api.patch("/conta", headers=auth, json={"email": new_email.upper()}).status_code == 200


@pytest.mark.banco
def test_login_clears_everyones_expired_sessions(api_contas, con):
    """Sessao vencida de qualquer conta sai no proximo login (antes ficava para sempre em conta abandonada)."""
    api, new_account = api_contas
    _, auth_a, body_a = new_account()
    banco.run(con, "UPDATE sessoes SET expira_em = now() - interval '1 day' WHERE usuario_id = ?",
              (body_a["conta"]["id"],))
    con.commit()
    new_account()  # outra pessoa entra
    left = banco.run(con, "SELECT COUNT(*) FROM sessoes WHERE usuario_id = ?", (body_a["conta"]["id"],)).scalar_one()
    assert left == 0
