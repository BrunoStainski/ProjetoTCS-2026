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

MODELO = Path(__file__).resolve().parents[1] / "models" / "kmeans.pkl"
AVISO_ML = ("Perfil estimado por um modelo treinado com residencias sinteticas; "
            "serve como referencia, nao como avaliacao oficial.")


@lru_cache(maxsize=1)
def carregar_modelo(caminho=MODELO):
    if not Path(caminho).exists():
        raise FileNotFoundError(f"{caminho} nao existe. Rode: python scripts/treinar_kmeans.py")
    with open(caminho, "rb") as f:
        return pickle.load(f)


def variaveis_da_residencia(inventario):
    """Inventario -> kwh_total e as variaveis por morador usadas pelo K-Means."""
    moradores = inventario.get("moradores")
    if not isinstance(moradores, (int, float)) or moradores < 1:
        raise ValueError("informe quantos moradores (1 ou mais)")
    itens = inventario.get("itens") or []
    if not itens:
        raise ValueError("informe pelo menos um aparelho com categoria e kwh_mes")

    por_categoria = {}
    for item in itens:
        kwh = float(item["kwh_mes"])
        if kwh < 0:
            raise ValueError("kwh_mes nao pode ser negativo")
        por_categoria[item["categoria"]] = por_categoria.get(item["categoria"], 0.0) + kwh
    total = sum(por_categoria.values())
    if total <= 0:
        raise ValueError("o consumo total precisa ser maior que zero")

    return total, {
        "kwh_por_morador": total / moradores,
        "frac_chuveiro": por_categoria.get("chuveiro", 0.0) / total,
        "frac_ar": por_categoria.get("ar_condicionado", 0.0) / total,
        "frac_refrigerador": por_categoria.get("refrigerador", 0.0) / total,
    }


def perfil_das_variaveis(variaveis, modelo=None):
    """Grupo do centroide mais proximo (mesma conta do KMeans.predict)."""
    modelo = modelo or carregar_modelo()
    x = np.array([np.log1p(variaveis[v]) if v in modelo["log"] else variaveis[v]
                  for v in modelo["variaveis"]], dtype=float)
    xz = (x - np.array(modelo["media"])) / np.array(modelo["escala"]) * np.array(modelo["pesos"])
    distancias = np.linalg.norm(np.array(modelo["centroides"]) - xz, axis=1)
    return modelo["nome_do_grupo"][int(distancias.argmin())]


def classificar_residencia(inventario):
    """{moradores, itens:[{categoria, kwh_mes}]} -> {perfil, kwh_por_morador, comparacao_media}"""
    modelo = carregar_modelo()
    total, variaveis = variaveis_da_residencia(inventario)
    media = modelo["mediana_kwh_por_morador"]  # mediana: a media e puxada pelas casas extremas
    diferenca = (variaveis["kwh_por_morador"] - media) / media * 100
    return {
        "perfil": perfil_das_variaveis(variaveis, modelo),
        "kwh_total": round(total, 2),
        "kwh_por_morador": round(variaveis["kwh_por_morador"], 2),
        "comparacao_media": {
            "mediana_kwh_por_morador": round(media, 2),
            "diferenca_percentual": round(diferenca, 1),
            "texto": f"{abs(diferenca):.0f}% {'acima' if diferenca > 0 else 'abaixo'} da mediana por morador (residencias sinteticas)",
        },
        "fracoes": {k: round(v, 3) for k, v in variaveis.items() if k.startswith("frac_")},
        "aviso": AVISO_ML,
        "fonte": modelo["fonte"],
    }
