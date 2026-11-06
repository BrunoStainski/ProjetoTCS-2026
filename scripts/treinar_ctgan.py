"""
Treina o CTGAN com a seed de residencias e gera residencias sinteticas (Dupla 2 - ML).

O CTGAN aprende so as colunas "base": UF, moradores, comodos, se a casa TEM cada aparelho
opcional (tem_*) e o kWh de cada aparelho. Dois cuidados para o CTGAN nao distorcer a seed:
  - tem_* separa "ter o aparelho" de "quanto ele gasta" (colunas com muitos zeros confundem
    o CTGAN); depois de gerar, o kWh e zerado quando tem_* = False.
  - o chuveiro entra POR MORADOR (kwh_chuveiro_por_morador) e e multiplicado de volta, para
    nao perder a relacao "mais gente = mais banho".
Total, custo, kWh/morador e fracoes sao RECALCULADOS depois, para a soma das partes sempre
bater com o total. A distribuidora e a tarifa sao sorteadas entre as reais da UF gerada
(tarifa nao e inventada pelo modelo). perfil_regra fica de fora (seria vazamento).

Uso (na raiz do projeto, com o .venv ativo; antes: python scripts/gerar_seed.py):
  python scripts/treinar_ctgan.py                 # 500 epocas, 5000 residencias
  python scripts/treinar_ctgan.py 300 10000       # epocas, quantidade
Saidas: models/ctgan.pkl, datasets/processed/residencias_sinteticas.csv
"""

import sys
from pathlib import Path

import numpy as np
import pandas as pd
from sdv.evaluation import evaluate_quality  # SDV 2.x (no 1.x era sdv.evaluation.single_table)
from sdv.metadata import Metadata
from sdv.single_table import CTGANSynthesizer

import gerar_seed  # mesma pasta: reaproveita as tarifas reais por UF e os caminhos

RAIZ = Path(__file__).resolve().parents[1]
SEED_CSV = gerar_seed.SAIDA
SAIDA_CSV = gerar_seed.config.DADOS / "residencias_sinteticas.csv"
MODELO = RAIZ / "models" / "ctgan.pkl"
SEMENTE = 42
TABELA = "residencias"

COLUNAS_KWH = ["kwh_refrigerador", "kwh_chuveiro", "kwh_ar_condicionado", "kwh_televisor",
               "kwh_iluminacao", "kwh_maquina_de_lavar", "kwh_microondas", "kwh_ventilador"]
# aparelho opcional: coluna tem_* -> coluna de kWh
OPCIONAIS = {"tem_chuveiro": "kwh_chuveiro", "tem_ar": "kwh_ar_condicionado",
             "tem_maquina": "kwh_maquina_de_lavar", "tem_microondas": "kwh_microondas",
             "tem_ventilador": "kwh_ventilador"}
COLUNAS_TREINO_KWH = ["kwh_chuveiro_por_morador" if c == "kwh_chuveiro" else c for c in COLUNAS_KWH]
COLUNAS_BASE = ["uf", "moradores", "comodos"] + list(OPCIONAIS) + COLUNAS_TREINO_KWH


def preparar_treino(seed):
    seed = seed.copy()
    seed["kwh_chuveiro_por_morador"] = (seed["kwh_chuveiro"] / seed["moradores"]).round(3)
    return seed[COLUNAS_BASE]


def montar_metadata(df):
    # SDV 2.x: fit/sample/metadata trabalham com {nome_tabela: DataFrame}
    meta = Metadata.detect_from_dataframes({TABELA: df})
    # moradores (1 a 6) como categoria: como numero o CTGAN concentrava quase tudo em 2
    for coluna in ["uf", "moradores"]:
        meta.update_column(coluna, sdtype="categorical", table_name=TABELA)
    for coluna in ["comodos"] + COLUNAS_TREINO_KWH:
        meta.update_column(coluna, sdtype="numerical", table_name=TABELA)
    for coluna in OPCIONAIS:
        meta.update_column(coluna, sdtype="boolean", table_name=TABELA)
    return meta


def completar(sint, rng):
    """Limpa o que o CTGAN gerou e recalcula as colunas derivadas com tarifas reais."""
    sint = sint.copy()
    sint["moradores"] = sint["moradores"].clip(1, 6).astype(int)
    sint["comodos"] = sint["comodos"].clip(2, 10).astype(int)
    sint["kwh_chuveiro"] = sint.pop("kwh_chuveiro_por_morador") * sint["moradores"]
    sint[COLUNAS_KWH] = sint[COLUNAS_KWH].clip(lower=0)
    for tem, coluna in OPCIONAIS.items():
        sint[tem] = sint[tem].astype(bool)
        sint.loc[~sint[tem], coluna] = 0.0
    sint["kwh_refrigerador"] = sint["kwh_refrigerador"].clip(lower=5)  # toda casa tem geladeira
    sint[COLUNAS_KWH] = sint[COLUNAS_KWH].round(2)

    tarifas = pd.DataFrame(gerar_seed.preparar_tarifas())
    por_uf = {uf: g.to_dict("records") for uf, g in tarifas.groupby("uf")}
    escolhidas = [por_uf[uf][rng.integers(len(por_uf[uf]))] for uf in sint["uf"]]
    sint["distribuidora"] = [d["nome"] for d in escolhidas]
    sint["tarifa_kwh"] = [d["tarifa_kwh"] for d in escolhidas]

    total = sint[COLUNAS_KWH].sum(axis=1)
    sint["kwh_total"] = total.round(2)
    sint["custo_mes"] = (total * sint["tarifa_kwh"]).round(2)
    sint["kwh_por_morador"] = (total / sint["moradores"]).round(2)
    sint["frac_chuveiro"] = (sint["kwh_chuveiro"] / total).round(4)
    sint["frac_ar"] = (sint["kwh_ar_condicionado"] / total).round(4)
    sint["frac_refrigerador"] = (sint["kwh_refrigerador"] / total).round(4)
    sint.insert(0, "id_residencia", range(1, len(sint) + 1))
    sint["origem"] = "sintetica (CTGAN treinado na seed por regras)"
    return sint


def validar(seed, sint):
    """Compara seed x sintetica (usar na EDA e na parte de limitacoes)."""
    q = [0.1, 0.25, 0.5, 0.75, 0.9, 0.99]
    print("\nkWh por morador - quantis (seed x sintetica):")
    print(pd.DataFrame({"seed": seed["kwh_por_morador"].quantile(q),
                        "sintetica": sint["kwh_por_morador"].quantile(q)}).round(1))
    print("\nkWh total da casa - mediana: "
          f"seed {seed['kwh_total'].median():.1f} | sintetica {sint['kwh_total'].median():.1f}")
    print("\nCasas que tem cada aparelho opcional:")
    print(pd.DataFrame({"seed": seed[list(OPCIONAIS)].mean(),
                        "sintetica": sint[list(OPCIONAIS)].mean()}).round(3))
    print("\nMoradores (proporcao):")
    print(pd.DataFrame({"seed": seed["moradores"].value_counts(normalize=True),
                        "sintetica": sint["moradores"].value_counts(normalize=True)}).sort_index().round(3))
    print("\nCorrelacao moradores x kWh do chuveiro: "
          f"seed {seed['moradores'].corr(seed['kwh_chuveiro']):.2f} | "
          f"sintetica {sint['moradores'].corr(sint['kwh_chuveiro']):.2f}")


def main():
    epocas = int(sys.argv[1]) if len(sys.argv) > 1 else 500
    quantidade = int(sys.argv[2]) if len(sys.argv) > 2 else 5000
    if not SEED_CSV.exists():
        sys.exit(f"Seed nao encontrada em {SEED_CSV}. Rode antes: python scripts/gerar_seed.py")

    seed_completa = pd.read_csv(SEED_CSV, encoding="utf-8-sig")
    seed = preparar_treino(seed_completa)
    meta = montar_metadata(seed)

    print(f"Treinando CTGAN com {len(seed)} residencias, {epocas} epocas (pode demorar alguns minutos)...")
    modelo = CTGANSynthesizer(meta, epochs=epocas, enforce_min_max_values=True, verbose=True)
    modelo.fit({TABELA: seed})
    MODELO.parent.mkdir(exist_ok=True)
    modelo.save(str(MODELO))
    print(f"Modelo salvo em {MODELO}")

    sint = modelo.sample(num_rows=quantidade)
    if isinstance(sint, dict):
        sint = sint[TABELA]
    print("\nQualidade (o quanto as sinteticas se parecem com a seed, 0 a 100%):")
    evaluate_quality({TABELA: seed}, {TABELA: sint[COLUNAS_BASE]}, meta)

    sint = completar(sint, np.random.default_rng(SEMENTE))
    sint.to_csv(SAIDA_CSV, index=False, encoding="utf-8-sig")
    print(f"\n{len(sint)} residencias sinteticas salvas em {SAIDA_CSV}")
    validar(seed_completa, sint)


if __name__ == "__main__":
    main()
