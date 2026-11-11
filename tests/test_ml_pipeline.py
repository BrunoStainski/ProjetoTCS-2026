"""Classificacao de perfil (ml_pipeline.py + models/kmeans.pkl). Nao precisa de banco."""

import pytest

import ml_pipeline

PROFILES = {"Consciente", "Moderado", "Ineficiente"}


def home(residents, **kwh):
    return {"moradores": residents, "itens": [{"categoria": c, "kwh_mes": v} for c, v in kwh.items()]}


def test_model_keeps_only_numbers():
    """A API nao tem scikit-learn: o pkl precisa abrir so com a biblioteca padrao + numpy."""
    model = ml_pipeline.load_model()
    assert set(model["nome_do_grupo"].values()) == PROFILES
    assert len(model["centroides"]) == 3
    assert all(isinstance(v, float) for v in model["media"])


def test_complete_response_with_right_totals():
    r = ml_pipeline.classify_residence(home(3, chuveiro=82.5, refrigerador=30, televisor=9))
    assert r["perfil"] in PROFILES
    assert r["kwh_total"] == pytest.approx(121.5)
    assert r["kwh_por_morador"] == pytest.approx(40.5)
    assert r["fracoes"]["frac_chuveiro"] == pytest.approx(82.5 / 121.5, abs=1e-3)
    assert r["fracoes"]["frac_ar"] == 0
    assert "sinteticas" in r["aviso"]


def test_items_of_same_category_are_summed():
    r = ml_pipeline.classify_residence(
        {"moradores": 2, "itens": [{"categoria": "televisor", "kwh_mes": 10},
                                   {"categoria": "televisor", "kwh_mes": 5},
                                   {"categoria": "refrigerador", "kwh_mes": 25}]})
    assert r["kwh_total"] == pytest.approx(40)


def test_extremes_fall_in_expected_profiles():
    economical = ml_pipeline.classify_residence(home(4, refrigerador=25, lampada_led=8, televisor=8))
    heavyUser = ml_pipeline.classify_residence(home(1, ar_condicionado=400, chuveiro=120, refrigerador=60))
    assert economical["perfil"] == "Consciente"
    assert heavyUser["perfil"] == "Ineficiente"
    assert economical["comparacao_media"]["diferenca_percentual"] < 0
    assert heavyUser["comparacao_media"]["diferenca_percentual"] > 0


@pytest.mark.parametrize("inventory, message", [
    ({"moradores": 0, "itens": [{"categoria": "chuveiro", "kwh_mes": 10}]}, "moradores"),
    ({"moradores": 2, "itens": []}, "pelo menos um aparelho"),
    ({"moradores": 2, "itens": [{"categoria": "chuveiro", "kwh_mes": -5}]}, "negativo"),
    ({"moradores": 2, "itens": [{"categoria": "chuveiro", "kwh_mes": 0}]}, "maior que zero"),
])
def test_invalid_inputs(inventory, message):
    with pytest.raises(ValueError, match=message):
        ml_pipeline.classify_residence(inventory)
