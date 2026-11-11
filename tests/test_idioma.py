"""
Idioma das respostas da API (src/idioma.py e src/traducoes.py).

Sem o cabecalho Accept-Language a API responde em portugues, como antes (os outros testes conferem
isso); com "Accept-Language: en", em ingles. Os testes marcados com "banco" leem o PostgreSQL.
"""

import csv
import re
from pathlib import Path

import pytest
from conftest import aparelho

import banco
import calculadora_residencial as calc
import estimativa
import idioma
import main
import ml_pipeline
import rag_agent
from traducoes import EN

RAIZ = Path(__file__).resolve().parents[1]
EM_INGLES = {"Accept-Language": "en"}


# Cabecalho e funcoes de idioma -----------------------------------------------------------------

@pytest.mark.parametrize("cabecalho, esperado", [
    (None, "pt"), ("", "pt"), ("en", "en"), ("EN-gb", "en"), ("en-US,en;q=0.9", "en"),
    ("pt-BR,pt;q=0.9,en;q=0.8", "pt"), ("fr-FR,fr;q=0.9,en;q=0.8", "en"), ("de", "pt"),
    ("en;q=0.5,pt;q=0.9", "pt"), ("en;q=0", "pt"), ("*", "pt"),
])
def test_idioma_do_cabecalho(cabecalho, esperado):
    assert idioma.do_cabecalho(cabecalho) == esperado


def test_portugues_e_o_padrao_e_o_ingles_vale_so_dentro_do_with():
    assert idioma.atual() == "pt" and idioma.tr("sim", "yes") == "sim"
    with idioma.usando("en"):
        assert idioma.tr("sim", "yes") == "yes"
        assert idioma.t(calc.AVISO_PADRAO) == EN[calc.AVISO_PADRAO]
        assert idioma.t("texto sem traducao") == "texto sem traducao"
    assert idioma.t(calc.AVISO_PADRAO) == calc.AVISO_PADRAO
    with idioma.usando("fr"):  # lingua desconhecida: portugues
        assert idioma.atual() == "pt"


def test_numeros_e_unidades_em_ingles():
    with idioma.usando("en"):
        assert idioma.numero(1234.5) == "1,234.5"
        assert idioma.medida("7.500 BTU/h") == "7,500 BTU/h"
        assert idioma.medida("1,5 cv") == "1.5 hp"
        assert idioma.medida("Ex.: 0,25") == "E.g.: 0.25"
        assert idioma.medida("24 polegadas") == "24 inches"
        assert idioma.unidades("43 pol") == "43 in"
        assert idioma.unidades("0.5 cv") == "0.5 hp"  # o detalhe do catalogo ja usa ponto decimal
        assert idioma.unidades("9 W, 806 lm") == "9 W, 806 lm"
    assert idioma.numero(1234.5) == "1.234,5"
    assert idioma.medida("1,5 cv") == "1,5 cv"


# Todo texto fixo tem traducao -------------------------------------------------------------------

def _portateis():
    with open(RAIZ / "datasets" / "processed" / "eletroportateis.csv", encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


def textos_fixos():
    """Textos fixos que a API pode mostrar e que passam por idioma.t()."""
    textos = {regra["texto"] for regra in calc.EQUIVALENCIA.values()}
    for config in calc.ESTIMAVEIS.values():
        textos.add(config["nome"])
        if config.get("medida"):
            textos.add(config["medida"])
        for forma in config.get("formas", []):
            textos.update(forma[c] for c in ("nome", "rotulo", "unidade", "onde", "dica") if forma[c])
    textos.discard("W")  # unidade igual nas duas linguas
    for nome, descricao in calc.NOMES_DOS_TIPOS.values():
        textos.update((nome, descricao))
    textos.update(calc.NOMES_DOS_TIPOS)  # tipos do Inmetro da maquina de lavar e do ar
    textos.update(calc.SEM_SUGESTAO.values())
    textos.update([calc.AVISO_EQUIVALENTES, calc.AVISO_CONVERTIDO, calc.AVISO_PADRAO, calc.AVISO_TARIFA_USUARIO,
                   "Ainda não sugerimos trocas para este tipo de aparelho."])
    textos.update([estimativa.AVISO_APROXIMADO, estimativa.AVISO_ETIQUETA, estimativa.AVISO_POTENCIA_TIPICA])
    for info in estimativa.TIPOS.values():
        textos.update((info["nome"], info["tipo_inmetro"]))
    textos.update(estimativa.RETAS_2006)
    textos.update([ml_pipeline.AVISO_ML, rag_agent.AVISO_ECO, rag_agent.AVISO_DICAS])
    textos.update(rag_agent.NOMES.values())
    for linha in _portateis():
        textos.add(linha["nome"])
        if linha["categoria"] not in rag_agent.NOMES:  # nome que o Eco-Coach monta pela categoria
            textos.add(linha["categoria"].replace("_", " "))
    textos.add("ANEEL – tarifas homologadas, B1 residencial")
    return textos


def test_todo_texto_fixo_tem_traducao():
    faltando = sorted(textos_fixos() - set(EN))
    assert not faltando, f"sem traducao em src/traducoes.py: {faltando}"


def test_traducoes_sem_texto_que_nao_existe_mais():
    sobrando = sorted(set(EN) - textos_fixos())
    assert not sobrando, f"chaves de src/traducoes.py que nao aparecem no codigo: {sobrando}"


def test_fonte_da_tarifa_traduzida_existe_no_codigo():
    assert "ANEEL – tarifas homologadas, B1 residencial" in (RAIZ / "src" / "tarifas_aneel.py").read_text("utf-8")


# Regras de calculo em ingles --------------------------------------------------------------------

def test_metodo_e_avisos_do_calculo_em_ingles():
    chuveiro = aparelho("chuveiro", potencia_w=5500)
    with idioma.usando("en"):
        consumo = calc.consumo_mensal_kwh(chuveiro, horas_dia=0.25)
        r = calc.montar_resultado(chuveiro, consumo, 0.768, "COPEL-DIS", "ANEEL", "PR")
    assert consumo["kwh_mes"] == pytest.approx(41.25)  # o numero nao depende do idioma
    assert consumo["metodo"] == "5500 W x 15 min/day x 30 days (entered)"
    assert r["avisos"] == [EN[calc.AVISO_PADRAO]]
    assert calc.consumo_mensal_kwh(chuveiro, horas_dia=0.25)["metodo"] == "5500 W x 15 min/dia x 30 dias (informado)"


def test_ventilador_em_ingles():
    ventilador = aparelho("ventilador_de_mesa", kwh_mes_media=3.0)
    with idioma.usando("en"):
        metodo = calc.consumo_mensal_kwh(ventilador, horas_dia=8, velocidade="media")["metodo"]
    assert metodo == "Inmetro consumption at medium speed (3 kWh/month for 1 h/day) adjusted to 8 h/day (entered)"


def test_erro_de_entrada_em_ingles():
    with idioma.usando("en"), pytest.raises(ValueError, match="enter how many hours per day"):
        calc.consumo_mensal_kwh(aparelho("chuveiro", potencia_w=5500))


def test_geladeira_estimada_em_ingles():
    with idioma.usando("en"):
        r = estimativa.consumo_refrigerador_estimado("duplex", True, 407, 2014, volume_congelador_l=90,
                                                     kwh_etiqueta=52.5, ano_referencia=2026)
    assert r["nome"] == "Two-door fridge"
    assert r["detalhe"] == "two-door fridge frost-free, 407 L, bought in 2014"
    assert r["avisos"] == [EN[estimativa.AVISO_ETIQUETA]]
    assert r["metodo"].startswith("label 52.5 kWh/month (old method)")


def test_prompt_do_eco_coach_pede_ingles_com_numeros_americanos():
    fontes = [{"orgao": "Cemig", "documento": "Cartilha", "secao": "Chuveiro", "texto": "Use a posição verão."}]
    chuveiro = {"categoria": "chuveiro", "nome": "Chuveiro", "kwh_mes": 1234.5, "custo_mes": 948.1}
    pt = rag_agent.montar_prompt_dicas(chuveiro, fontes)
    with idioma.usando("en"):
        en = rag_agent.montar_prompt_dicas(chuveiro, fontes)
    assert "IDIOMA DA RESPOSTA" not in pt and "1.234,50 kWh/mês" in pt and "R$ 948,10/mês" in pt
    assert "IDIOMA DA RESPOSTA" in en and "1,234.50 kWh/month" in en and "R$ 948.10/month" in en
    assert "/mês" not in en  # o LLM copia a unidade dos dados
    assert "Use a posição verão." in en  # as fontes continuam em portugues: o LLM traduz


# API ---------------------------------------------------------------------------------------------

def test_api_responde_no_idioma_do_cabecalho(client):
    corpo = {"moradores": 2, "itens": [{"categoria": "chuveiro", "kwh_mes": 80}]}
    en = client.post("/classificar", json=corpo, headers={"Accept-Language": "en-US,en;q=0.9"})
    pt = client.post("/classificar", json=corpo)
    assert en.status_code == pt.status_code == 200
    assert "median per resident" in en.json()["comparacao_media"]["texto"]
    assert en.json()["aviso"] == EN[ml_pipeline.AVISO_ML]
    assert en.json()["perfil"] == pt.json()["perfil"]  # o perfil e uma chave: o app traduz o nome
    assert "mediana por morador" in pt.json()["comparacao_media"]["texto"]
    assert en.headers["content-language"] == "en" and pt.headers["content-language"] == "pt-BR"
    assert "Accept-Language" in en.headers["vary"]


def test_erro_da_api_em_ingles(client):
    # rota sincrona (roda numa thread): o idioma da requisicao chega ate a regra de negocio
    corpo = {"moradores": 2, "itens": [{"categoria": "chuveiro", "kwh_mes": 0}]}
    en = client.post("/classificar", json=corpo, headers=EM_INGLES)
    assert en.status_code == 422 and en.json()["detail"] == "the total consumption must be greater than zero"
    assert client.post("/classificar", json=corpo).json()["detail"] == "o consumo total precisa ser maior que zero"


def test_erro_em_ingles_continua_404():
    assert main.erro_do_servico(ValueError("appliance 9 does not exist")).status_code == 404
    assert main.erro_do_servico(ValueError("power company 9 has no current tariff")).status_code == 404
    assert main.erro_do_servico(ValueError("enter how many hours per day")).status_code == 422


@pytest.mark.banco
def test_categorias_estimaveis_em_ingles(api):
    categorias = {c["categoria"]: c for c in api.get("/estimativa/categorias", headers=EM_INGLES).json()}
    lavar = categorias["maquina_de_lavar"]
    assert lavar["nome"] == "Washing machine" and lavar["medida"] == "Washing capacity (kg)"
    assert lavar["tipos"][0] == {"valor": "Top Load (automatica)", "nome": "Automatic, top-loading",
                                 "descricao": "Lid on top. It washes, rinses and spins on its own."}
    assert lavar["formas"][0]["unidade"] == "kWh/cycle" and lavar["formas"][0]["exemplo"] == "E.g.: 0.25"
    assert categorias["televisor"]["unidade_medida"] == "inches"
    assert categorias["televisor"]["tamanhos"][0]["nome"] == "24 inches"
    assert categorias["ar_condicionado"]["tamanhos"][0]["nome"] == "7,500 BTU/h"
    assert categorias["bomba"]["tamanhos"][-1]["nome"] == "1.5 hp"


@pytest.mark.banco
def test_calculo_pela_api_em_ingles(api, con):
    chuveiro = banco.consulta(con, "SELECT id FROM aparelhos WHERE categoria = ? ORDER BY id LIMIT 1", ("chuveiro",))
    corpo = {"registrar": False, "aparelho_id": int(chuveiro.iloc[0]["id"]), "tarifa_manual": 0.8, "horas_dia": 0.25}
    en = api.post("/calcular", json=corpo, headers=EM_INGLES).json()
    pt = api.post("/calcular", json=corpo).json()
    assert en["custo_mes"] == pt["custo_mes"]
    assert "days (entered)" in en["metodo"] and "dias (informado)" in pt["metodo"]
    assert en["origem_tarifa"] == "entered by the user (electricity bill)"
    assert en["avisos"][0] == EN[calc.AVISO_TARIFA_USUARIO]


@pytest.mark.banco
def test_eletroportateis_em_ingles(api):
    nomes = [p["nome"] for p in api.get("/resistivos", headers=EM_INGLES).json()]
    assert "Hair dryer" in nomes and nomes == sorted(nomes, key=str.lower)
    assert not any(re.search(r"[áéíóúãõç]", n) for n in nomes)
