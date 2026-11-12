"""
Idioma das respostas da API (src/idioma.py e src/traducoes.py).

Sem o cabecalho Accept-Language a API responde em portugues, como antes (os outros testes conferem
isso); com "Accept-Language: en", em ingles. Os testes marcados com "banco" leem o PostgreSQL.
"""

import csv
import re
from pathlib import Path

import pytest
from conftest import appliance

import banco
import calculadora_residencial as calc
import estimativa
import idioma
import main
import ml_pipeline
import rag_agent
from traducoes import EN

ROOT = Path(__file__).resolve().parents[1]
IN_ENGLISH = {"Accept-Language": "en"}


# Cabecalho e funcoes de idioma -----------------------------------------------------------------

@pytest.mark.parametrize("header, expected", [
    (None, "pt"), ("", "pt"), ("en", "en"), ("EN-gb", "en"), ("en-US,en;q=0.9", "en"),
    ("pt-BR,pt;q=0.9,en;q=0.8", "pt"), ("fr-FR,fr;q=0.9,en;q=0.8", "en"), ("de", "pt"),
    ("en;q=0.5,pt;q=0.9", "pt"), ("en;q=0", "pt"), ("*", "pt"),
])
def test_header_language(header, expected):
    assert idioma.from_header(header) == expected


def test_portuguese_is_default_and_english_only_applies_inside_with():
    assert idioma.current() == "pt" and idioma.tr("sim", "yes") == "sim"
    with idioma.using("en"):
        assert idioma.tr("sim", "yes") == "yes"
        assert idioma.t(calc.DEFAULT_NOTICE) == EN[calc.DEFAULT_NOTICE]
        assert idioma.t("texto sem traducao") == "texto sem traducao"
    assert idioma.t(calc.DEFAULT_NOTICE) == calc.DEFAULT_NOTICE
    with idioma.using("fr"):  # lingua desconhecida: portugues
        assert idioma.current() == "pt"


def test_numbers_and_units_in_english():
    with idioma.using("en"):
        assert idioma.number(1234.5) == "1,234.5"
        assert idioma.measure("7.500 BTU/h") == "7,500 BTU/h"
        assert idioma.measure("1,5 cv") == "1.5 hp"
        assert idioma.measure("Ex.: 0,25") == "E.g.: 0.25"
        assert idioma.measure("24 polegadas") == "24 inches"
        assert idioma.units("43 pol") == "43 in"
        assert idioma.units("0.5 cv") == "0.5 hp"  # o detalhe do catalogo ja usa ponto decimal
        assert idioma.units("9 W, 806 lm") == "9 W, 806 lm"
    assert idioma.number(1234.5) == "1.234,5"
    assert idioma.measure("1,5 cv") == "1,5 cv"


# Todo texto fixo tem traducao -------------------------------------------------------------------

def _smallAppliances():
    with open(ROOT / "datasets" / "processed" / "eletroportateis.csv", encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


def fixed_texts():
    """Textos fixos que a API pode mostrar e que passam por idioma.t()."""
    texts = {rule["texto"] for rule in calc.EQUIVALENCE.values()}
    for config in calc.ESTIMABLE.values():
        texts.add(config["nome"])
        if config.get("medida"):
            texts.add(config["medida"])
        for shape in config.get("formas", []):
            texts.update(shape[c] for c in ("nome", "rotulo", "unidade", "onde", "dica") if shape[c])
    texts.discard("W")  # unidade igual nas duas linguas
    for name, description in calc.TYPE_NAMES.values():
        texts.update((name, description))
    texts.update(calc.TYPE_NAMES)  # tipos do Inmetro da maquina de lavar e do ar
    texts.update(calc.NO_SUGGESTION.values())
    texts.update([calc.EQUIVALENT_NOTICE, calc.CONVERTED_NOTICE, calc.DEFAULT_NOTICE, calc.USER_TARIFF_NOTICE,
                   "Ainda não sugerimos trocas para este tipo de aparelho."])
    texts.update([estimativa.APPROXIMATE_NOTICE, estimativa.LABEL_NOTICE, estimativa.TYPICAL_POWER_NOTICE])
    for info in estimativa.TYPES.values():
        texts.update((info["nome"], info["tipo_inmetro"]))
    texts.update(estimativa.LINES_2006)
    texts.update([ml_pipeline.ML_NOTICE, rag_agent.ECO_NOTICE, rag_agent.TIP_NOTICE])
    texts.update(rag_agent.NAMES.values())
    for line in _smallAppliances():
        texts.add(line["nome"])
        if line["categoria"] not in rag_agent.NAMES:  # nome que o Eco-Coach monta pela categoria
            texts.add(line["categoria"].replace("_", " "))
    texts.add("ANEEL – tarifas homologadas, B1 residencial")
    return texts


def test_all_fixed_text_has_translation():
    untranslated = sorted(fixed_texts() - set(EN))
    assert not untranslated, f"sem traducao em src/traducoes.py: {untranslated}"


def test_translations_have_no_text_that_no_longer_exists():
    leftover = sorted(set(EN) - fixed_texts())
    assert not leftover, f"chaves de src/traducoes.py que nao aparecem no codigo: {leftover}"


def test_translated_tariff_source_exists_in_code():
    assert "ANEEL – tarifas homologadas, B1 residencial" in (ROOT / "src" / "tarifas_aneel.py").read_text("utf-8")


# Regras de calculo em ingles --------------------------------------------------------------------

def test_calculation_method_and_notices_in_english():
    shower = appliance("chuveiro", potencia_w=5500)
    with idioma.using("en"):
        consumption = calc.monthly_consumption_kwh(shower, daily_hours=0.25)
        r = calc.build_result(shower, consumption, 0.768, "COPEL-DIS", "ANEEL", "PR")
    assert consumption["kwh_mes"] == pytest.approx(41.25)  # o numero nao depende do idioma
    assert consumption["metodo"] == "5500 W x 15 min/day x 30 days (entered)"
    assert r["avisos"] == [EN[calc.DEFAULT_NOTICE]]
    assert calc.monthly_consumption_kwh(shower, daily_hours=0.25)["metodo"] == "5500 W x 15 min/dia x 30 dias (informado)"


def test_fan_in_english():
    fan = appliance("ventilador_de_mesa", kwh_mes_media=3.0)
    with idioma.using("en"):
        method = calc.monthly_consumption_kwh(fan, daily_hours=8, speed="media")["metodo"]
    assert method == "Inmetro consumption at medium speed (3 kWh/month for 1 h/day) adjusted to 8 h/day (entered)"


def test_input_error_in_english():
    with idioma.using("en"), pytest.raises(ValueError, match="enter how many hours per day"):
        calc.monthly_consumption_kwh(appliance("chuveiro", potencia_w=5500))


def test_estimated_fridge_in_english():
    with idioma.using("en"):
        r = estimativa.estimated_refrigerator_consumption("duplex", True, 407, 2014, freezer_volume_l=90,
                                                     kwh_label=52.5, reference_year=2026)
    assert r["nome"] == "Two-door fridge"
    assert r["detalhe"] == "two-door fridge frost-free, 407 L, bought in 2014"
    assert r["avisos"] == [EN[estimativa.LABEL_NOTICE]]
    assert r["metodo"].startswith("label 52.5 kWh/month (old method)")


def test_eco_coach_prompt_asks_english_with_american_numbers():
    sources = [{"orgao": "Cemig", "documento": "Cartilha", "secao": "Chuveiro", "texto": "Use a posição verão."}]
    shower = {"categoria": "chuveiro", "nome": "Chuveiro", "kwh_mes": 1234.5, "custo_mes": 948.1}
    pt = rag_agent.build_prompt_tips(shower, sources)
    with idioma.using("en"):
        en = rag_agent.build_prompt_tips(shower, sources)
    assert "IDIOMA DA RESPOSTA" not in pt and "1.234,50 kWh/mês" in pt and "R$ 948,10/mês" in pt
    assert "IDIOMA DA RESPOSTA" in en and "1,234.50 kWh/month" in en and "R$ 948.10/month" in en
    assert "/mês" not in en  # o LLM copia a unidade dos dados
    assert "Use a posição verão." in en  # as fontes continuam em portugues: o LLM traduz


# API ---------------------------------------------------------------------------------------------

def test_api_responds_in_header_language(client):
    body = {"moradores": 2, "itens": [{"categoria": "chuveiro", "kwh_mes": 80}]}
    en = client.post("/classificar", json=body, headers={"Accept-Language": "en-US,en;q=0.9"})
    pt = client.post("/classificar", json=body)
    assert en.status_code == pt.status_code == 200
    assert "median per resident" in en.json()["comparacao_media"]["texto"]
    assert en.json()["aviso"] == EN[ml_pipeline.ML_NOTICE]
    assert en.json()["perfil"] == pt.json()["perfil"]  # o perfil e uma chave: o app traduz o nome
    assert "mediana por morador" in pt.json()["comparacao_media"]["texto"]
    assert en.headers["content-language"] == "en" and pt.headers["content-language"] == "pt-BR"
    assert "Accept-Language" in en.headers["vary"]


def test_api_error_in_english(client):
    # rota sincrona (roda numa thread): o idioma da requisicao chega ate a regra de negocio
    body = {"moradores": 2, "itens": [{"categoria": "chuveiro", "kwh_mes": 0}]}
    en = client.post("/classificar", json=body, headers=IN_ENGLISH)
    assert en.status_code == 422 and en.json()["detail"] == "the total consumption must be greater than zero"
    assert client.post("/classificar", json=body).json()["detail"] == "o consumo total precisa ser maior que zero"


def test_error_in_english_is_still_404():
    assert main.service_error(ValueError("appliance 9 does not exist")).status_code == 404
    assert main.service_error(ValueError("power company 9 has no current tariff")).status_code == 404
    assert main.service_error(ValueError("enter how many hours per day")).status_code == 422


@pytest.mark.banco
def test_estimable_categories_in_english(api):
    categories = {c["categoria"]: c for c in api.get("/estimativa/categorias", headers=IN_ENGLISH).json()}
    washing = categories["maquina_de_lavar"]
    assert washing["nome"] == "Washing machine" and washing["medida"] == "Washing capacity (kg)"
    assert washing["tipos"][0] == {"valor": "Top Load (automatica)", "nome": "Automatic, top-loading",
                                 "descricao": "Lid on top. It washes, rinses and spins on its own."}
    assert washing["formas"][0]["unidade"] == "kWh/cycle" and washing["formas"][0]["exemplo"] == "E.g.: 0.25"
    assert categories["televisor"]["unidade_medida"] == "inches"
    assert categories["televisor"]["tamanhos"][0]["nome"] == "24 inches"
    assert categories["ar_condicionado"]["tamanhos"][0]["nome"] == "7,500 BTU/h"
    assert categories["bomba"]["tamanhos"][-1]["nome"] == "1.5 hp"


@pytest.mark.banco
def test_calculation_by_api_in_english(api, con):
    shower = banco.query(con, "SELECT id FROM aparelhos WHERE categoria = ? ORDER BY id LIMIT 1", ("chuveiro",))
    body = {"registrar": False, "aparelho_id": int(shower.iloc[0]["id"]), "tarifa_manual": 0.8, "horas_dia": 0.25}
    en = api.post("/calcular", json=body, headers=IN_ENGLISH).json()
    pt = api.post("/calcular", json=body).json()
    assert en["custo_mes"] == pt["custo_mes"]
    assert "days (entered)" in en["metodo"] and "dias (informado)" in pt["metodo"]
    assert en["origem_tarifa"] == "entered by the user (electricity bill)"
    assert en["avisos"][0] == EN[calc.USER_TARIFF_NOTICE]


@pytest.mark.banco
def test_small_appliances_in_english(api):
    names = [p["nome"] for p in api.get("/resistivos", headers=IN_ENGLISH).json()]
    assert "Hair dryer" in names and names == sorted(names, key=str.lower)
    assert not any(re.search(r"[áéíóúãõç]", n) for n in names)
