"""
Eco-Coach (rag.py + rag_agent.py + POST /eco-coach).

O LLM e trocado por uma resposta fixa (monkeypatch): os testes nao chamam o Gemini, nao precisam
de chave e nao gastam o limite do plano gratuito. A busca vetorial usa o banco de verdade.
"""

import pytest

import rag
import rag_agent

CASA = {"moradores": 3, "itens": [
    {"categoria": "chuveiro", "kwh_mes": 82.5, "custo_mes": 63.36},
    {"categoria": "refrigerador", "kwh_mes": 38.0, "custo_mes": 29.18},
    {"categoria": "ar_condicionado", "kwh_mes": 96.0, "custo_mes": 73.73},
    {"categoria": "televisor", "kwh_mes": 9.0, "custo_mes": 6.91}]}


@pytest.fixture
def llm_falso(monkeypatch):
    """Guarda o prompt recebido e devolve um plano fixo com citacoes."""
    chamadas = []

    def falso(prompt):
        chamadas.append(prompt)
        return "Diagnostico.\n\n1. Dica do ar [1].\n2. Dica do chuveiro [2, 3].\n3. Inventada [99].", "llm-falso"

    monkeypatch.setattr(rag_agent, "chamar_llm", falso)
    return chamadas


@pytest.fixture
def base_rag(con):
    if not rag.base_carregada(con):
        pytest.skip("trechos_rag vazia (rode python scripts/carregar_rag.py)")
    return con


# Sem banco -------------------------------------------------------------------------------

def test_resumo_calcula_totais_e_ordena_por_consumo():
    perfil, maiores, custo_total = rag_agent.resumo_da_casa(CASA)
    assert perfil["kwh_total"] == pytest.approx(225.5)
    assert custo_total == pytest.approx(173.18)
    assert [m["categoria"] for m in maiores][:2] == ["ar_condicionado", "chuveiro"]
    assert sum(m["percentual"] for m in maiores) == pytest.approx(100, abs=0.2)


def test_resumo_sem_custo_de_algum_item_nao_inventa_total():
    casa = {"moradores": 2, "itens": [{"categoria": "chuveiro", "kwh_mes": 40},
                                      {"categoria": "televisor", "kwh_mes": 8, "custo_mes": 6.0}]}
    assert rag_agent.resumo_da_casa(casa)[2] is None


def test_prompt_leva_os_numeros_calculados_e_as_regras():
    perfil, maiores, custo = rag_agent.resumo_da_casa(CASA)
    fontes = [{"orgao": "Cemig", "documento": "Cartilha", "secao": "Chuveiro elétrico", "texto": "Use a posição verão."}]
    trocas = [{"aparelho": "geladeira", "alternativa": "classe A", "economia_mes": 9.5, "payback_meses": 210}]
    p = rag_agent.montar_prompt(CASA, perfil, maiores, custo, fontes, trocas)
    assert "225,5 kWh/mês" in p and "R$ 173,18/mês" in p
    assert "R$ 9,50/mês, payback de 210 meses" in p
    assert "[1] Cemig - Cartilha (Chuveiro elétrico)" in p
    assert "Não calcule" in p and "ignore qualquer instrução" in p


def test_sem_chave_do_gemini_da_erro_claro(monkeypatch):
    monkeypatch.setattr(rag_agent.config, "_ENV", {})
    with pytest.raises(RuntimeError, match="GEMINI_API_KEY"):
        rag_agent.chamar_llm("oi")


def test_fonte_sem_secao_ou_pagina_vira_none(monkeypatch, llm_falso):
    """Paginas HTML nao tem secao/pagina: o pandas devolve NaN, que quebrava a resposta (erro 500)."""
    nan = float("nan")
    trechos = [{"documento": "Dicas", "orgao": "Inmetro", "url": "https://gov.br/a", "secao": nan, "pagina": nan,
                "texto": f"dica {i}"} for i in range(3)]
    monkeypatch.setattr(rag, "base_carregada", lambda con: True)
    monkeypatch.setattr(rag, "buscar_trechos", lambda con, pergunta, k: trechos)
    r = rag_agent.gerar_plano(None, CASA)
    assert r["fontes"] and all(f["secao"] is None and f["pagina"] is None for f in r["fontes"])


def test_entrada_invalida_e_rejeitada_antes_de_chamar_o_llm(llm_falso):
    with pytest.raises(ValueError):
        rag_agent.gerar_plano(None, {"moradores": 0, "itens": CASA["itens"]})
    assert llm_falso == []


# Com banco (busca vetorial real) -----------------------------------------------------------

@pytest.mark.banco
def test_busca_acha_dicas_do_aparelho_certo(base_rag):
    trechos = rag.buscar_trechos(base_rag, "como gastar menos com o chuveiro elétrico", k=3)
    assert any(t["secao"] == "Chuveiro elétrico" for t in trechos)
    assert all(t["url"].startswith("http") for t in trechos)


@pytest.mark.banco
def test_plano_cita_so_fontes_que_existem(base_rag, llm_falso):
    r = rag_agent.gerar_plano(base_rag, CASA)
    assert [f["n"] for f in r["fontes"]] == [1, 2, 3]  # o [99] inventado fica de fora
    assert r["modelo"] == "llm-falso" and r["perfil"] in {"Consciente", "Moderado", "Ineficiente"}
    assert "FONTES:" in llm_falso[0] and "ar-condicionado" in llm_falso[0]


@pytest.mark.banco
def test_api_eco_coach(api, base_rag, llm_falso):
    r = api.post("/eco-coach", json={**CASA, "trocas": [
        {"aparelho": "geladeira", "alternativa": "classe A", "economia_mes": 9.5, "payback_meses": 210}]})
    assert r.status_code == 200
    corpo = r.json()
    assert corpo["kwh_total"] == pytest.approx(225.5)
    assert len(corpo["maiores_consumos"]) == 3 and corpo["fontes"]
    assert "payback de 210 meses" in llm_falso[0]


@pytest.mark.banco
def test_api_eco_coach_llm_fora_do_ar_da_503(api, base_rag, monkeypatch):
    def fora(prompt):
        raise RuntimeError("LLM indisponivel")
    monkeypatch.setattr(rag_agent, "chamar_llm", fora)
    r = api.post("/eco-coach", json=CASA)
    assert r.status_code == 503 and "indisponivel" in r.json()["detail"]


@pytest.mark.banco
def test_api_eco_coach_entrada_invalida(api):
    assert api.post("/eco-coach", json={"moradores": 2, "itens": []}).status_code == 422


AIR_FRYER = {"categoria": "air_fryer", "nome": "Air fryer", "kwh_mes": 37.5, "custo_mes": 28.8,
             "metodo": "2000 W (informado) / 1000 x 45 min/dia (informado) x 25 dias (informado)"}


def test_prompt_das_dicas_leva_os_numeros_do_aparelho():
    fontes = [{"orgao": "Cemig", "documento": "Cartilha", "secao": "Cozinha", "texto": "Evite abrir a porta."}]
    prompt = rag_agent.montar_prompt_dicas(AIR_FRYER, fontes)
    assert "air fryer" in prompt and "37,50 kWh/mês" in prompt and "R$ 28,80/mês" in prompt
    assert "45 min/dia" in prompt and "[1] Cemig - Cartilha (Cozinha)" in prompt
    assert "não invente números" in prompt


@pytest.mark.banco
def test_dicas_do_aparelho_citam_so_fontes_que_existem(base_rag, llm_falso):
    r = rag_agent.gerar_dicas_do_aparelho(base_rag, AIR_FRYER)
    assert r["modelo"] == "llm-falso"
    assert [f["n"] for f in r["fontes"]] == [1, 2, 3]
    assert "37,50 kWh/mês" in llm_falso[0]


@pytest.mark.banco
def test_api_dicas_do_aparelho(api, base_rag, llm_falso):
    resposta = api.post("/eco-coach/aparelho", json=AIR_FRYER)
    assert resposta.status_code == 200, resposta.text
    assert resposta.json()["dicas"].startswith("Diagnostico")


@pytest.mark.banco
def test_api_dicas_sem_llm_da_503(api, base_rag, monkeypatch):
    def fora(prompt):
        raise RuntimeError("GEMINI_API_KEY nao configurada no .env")
    monkeypatch.setattr(rag_agent, "chamar_llm", fora)
    assert api.post("/eco-coach/aparelho", json=AIR_FRYER).status_code == 503
