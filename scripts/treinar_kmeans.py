"""
Treina o K-Means que agrupa residencias em Consciente / Moderado / Ineficiente (Dupla 2 - ML).

Variaveis (todas "por morador" ou fracao, para casa grande nao virar "ineficiente" so por
ser grande): kwh_por_morador, frac_chuveiro, frac_ar, frac_refrigerador.
Os dados sao padronizados (StandardScaler) e o K-Means usa k=3. O nome de cada grupo vem
da media de kwh_por_morador: menor = Consciente, maior = Ineficiente.

O models/kmeans.pkl guarda SO numeros (medias, escalas, centroides, rotulos), entao
src/ml_pipeline.py classifica sem precisar do scikit-learn instalado na imagem da API.

Uso (na raiz, com o .venv ativo; antes: gerar_seed.py e treinar_ctgan.py):
  python scripts/treinar_kmeans.py
"""

import pickle
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.cluster import KMeans
from sklearn.metrics import silhouette_score
from sklearn.preprocessing import StandardScaler

import gerar_seed

RAIZ = Path(__file__).resolve().parents[1]
SINTETICAS = gerar_seed.config.DADOS / "residencias_sinteticas.csv"
SEED = gerar_seed.SAIDA
MODELO = RAIZ / "models" / "kmeans.pkl"
VARIAVEIS = ["kwh_por_morador", "frac_chuveiro", "frac_ar", "frac_refrigerador"]
NOMES = ["Consciente", "Moderado", "Ineficiente"]
# kwh_por_morador tem cauda longa: entra em log e com peso maior, para o grupo refletir
# o QUANTO a casa gasta; as fracoes so ajudam a explicar ONDE ela gasta.
LOG = ["kwh_por_morador"]
PESOS = {"kwh_por_morador": 2.0, "frac_chuveiro": 0.5, "frac_ar": 0.5, "frac_refrigerador": 0.5}
SEMENTE = 42


def main():
    df = pd.read_csv(SINTETICAS, encoding="utf-8-sig")
    x = df[VARIAVEIS].copy()
    for v in LOG:
        x[v] = np.log1p(x[v])
    escala = StandardScaler().fit(x)
    pesos = np.array([PESOS[v] for v in VARIAVEIS])
    xz = escala.transform(x) * pesos

    print("Silhueta por k (quanto maior, mais separados os grupos; usamos k=3 pelo desenho do app):")
    for k in range(2, 7):
        rotulos = KMeans(n_clusters=k, n_init=10, random_state=SEMENTE).fit_predict(xz)
        print(f"  k={k}: {silhouette_score(xz, rotulos):.3f}")

    km = KMeans(n_clusters=3, n_init=10, random_state=SEMENTE).fit(xz)
    df["grupo"] = km.labels_
    ordem = df.groupby("grupo")["kwh_por_morador"].mean().sort_values().index
    nome_do_grupo = {int(g): NOMES[i] for i, g in enumerate(ordem)}
    df["perfil"] = df["grupo"].map(nome_do_grupo)

    modelo = {
        "variaveis": VARIAVEIS,
        "media": escala.mean_.tolist(),
        "escala": escala.scale_.tolist(),
        "log": LOG,
        "pesos": pesos.tolist(),
        "centroides": km.cluster_centers_.tolist(),
        "nome_do_grupo": nome_do_grupo,
        "mediana_kwh_por_morador": float(df["kwh_por_morador"].median()),
        "media_por_perfil": df.groupby("perfil")[VARIAVEIS].mean().round(4).to_dict("index"),
        "media_por_moradores": df.groupby("moradores")["kwh_total"].mean().round(2).to_dict(),
        "n_residencias": len(df),
        "fonte": f"K-Means (k=3, log e pesos nas variaveis) treinado em {SINTETICAS.name} (residencias sinteticas, CTGAN)",
    }
    MODELO.parent.mkdir(exist_ok=True)
    with open(MODELO, "wb") as f:
        pickle.dump(modelo, f)
    print(f"\nModelo salvo em {MODELO}\n")

    print("Perfis encontrados (medias):")
    resumo = df.groupby("perfil")[VARIAVEIS + ["kwh_total"]].mean().reindex(NOMES).round(3)
    resumo["residencias"] = df["perfil"].value_counts()
    print(resumo)

    # conferencia: o K-Means reencontra os perfis usados para gerar a seed?
    import sys
    sys.path.insert(0, str(RAIZ / "src"))
    import ml_pipeline
    seed = pd.read_csv(SEED, encoding="utf-8-sig")
    seed["perfil"] = [ml_pipeline.perfil_das_variaveis(linha, modelo) for linha in seed[VARIAVEIS].to_dict("records")]
    print("\nConferencia na seed (linhas = perfil usado na geracao, colunas = perfil do K-Means):")
    print(pd.crosstab(seed["perfil_regra"], seed["perfil"]).reindex(columns=NOMES, fill_value=0))


if __name__ == "__main__":
    main()
