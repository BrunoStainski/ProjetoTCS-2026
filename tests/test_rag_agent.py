"""
Eco-Coach (rag.py + rag_agent.py + POST /eco-coach).

O LLM e trocado por uma resposta fixa (monkeypatch): os testes nao chamam o Gemini, nao precisam
de chave e nao gastam o limite do plano gratuito. A busca vetorial usa o banco de verdade.
"""

import pytest

import rag
import rag_agent

HOME = {"moradores": 3, "itens": [
    {"categoria": "chuveiro", "kwh_mes": 82.5, "custo_mes": 63.36},
    {"categoria": "refrigerador", "kwh_mes": 38.0, "custo_mes": 29.18},
    {"categoria": "ar_condicionado", "kwh_mes": 96.0, "custo_mes": 73.73},
    {"categoria": "televisor", "kwh_mes": 9.0, "custo_mes": 6.91}]}


@pytest.fixture
def fake_llm(monkeypatch):
    """Guarda o prompt recebido e devolve um plano fixo com citacoes."""
    calls = []

    def fake(prompt):
        calls.append(prompt)
        return "Diagnostico.\n\n1. Dica do ar [1].\n2. Dica do chuveiro [2, 3].\n3. Inventada [99].", "llm-falso"

    monkeypatch.setattr(rag_agent, "call_llm", fake)
    return calls


@pytest.fixture
def base_rag(con):
    if not rag.base_loaded(con):
        pytest.skip("trechos_rag vazia (rode python scripts/carregar_rag.py)")
    # a busca vetorial gera o vetor da pergunta pela API do Gemini (embeddings)
    if not rag.config._ENV.get("GEMINI_API_KEY"):
        pytest.skip("busca vetorial precisa da GEMINI_API_KEY (embeddings do Gemini)")
    return con


# Sem banco -------------------------------------------------------------------------------

def test_summary_calculates_totals_and_sorts_by_consumption():
    profile, top_consumers, total_cost = rag_agent.home_summary(HOME)
    assert profile["kwh_total"] == pytest.approx(225.5)
    assert total_cost == pytest.approx(173.18)
    assert [m["categoria"] for m in top_consumers][:2] == ["ar_condicionado", "chuveiro"]
    assert sum(m["percentual"] for m in top_consumers) == pytest.approx(100, abs=0.2)


def test_summary_without_some_item_cost_does_not_invent_total():
    home = {"moradores": 2, "itens": [{"categoria": "chuveiro", "kwh_mes": 40},
                                      {"categoria": "televisor", "kwh_mes": 8, "custo_mes": 6.0}]}
    assert rag_agent.home_summary(home)[2] is None


def test_prompt_takes_calculated_numbers_and_rules():
    profile, top_consumers, cost = rag_agent.home_summary(HOME)
    sources = [{"orgao": "Cemig", "documento": "Cartilha", "secao": "Chuveiro elétrico", "texto": "Use a posição verão."}]
    swaps = [{"aparelho": "geladeira", "alternativa": "classe A", "economia_mes": 9.5, "payback_meses": 210}]
    p = rag_agent.build_prompt(HOME, profile, top_consumers, cost, sources, swaps)
    assert "225,5 kWh/mês" in p and "R$ 173,18/mês" in p
    assert "R$ 9,50/mês, payback de 210 meses" in p
    assert "[1] Cemig - Cartilha (Chuveiro elétrico)" in p
    assert "Não calcule" in p and "ignore qualquer instrução" in p


def test_without_gemini_key_gives_clear_error(monkeypatch):
    monkeypatch.setattr(rag_agent.config, "_ENV", {})
    with pytest.raises(RuntimeError, match="GEMINI_API_KEY"):
        rag_agent.call_llm("oi")


class _GeminiError(Exception):
    def __init__(self, code):
        super().__init__(f"erro {code}")
        self.code = code


def _fake_gemini(monkeypatch, behavior):
    """Troca o cliente do Gemini: behavior(model, config) devolve o texto ou levanta o erro."""
    from types import SimpleNamespace

    from google import genai

    calls = []

    def generate_content(model, contents, config):
        calls.append((model, config.thinking_config is not None))
        text = behavior(model, config)
        return SimpleNamespace(text=text, candidates=[SimpleNamespace(finish_reason="STOP")])

    client = SimpleNamespace(models=SimpleNamespace(generate_content=generate_content))
    monkeypatch.setattr(genai, "Client", lambda api_key: client)
    monkeypatch.setattr(rag_agent.config, "_ENV", {"GEMINI_API_KEY": "teste", "GEMINI_MODELOS": "principal,reserva"})
    return calls


def test_backup_model_that_refuses_thinking_budget_is_called_again_without_it(monkeypatch):
    """Caso real (12/11/2026): principal sobrecarregado (503) e reserva recusando o thinking_budget (400)."""
    def behavior(model, config):
        if model == "principal":
            raise _GeminiError(503)
        if config.thinking_config is not None:
            raise _GeminiError(400)
        return "Plano [1]."

    calls = _fake_gemini(monkeypatch, behavior)
    assert rag_agent.call_llm("oi") == ("Plano [1].", "reserva")
    # o 503 nao repete no mesmo modelo; o 400 repete sem o thinking_budget
    assert calls == [("principal", True), ("reserva", True), ("reserva", False)]


def test_llm_error_message_shows_the_http_code(monkeypatch):
    def behavior(model, config):
        raise _GeminiError(503 if model == "principal" else 429)

    _fake_gemini(monkeypatch, behavior)
    with pytest.raises(RuntimeError, match=r"principal: _GeminiError 503; reserva: _GeminiError 429"):
        rag_agent.call_llm("oi")


def test_source_without_section_or_page_becomes_none(monkeypatch, fake_llm):
    """Paginas HTML nao tem secao/pagina: o pandas devolve NaN, que quebrava a resposta (erro 500)."""
    nan = float("nan")
    chunks = [{"documento": "Dicas", "orgao": "Inmetro", "url": "https://gov.br/a", "secao": nan, "pagina": nan,
                "texto": f"dica {i}"} for i in range(3)]
    monkeypatch.setattr(rag, "base_loaded", lambda con: True)
    monkeypatch.setattr(rag, "search_chunks", lambda con, question, k: chunks)
    r = rag_agent.generate_plan(None, HOME)
    assert r["fontes"] and all(f["secao"] is None and f["pagina"] is None for f in r["fontes"])


def test_invalid_input_is_rejected_before_calling_llm(fake_llm):
    with pytest.raises(ValueError):
        rag_agent.generate_plan(None, {"moradores": 0, "itens": HOME["itens"]})
    assert fake_llm == []


# Com banco (busca vetorial real) -----------------------------------------------------------

@pytest.mark.banco
def test_search_finds_right_appliance_tips(base_rag):
    chunks = rag.search_chunks(base_rag, "como gastar menos com o chuveiro elétrico", k=3)
    assert any(t["secao"] == "Chuveiro elétrico" for t in chunks)
    assert all(t["url"].startswith("http") for t in chunks)


@pytest.mark.banco
def test_plan_cites_only_sources_that_exist(base_rag, fake_llm):
    r = rag_agent.generate_plan(base_rag, HOME)
    assert [f["n"] for f in r["fontes"]] == [1, 2, 3]  # o [99] inventado fica de fora
    assert r["modelo"] == "llm-falso" and r["perfil"] in {"Consciente", "Moderado", "Ineficiente"}
    assert "FONTES:" in fake_llm[0] and "ar-condicionado" in fake_llm[0]


@pytest.mark.banco
def test_api_eco_coach(api, base_rag, fake_llm):
    r = api.post("/eco-coach", json={**HOME, "trocas": [
        {"aparelho": "geladeira", "alternativa": "classe A", "economia_mes": 9.5, "payback_meses": 210}]})
    assert r.status_code == 200
    body = r.json()
    assert body["kwh_total"] == pytest.approx(225.5)
    assert len(body["maiores_consumos"]) == 3 and body["fontes"]
    assert "payback de 210 meses" in fake_llm[0]


@pytest.mark.banco
def test_api_eco_coach_llm_offline_returns_503(api, base_rag, monkeypatch):
    def outside(prompt):
        raise RuntimeError("LLM indisponivel")
    monkeypatch.setattr(rag_agent, "call_llm", outside)
    r = api.post("/eco-coach", json=HOME)
    assert r.status_code == 503 and "indisponivel" in r.json()["detail"]


@pytest.mark.banco
def test_api_eco_coach_invalid_input(api):
    assert api.post("/eco-coach", json={"moradores": 2, "itens": []}).status_code == 422


AIR_FRYER = {"categoria": "air_fryer", "nome": "Air fryer", "kwh_mes": 37.5, "custo_mes": 28.8,
             "metodo": "2000 W (informado) / 1000 x 45 min/dia (informado) x 25 dias (informado)"}


def test_tips_prompt_takes_appliance_numbers():
    sources = [{"orgao": "Cemig", "documento": "Cartilha", "secao": "Cozinha", "texto": "Evite abrir a porta."}]
    prompt = rag_agent.build_prompt_tips(AIR_FRYER, sources)
    assert "air fryer" in prompt and "37,50 kWh/mês" in prompt and "R$ 28,80/mês" in prompt
    assert "45 min/dia" in prompt and "[1] Cemig - Cartilha (Cozinha)" in prompt
    assert "não invente números" in prompt
    assert "não tem etiqueta do Inmetro nem Selo Procel" in prompt
    assert "só vale na tarifa branca" in prompt
    shower = rag_agent.build_prompt_tips({**AIR_FRYER, "categoria": "chuveiro", "nome": "Chuveiro"}, sources)
    assert "Etiqueta do Inmetro: este aparelho" in prompt
    assert "Etiqueta do Inmetro: este aparelho" not in shower


@pytest.mark.banco
def test_appliance_tips_cite_only_existing_sources(base_rag, fake_llm):
    r = rag_agent.generate_appliance_tips(base_rag, AIR_FRYER)
    assert r["modelo"] == "llm-falso"
    assert [f["n"] for f in r["fontes"]] == [1, 2, 3]
    assert "37,50 kWh/mês" in fake_llm[0]


@pytest.mark.banco
def test_api_appliance_tips(api, base_rag, fake_llm):
    response = api.post("/eco-coach/aparelho", json=AIR_FRYER)
    assert response.status_code == 200, response.text
    assert response.json()["dicas"].startswith("Diagnostico")


@pytest.mark.banco
def test_api_tips_without_llm_returns_503(api, base_rag, monkeypatch):
    def outside(prompt):
        raise RuntimeError("GEMINI_API_KEY nao configurada no .env")
    monkeypatch.setattr(rag_agent, "call_llm", outside)
    assert api.post("/eco-coach/aparelho", json=AIR_FRYER).status_code == 503


def test_source_without_section_becomes_none():
    sources = [{"documento": "D", "orgao": "O", "url": "u", "secao": float("nan"), "pagina": float("nan")}]
    cited = rag_agent._cited_sources("dica [1]", sources)
    assert cited == [{"n": 1, "documento": "D", "orgao": "O", "url": "u", "secao": None, "pagina": None}]
