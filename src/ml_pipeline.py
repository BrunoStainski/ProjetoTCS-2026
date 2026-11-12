"""
Classificacao do perfil de consumo de uma residencia (Consciente / Moderado / Ineficiente).

Usa o models/kmeans.pkl gerado por scripts/treinar_kmeans.py. O arquivo guarda so numeros,
entao aqui basta o numpy (nao precisa de scikit-learn na API).

ATENCAO: o modelo foi treinado com residencias SINTETICAS (seed por regras + CTGAN).
O perfil serve para demonstracao, nao e uma avaliacao oficial do consumo.

Exemplo:
  classificar_residencia({
      "moradores": 3,
      "itens": [{"categoria": "chuveiro", "kwh_mes": 82.5},
                {"categoria": "refrigerador", "kwh_mes": 30},
                {"categoria": "televisor", "kwh_mes": 9}],
  })
Os itens podem ser os proprios resultados de servico.calcular (tem categoria e kwh_mes).
"""

import pickle
from functools import lru_cache
from pathlib import Path

import numpy as np

from idioma import t, tr

MODEL = Path(__file__).resolve().parents[1] / "models" / "kmeans.pkl"
ML_NOTICE = ("Perfil estimado por um modelo treinado com residencias sinteticas; "
            "serve como referencia, nao como avaliacao oficial.")


@lru_cache(maxsize=1)
def load_model(path=MODEL):
    if not Path(path).exists():
        raise FileNotFoundError(f"{path} nao existe. Rode: python scripts/treinar_kmeans.py")
    with open(path, "rb") as f:
        return pickle.load(f)


def residence_variables(inventory):
    """Inventario -> kwh_total e as variaveis por morador usadas pelo K-Means."""
    residents = inventory.get("moradores")
    if not isinstance(residents, (int, float)) or residents < 1:
        raise ValueError(tr("informe quantos moradores (1 ou mais)", "enter how many residents (1 or more)"))
    items = inventory.get("itens") or []
    if not items:
        raise ValueError(tr("informe pelo menos um aparelho com categoria e kwh_mes",
                            "enter at least one appliance with categoria and kwh_mes"))

    by_category = {}
    for item in items:
        kwh = float(item["kwh_mes"])
        if kwh < 0:
            raise ValueError(tr("kwh_mes nao pode ser negativo", "kwh_mes cannot be negative"))
        by_category[item["categoria"]] = by_category.get(item["categoria"], 0.0) + kwh
    total = sum(by_category.values())
    if total <= 0:
        raise ValueError(tr("o consumo total precisa ser maior que zero", "the total consumption must be greater than zero"))

    return total, {
        "kwh_por_morador": total / residents,
        "frac_chuveiro": by_category.get("chuveiro", 0.0) / total,
        "frac_ar": by_category.get("ar_condicionado", 0.0) / total,
        "frac_refrigerador": by_category.get("refrigerador", 0.0) / total,
    }


def variables_profile(variables, model=None):
    """Grupo do centroide mais proximo (mesma conta do KMeans.predict)."""
    model = model or load_model()
    x = np.array([np.log1p(variables[v]) if v in model["log"] else variables[v]
                  for v in model["variaveis"]], dtype=float)
    xz = (x - np.array(model["media"])) / np.array(model["escala"]) * np.array(model["pesos"])
    distances = np.linalg.norm(np.array(model["centroides"]) - xz, axis=1)
    return model["nome_do_grupo"][int(distances.argmin())]


def classify_residence(inventory):
    """{moradores, itens:[{categoria, kwh_mes}]} -> {perfil, kwh_por_morador, comparacao_media}"""
    model = load_model()
    total, variables = residence_variables(inventory)
    mean = model["mediana_kwh_por_morador"]  # mediana: a media e puxada pelas casas extremas
    difference = (variables["kwh_por_morador"] - mean) / mean * 100
    return {
        "perfil": variables_profile(variables, model),
        "kwh_total": round(total, 2),
        "kwh_por_morador": round(variables["kwh_por_morador"], 2),
        "comparacao_media": {
            "mediana_kwh_por_morador": round(mean, 2),
            "diferenca_percentual": round(difference, 1),
            "texto": tr(f"{abs(difference):.0f}% {'acima' if difference > 0 else 'abaixo'} da mediana por morador "
                        "(residencias sinteticas)",
                        f"{abs(difference):.0f}% {'above' if difference > 0 else 'below'} the median per resident "
                        "(synthetic homes)"),
        },
        "fracoes": {k: round(v, 3) for k, v in variables.items() if k.startswith("frac_")},
        "aviso": t(ML_NOTICE),
        "fonte": model["fonte"],
    }
