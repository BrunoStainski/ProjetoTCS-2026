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

ROOT = Path(__file__).resolve().parents[1]
SYNTHETIC = gerar_seed.config.DATA / "residencias_sinteticas.csv"
SEED = gerar_seed.OUTPUT
MODEL = ROOT / "models" / "kmeans.pkl"
VARIABLES = ["kwh_por_morador", "frac_chuveiro", "frac_ar", "frac_refrigerador"]
NAMES = ["Consciente", "Moderado", "Ineficiente"]
# kwh_por_morador tem cauda longa: entra em log e com peso maior, para o grupo refletir
# o QUANTO a casa gasta; as fracoes so ajudam a explicar ONDE ela gasta.
LOG = ["kwh_por_morador"]
WEIGHTS = {"kwh_por_morador": 2.0, "frac_chuveiro": 0.5, "frac_ar": 0.5, "frac_refrigerador": 0.5}
RANDOM_SEED = 42


def main():
    df = pd.read_csv(SYNTHETIC, encoding="utf-8-sig")
    x = df[VARIABLES].copy()
    for v in LOG:
        x[v] = np.log1p(x[v])
    scaler = StandardScaler().fit(x)
    weights = np.array([WEIGHTS[v] for v in VARIABLES])
    xz = scaler.transform(x) * weights

    print("Silhueta por k (quanto maior, mais separados os grupos; usamos k=3 pelo desenho do app):")
    for k in range(2, 7):
        cluster_labels = KMeans(n_clusters=k, n_init=10, random_state=RANDOM_SEED).fit_predict(xz)
        print(f"  k={k}: {silhouette_score(xz, cluster_labels):.3f}")

    km = KMeans(n_clusters=3, n_init=10, random_state=RANDOM_SEED).fit(xz)
    df["grupo"] = km.labels_
    order = df.groupby("grupo")["kwh_por_morador"].mean().sort_values().index
    group_name = {int(g): NAMES[i] for i, g in enumerate(order)}
    df["perfil"] = df["grupo"].map(group_name)

    model = {
        "variaveis": VARIABLES,
        "media": scaler.mean_.tolist(),
        "escala": scaler.scale_.tolist(),
        "log": LOG,
        "pesos": weights.tolist(),
        "centroides": km.cluster_centers_.tolist(),
        "nome_do_grupo": group_name,
        "mediana_kwh_por_morador": float(df["kwh_por_morador"].median()),
        "media_por_perfil": df.groupby("perfil")[VARIABLES].mean().round(4).to_dict("index"),
        "media_por_moradores": df.groupby("moradores")["kwh_total"].mean().round(2).to_dict(),
        "n_residencias": len(df),
        "fonte": f"K-Means (k=3, log e pesos nas variaveis) treinado em {SYNTHETIC.name} (residencias sinteticas, CTGAN)",
    }
    MODEL.parent.mkdir(exist_ok=True)
    with open(MODEL, "wb") as f:
        pickle.dump(model, f)
    print(f"\nModelo salvo em {MODEL}\n")

    print("Perfis encontrados (medias):")
    summary = df.groupby("perfil")[VARIABLES + ["kwh_total"]].mean().reindex(NAMES).round(3)
    summary["residencias"] = df["perfil"].value_counts()
    print(summary)

    # conferencia: o K-Means reencontra os perfis usados para gerar a seed?
    import sys
    sys.path.insert(0, str(ROOT / "src"))
    import ml_pipeline
    seed = pd.read_csv(SEED, encoding="utf-8-sig")
    seed["perfil"] = [ml_pipeline.variables_profile(line, model) for line in seed[VARIABLES].to_dict("records")]
    print("\nConferencia na seed (linhas = perfil usado na geracao, colunas = perfil do K-Means):")
    print(pd.crosstab(seed["perfil_regra"], seed["perfil"]).reindex(columns=NAMES, fill_value=0))


if __name__ == "__main__":
    main()
