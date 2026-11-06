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

SEMENTE = 42
SAIDA = config.DADOS / "seed_residencias.csv"

# Perfis de comportamento (premissas do grupo). Cada faixa (min, max) e sorteada uniforme.
# "faixa_modelo" = parte do catalogo (ordenado do mais economico ao mais gastao) de onde
# o aparelho e sorteado: o economico tende a ter aparelhos mais eficientes.
PERFIS = {
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
P_CHUVEIRO_ELETRICO = 0.90   # o resto usa gas/solar (fora do escopo)
P_MAQUINA, P_MICROONDAS, P_VENTILADOR = 0.85, 0.75, 0.70
# Ar-condicionado residencial: o catalogo vai ate ~8 kW (aparelhos quase comerciais), que
# geravam casas com mais de 1.500 kWh/mes por morador. Limite de 3.500 W (~24.000 BTU/h).
POTENCIA_MAX_AR_W = 3500
# A potencia do Inmetro e a 35 C em carga total; o compressor nao fica ligado o tempo todo.
# Fracao media do tempo ligado (premissa do grupo, sem fonte).
FATOR_COMPRESSOR = 0.6

rng = np.random.default_rng(SEMENTE)


def faixa(intervalo):
    return float(rng.uniform(*intervalo))


def preparar_catalogo():
    """Catalogo por categoria, ordenado pelo dado de consumo (mais economico primeiro)."""
    cat = calc.carregar_catalogo()
    ar = cat["categoria"] == "ar_condicionado"
    cat = cat[~ar | (cat["potencia_w"] <= POTENCIA_MAX_AR_W)]
    cat["ordem"] = cat["kwh_mes"].fillna(cat["kwh_ciclo"]).fillna(cat["potencia_w"])
    return {c: g.sort_values("ordem").to_dict("records") for c, g in cat.groupby("categoria")}


def preparar_tarifas():
    """Tarifa vigente hoje de cada distribuidora, com a UF (distribuidoras_uf.csv)."""
    t = tarifas_aneel.ler_tarifas_residenciais()
    hoje = date.today().isoformat()
    t = t[t["vigencia_inicio"].fillna("") <= hoje].sort_values("vigencia_inicio")
    t = t.drop_duplicates("nome", keep="last")
    uf = pd.read_csv(config.DISTRIBUIDORAS_CSV, encoding="utf-8-sig")[["SigAgente", "uf"]]
    t = t.merge(uf, left_on="nome", right_on="SigAgente", how="inner")
    return t[["nome", "uf", "tarifa_kwh"]].to_dict("records")


def sortear_modelo(catalogo, categoria, perfil):
    itens = catalogo[categoria]
    ini, fim = PERFIS[perfil]["faixa_modelo"]
    a, b = int(ini * len(itens)), max(int(fim * len(itens)), int(ini * len(itens)) + 1)
    return itens[rng.integers(a, b)]


def kwh(aparelho, **uso):
    return calc.consumo_mensal_kwh(aparelho, **uso)["kwh_mes"]


def gerar_residencia(i, catalogo, tarifas):
    perfil = rng.choice(list(PERFIS), p=[p["peso"] for p in PERFIS.values()])
    p = PERFIS[perfil]
    dist = tarifas[rng.integers(len(tarifas))]
    moradores = int(rng.choice([1, 2, 3, 4, 5, 6], p=[0.15, 0.25, 0.25, 0.20, 0.10, 0.05]))
    comodos = int(np.clip(moradores + rng.integers(1, 4), 2, 10))
    c = {}

    # geladeira (toda casa tem uma; algumas tem a segunda)
    c["refrigerador"] = kwh(sortear_modelo(catalogo, "refrigerador", perfil))
    if rng.random() < p["p_2a_geladeira"]:
        c["refrigerador"] += kwh(sortear_modelo(catalogo, "refrigerador", perfil))

    # chuveiro: minutos por banho x moradores (1 banho por pessoa por dia)
    c["chuveiro"] = 0.0
    tem = {k: bool(rng.random() < prob) for k, prob in [
        ("chuveiro", P_CHUVEIRO_ELETRICO), ("ar", p["p_ar"]), ("maquina", P_MAQUINA),
        ("microondas", P_MICROONDAS), ("ventilador", P_VENTILADOR)]}
    if tem["chuveiro"]:
        horas = moradores * faixa(p["min_banho"]) / 60
        c["chuveiro"] = kwh(sortear_modelo(catalogo, "chuveiro", perfil), horas_dia=min(horas, 24))

    # ar-condicionado: potencia a 35 C x horas (conta do app) x fracao do tempo com compressor ligado
    c["ar_condicionado"] = 0.0
    if tem["ar"]:
        c["ar_condicionado"] = FATOR_COMPRESSOR * kwh(sortear_modelo(catalogo, "ar_condicionado", perfil),
                                                      horas_dia=faixa(p["h_ar"]))

    # TVs (kWh/mes fixo do Inmetro; o app ainda nao ajusta pelas horas)
    n_tv = int(np.clip(rng.poisson(1 + moradores / 3), 1, 4))
    c["televisor"] = sum(kwh(sortear_modelo(catalogo, "televisor", perfil)) for _ in range(n_tv))

    # iluminacao: ~1,5 lampada por comodo, parte fluorescente nos perfis menos eficientes
    c["iluminacao"] = 0.0
    horas_luz = faixa(p["h_luz"])
    for _ in range(int(round(comodos * 1.5))):
        tipo = "lampada_fluorescente" if rng.random() < p["p_fluorescente"] else "lampada_led"
        c["iluminacao"] += kwh(sortear_modelo(catalogo, tipo, perfil), horas_dia=horas_luz)

    c["maquina_de_lavar"] = 0.0
    if tem["maquina"]:
        ciclos = round(moradores * faixa(p["ciclos_pessoa"]))
        c["maquina_de_lavar"] = kwh(sortear_modelo(catalogo, "maquina_de_lavar", perfil), ciclos_mes=ciclos)

    c["microondas"] = 0.0
    if tem["microondas"]:
        c["microondas"] = kwh(sortear_modelo(catalogo, "microondas", perfil), horas_dia=faixa((0.1, 0.5)))

    c["ventilador"] = 0.0
    if tem["ventilador"]:
        for _ in range(int(rng.integers(1, 3))):
            categoria = "ventilador_de_teto" if rng.random() < 0.4 else "ventilador_de_mesa"
            c["ventilador"] += kwh(sortear_modelo(catalogo, categoria, perfil),
                                   velocidade=str(rng.choice(p["velocidade"])))

    total = sum(c.values())
    linha = {
        "id_residencia": i, "uf": dist["uf"], "distribuidora": dist["nome"],
        "tarifa_kwh": dist["tarifa_kwh"], "moradores": moradores, "comodos": comodos,
        **{f"tem_{k}": v for k, v in tem.items()},
        **{f"kwh_{k}": round(v, 2) for k, v in c.items()},
        "kwh_total": round(total, 2),
        "custo_mes": round(total * dist["tarifa_kwh"], 2),
        "kwh_por_morador": round(total / moradores, 2),
        "frac_chuveiro": round(c["chuveiro"] / total, 4),
        "frac_ar": round(c["ar_condicionado"] / total, 4),
        "frac_refrigerador": round(c["refrigerador"] / total, 4),
        # perfil usado na geracao: NAO usar para treinar o CTGAN/K-Means (vazamento);
        # serve so para conferir se os grupos do K-Means fazem sentido.
        "perfil_regra": perfil,
    }
    return linha


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 3000
    catalogo, tarifas = preparar_catalogo(), preparar_tarifas()
    print(f"Catalogo: {sum(map(len, catalogo.values()))} aparelhos | distribuidoras com UF: {len(tarifas)}")
    seed = pd.DataFrame([gerar_residencia(i, catalogo, tarifas) for i in range(1, n + 1)])
    seed.to_csv(SAIDA, index=False, encoding="utf-8-sig")
    print(f"{len(seed)} residencias salvas em {SAIDA}\n")
    print(seed.groupby("perfil_regra")[["kwh_total", "kwh_por_morador", "custo_mes"]].median().round(1))


if __name__ == "__main__":
    main()
