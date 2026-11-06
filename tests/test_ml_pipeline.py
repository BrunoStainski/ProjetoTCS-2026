"""Classificacao de perfil (ml_pipeline.py + models/kmeans.pkl). Nao precisa de banco."""

import pytest

import ml_pipeline

PERFIS = {"Consciente", "Moderado", "Ineficiente"}


def casa(moradores, **kwh):
    return {"moradores": moradores, "itens": [{"categoria": c, "kwh_mes": v} for c, v in kwh.items()]}


def test_modelo_guarda_so_numeros():
    """A API nao tem scikit-learn: o pkl precisa abrir so com a biblioteca padrao + numpy."""
    modelo = ml_pipeline.carregar_modelo()
    assert set(modelo["nome_do_grupo"].values()) == PERFIS
    assert len(modelo["centroides"]) == 3
    assert all(isinstance(v, float) for v in modelo["media"])


def test_resposta_completa_e_contas_certas():
    r = ml_pipeline.classificar_residencia(casa(3, chuveiro=82.5, refrigerador=30, televisor=9))
    assert r["perfil"] in PERFIS
    assert r["kwh_total"] == pytest.approx(121.5)
    assert r["kwh_por_morador"] == pytest.approx(40.5)
    assert r["fracoes"]["frac_chuveiro"] == pytest.approx(82.5 / 121.5, abs=1e-3)
    assert r["fracoes"]["frac_ar"] == 0
    assert "sinteticas" in r["aviso"]


def test_itens_da_mesma_categoria_sao_somados():
    r = ml_pipeline.classificar_residencia(
        {"moradores": 2, "itens": [{"categoria": "televisor", "kwh_mes": 10},
                                   {"categoria": "televisor", "kwh_mes": 5},
                                   {"categoria": "refrigerador", "kwh_mes": 25}]})
    assert r["kwh_total"] == pytest.approx(40)


def test_extremos_caem_nos_perfis_esperados():
    economica = ml_pipeline.classificar_residencia(casa(4, refrigerador=25, lampada_led=8, televisor=8))
    gastona = ml_pipeline.classificar_residencia(casa(1, ar_condicionado=400, chuveiro=120, refrigerador=60))
    assert economica["perfil"] == "Consciente"
    assert gastona["perfil"] == "Ineficiente"
    assert economica["comparacao_media"]["diferenca_percentual"] < 0
    assert gastona["comparacao_media"]["diferenca_percentual"] > 0


@pytest.mark.parametrize("inventario, mensagem", [
    ({"moradores": 0, "itens": [{"categoria": "chuveiro", "kwh_mes": 10}]}, "moradores"),
    ({"moradores": 2, "itens": []}, "pelo menos um aparelho"),
    ({"moradores": 2, "itens": [{"categoria": "chuveiro", "kwh_mes": -5}]}, "negativo"),
    ({"moradores": 2, "itens": [{"categoria": "chuveiro", "kwh_mes": 0}]}, "maior que zero"),
])
def test_entradas_invalidas(inventario, mensagem):
    with pytest.raises(ValueError, match=mensagem):
        ml_pipeline.classificar_residencia(inventario)
