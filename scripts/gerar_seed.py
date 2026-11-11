"""
Gera a seed de residencias para o CTGAN (Dupla 2 - Machine Learning).

Cada linha e uma residencia montada por REGRAS, usando aparelhos reais do catalogo do
Inmetro e tarifas reais da ANEEL. O consumo de cada aparelho sai da mesma funcao que o app
usa (calculadora_residencial.consumo_mensal_kwh), entao a seed segue as regras do projeto.

ATENCAO (etica/limitacoes): as probabilidades e faixas de uso abaixo (PERFIS) sao premissas
do grupo, sem fonte oficial. As residencias sao sinteticas e servem para demonstracao.

Uso (na raiz do projeto, com o .venv ativo):
  python scripts/gerar_seed.py            # 3000 residencias
  python scripts/gerar_seed.py 500        # outra quantidade
Saida: datasets/processed/seed_residencias.csv
"""

import sys
from datetime import date
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
import calculadora_residencial as calc  # noqa: E402
import config  # noqa: E402
import tarifas_aneel  # noqa: E402

SEED = 42
OUTPUT = config.DATA / "seed_residencias.csv"

# Perfis de comportamento (premissas do grupo). Cada faixa (min, max) e sorteada uniforme.
# "faixa_modelo" = parte do catalogo (ordenado do mais economico ao mais gastao) de onde
# o aparelho e sorteado: o economico tende a ter aparelhos mais eficientes.
PROFILES = {
    "economico": {
        "peso": 0.30, "faixa_modelo": (0.0, 0.5),
        "min_banho": (4, 8), "p_ar": 0.10, "h_ar": (1, 3), "h_tv": (2, 4),
        "h_luz": (3, 4), "ciclos_pessoa": (2, 3), "p_2a_geladeira": 0.02,
        "p_fluorescente": 0.05, "velocidade": ["baixa", "media"],
    },
    "moderado": {
        "peso": 0.45, "faixa_modelo": (0.25, 0.75),
        "min_banho": (8, 12), "p_ar": 0.25, "h_ar": (3, 6), "h_tv": (4, 6),
        "h_luz": (4, 6), "ciclos_pessoa": (3, 4), "p_2a_geladeira": 0.10,
        "p_fluorescente": 0.20, "velocidade": ["media"],
    },
    "ineficiente": {
        "peso": 0.25, "faixa_modelo": (0.5, 1.0),
        "min_banho": (12, 20), "p_ar": 0.45, "h_ar": (6, 10), "h_tv": (6, 10),
        "h_luz": (6, 8), "ciclos_pessoa": (4, 6), "p_2a_geladeira": 0.30,
        "p_fluorescente": 0.50, "velocidade": ["media", "alta"],
    },
}
P_ELECTRIC_SHOWER = 0.90   # o resto usa gas/solar (fora do escopo)
P_MACHINE, P_MICROWAVE, P_FAN = 0.85, 0.75, 0.70
# Ar-condicionado residencial: o catalogo vai ate ~8 kW (aparelhos quase comerciais), que
# geravam casas com mais de 1.500 kWh/mes por morador. Limite de 3.500 W (~24.000 BTU/h).
MAX_AC_POWER_W = 3500
# A potencia do Inmetro e a 35 C em carga total; o compressor nao fica ligado o tempo todo.
# Fracao media do tempo ligado (premissa do grupo, sem fonte).
COMPRESSOR_FACTOR = 0.6

rng = np.random.default_rng(SEED)


def range_text(interval):
    return float(rng.uniform(*interval))


def prepare_catalog():
    """Catalogo por categoria, ordenado pelo dado de consumo (mais economico primeiro)."""
    cat = calc.load_catalog()
    ar = cat["categoria"] == "ar_condicionado"
    cat = cat[~ar | (cat["potencia_w"] <= MAX_AC_POWER_W)]
    cat["ordem"] = cat["kwh_mes"].fillna(cat["kwh_ciclo"]).fillna(cat["potencia_w"])
    return {c: g.sort_values("ordem").to_dict("records") for c, g in cat.groupby("categoria")}


def prepare_tariffs():
    """Tarifa vigente hoje de cada distribuidora, com a UF (distribuidoras_uf.csv)."""
    t = tarifas_aneel.read_residential_tariffs()
    today = date.today().isoformat()
    t = t[t["vigencia_inicio"].fillna("") <= today].sort_values("vigencia_inicio")
    t = t.drop_duplicates("nome", keep="last")
    uf = pd.read_csv(config.DISTRIBUTORS_CSV, encoding="utf-8-sig")[["SigAgente", "uf"]]
    t = t.merge(uf, left_on="nome", right_on="SigAgente", how="inner")
    return t[["nome", "uf", "tarifa_kwh"]].to_dict("records")


def draw_model(catalog, category, profile):
    items = catalog[category]
    ini, end = PROFILES[profile]["faixa_modelo"]
    a, b = int(ini * len(items)), max(int(end * len(items)), int(ini * len(items)) + 1)
    return items[rng.integers(a, b)]


def kwh(appliance, **usage):
    return calc.monthly_consumption_kwh(appliance, **usage)["kwh_mes"]


def generate_residence(i, catalog, tariffs):
    profile = rng.choice(list(PROFILES), p=[p["peso"] for p in PROFILES.values()])
    p = PROFILES[profile]
    dist = tariffs[rng.integers(len(tariffs))]
    residents = int(rng.choice([1, 2, 3, 4, 5, 6], p=[0.15, 0.25, 0.25, 0.20, 0.10, 0.05]))
    rooms = int(np.clip(residents + rng.integers(1, 4), 2, 10))
    c = {}

    # geladeira (toda casa tem uma; algumas tem a segunda)
    c["refrigerador"] = kwh(draw_model(catalog, "refrigerador", profile))
    if rng.random() < p["p_2a_geladeira"]:
        c["refrigerador"] += kwh(draw_model(catalog, "refrigerador", profile))

    # chuveiro: minutos por banho x moradores (1 banho por pessoa por dia)
    c["chuveiro"] = 0.0
    has = {k: bool(rng.random() < prob) for k, prob in [
        ("chuveiro", P_ELECTRIC_SHOWER), ("ar", p["p_ar"]), ("maquina", P_MACHINE),
        ("microondas", P_MICROWAVE), ("ventilador", P_FAN)]}
    if has["chuveiro"]:
        hours = residents * range_text(p["min_banho"]) / 60
        c["chuveiro"] = kwh(draw_model(catalog, "chuveiro", profile), daily_hours=min(hours, 24))

    # ar-condicionado: potencia a 35 C x horas (conta do app) x fracao do tempo com compressor ligado
    c["ar_condicionado"] = 0.0
    if has["ar"]:
        c["ar_condicionado"] = COMPRESSOR_FACTOR * kwh(draw_model(catalog, "ar_condicionado", profile),
                                                      daily_hours=range_text(p["h_ar"]))

    # TVs (kWh/mes fixo do Inmetro; o app ainda nao ajusta pelas horas)
    n_tv = int(np.clip(rng.poisson(1 + residents / 3), 1, 4))
    c["televisor"] = sum(kwh(draw_model(catalog, "televisor", profile)) for _ in range(n_tv))

    # iluminacao: ~1,5 lampada por comodo, parte fluorescente nos perfis menos eficientes
    c["iluminacao"] = 0.0
    light_hours = range_text(p["h_luz"])
    for _ in range(int(round(rooms * 1.5))):
        kind = "lampada_fluorescente" if rng.random() < p["p_fluorescente"] else "lampada_led"
        c["iluminacao"] += kwh(draw_model(catalog, kind, profile), daily_hours=light_hours)

    c["maquina_de_lavar"] = 0.0
    if has["maquina"]:
        cycles = round(residents * range_text(p["ciclos_pessoa"]))
        c["maquina_de_lavar"] = kwh(draw_model(catalog, "maquina_de_lavar", profile), monthly_cycles=cycles)

    c["microondas"] = 0.0
    if has["microondas"]:
        c["microondas"] = kwh(draw_model(catalog, "microondas", profile), daily_hours=range_text((0.1, 0.5)))

    c["ventilador"] = 0.0
    if has["ventilador"]:
        for _ in range(int(rng.integers(1, 3))):
            category = "ventilador_de_teto" if rng.random() < 0.4 else "ventilador_de_mesa"
            c["ventilador"] += kwh(draw_model(catalog, category, profile),
                                   speed=str(rng.choice(p["velocidade"])))

    total = sum(c.values())
    line = {
        "id_residencia": i, "uf": dist["uf"], "distribuidora": dist["nome"],
        "tarifa_kwh": dist["tarifa_kwh"], "moradores": residents, "comodos": rooms,
        **{f"tem_{k}": v for k, v in has.items()},
        **{f"kwh_{k}": round(v, 2) for k, v in c.items()},
        "kwh_total": round(total, 2),
        "custo_mes": round(total * dist["tarifa_kwh"], 2),
        "kwh_por_morador": round(total / residents, 2),
        "frac_chuveiro": round(c["chuveiro"] / total, 4),
        "frac_ar": round(c["ar_condicionado"] / total, 4),
        "frac_refrigerador": round(c["refrigerador"] / total, 4),
        # perfil usado na geracao: NAO usar para treinar o CTGAN/K-Means (vazamento);
        # serve so para conferir se os grupos do K-Means fazem sentido.
        "perfil_regra": profile,
    }
    return line


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 3000
    catalog, tariffs = prepare_catalog(), prepare_tariffs()
    print(f"Catalogo: {sum(map(len, catalog.values()))} aparelhos | distribuidoras com UF: {len(tariffs)}")
    seed = pd.DataFrame([generate_residence(i, catalog, tariffs) for i in range(1, n + 1)])
    seed.to_csv(OUTPUT, index=False, encoding="utf-8-sig")
    print(f"{len(seed)} residencias salvas em {OUTPUT}\n")
    print(seed.groupby("perfil_regra")[["kwh_total", "kwh_por_morador", "custo_mes"]].median().round(1))


if __name__ == "__main__":
    main()
