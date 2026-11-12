import pickle
import sys

import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import GroupKFold

import config

sys.path.insert(0, str(config.PROJECT_ROOT / "src"))
import estimativa

RAW = "refrigeradores-e-assemelhados.csv"
CURRENT = config.PROCESSED_FOLDER / "refrigeradores-e-assemelhados_limpo.csv"
TABLE_2001 = config.RAW_FOLDER / "refrigeradores_inmetro_2001.csv"
MODEL = config.PROJECT_ROOT / "models" / "refrigerador.pkl"

TYPES = ["Refrigerador", "Refrigerador-Congelador", "Frigobar", "Congelador Vertical", "Congelador Horizontal"]
TYPE_2001 = {"1 porta": "Refrigerador"}
STARS = [f"volume_do_compartimento_de_alimentos_congelados_do_tipo_{n}_litros"
            for n in ("1_estrela", "2_estrelas", "3_estrelas")]
OLD_CONSUMPTION = "consumo_de_energia_mensal_kwh_mes"
CONSUMPTION_2025 = "consumo_medio_de_energia_mensal_kwh_mes"
FREEZER_FACTOR_2001 = 1.42
REGRESSION_2001 = (21.1678, 0.0279)
VOLUMES = np.arange(40, 901)
MONOTONICITY = [0] * len(TYPES) + [0, 1]
FOLDS = 5
SEED = 42
MIN_PAIRS = 5
VALID_RATIO = (0.3, 1.5)
USEFUL_LIFE_YEARS = 16


def load_current():
    df = pd.read_csv(CURRENT, encoding="utf-8-sig")
    df = df[df["tipo"].isin(TYPES)].copy()
    df["frost_free"] = df["sistema_de_degelo"].fillna("").str.contains("Frost")
    freezer = df[STARS].fillna(0).sum(axis=1)
    df["volume_ajustado_l"] = df["volume_do_refrigerador_litros"] + FREEZER_FACTOR_2001 * freezer
    has_2025 = df[CONSUMPTION_2025].notna()
    imputed = df["consumo_imputado"].astype(str).str.lower().isin(["true", "1"])
    df["kwh_antigo"] = df[OLD_CONSUMPTION].where(~has_2025 & ~imputed)
    df["kwh_2025"] = df[CONSUMPTION_2025]
    df["grupo"] = df["marca"].str.lower().str.split().str[0]
    return df


def variables(df):
    x = pd.DataFrame({f"tipo_{t}": (df["tipo"] == t).astype(float) for t in TYPES}, index=df.index)
    x["frost_free"] = df["frost_free"].astype(float)
    x["volume_total_litros"] = df["volume_total_litros"].astype(float)
    return x


def new_rf():
    return RandomForestRegressor(n_estimators=300, min_samples_leaf=3, random_state=SEED, n_jobs=-1,
                                 monotonic_cst=MONOTONICITY)


def validate(data, target):
    predicted_rf = pd.Series(np.nan, index=data.index)
    predicted_mean = pd.Series(np.nan, index=data.index)
    for training, test in GroupKFold(n_splits=FOLDS).split(data, groups=data["grupo"]):
        a, b = data.iloc[training], data.iloc[test]
        predicted_rf.iloc[test] = new_rf().fit(variables(a), a[target]).predict(variables(b))
        medias = a.groupby(["tipo", "frost_free"])[target].mean()
        key = pd.MultiIndex.from_frame(b[["tipo", "frost_free"]])
        predicted_mean.iloc[test] = medias.reindex(key).fillna(a[target].mean()).to_numpy()
    return predicted_rf, predicted_mean


def mae(predicted, real):
    return float((predicted - real).abs().mean())


def train(df, target):
    data = df.dropna(subset=[target]).drop_duplicates(
        subset=["grupo", "tipo", "frost_free", "volume_total_litros", target]).reset_index(drop=True)
    predicted_rf, predicted_mean = validate(data, target)
    data["previsto"] = predicted_rf
    data["erro_abs"] = (predicted_rf - data[target]).abs()

    print(f"\n=== {target}: {len(data)} modelos, {data['grupo'].nunique()} marcas, GroupKFold por marca (k={FOLDS}) ===")
    print(f"MAE Random Forest:              {mae(predicted_rf, data[target]):.2f} kWh/mes")
    print(f"MAE media por tipo+degelo:      {mae(predicted_mean, data[target]):.2f} kWh/mes")
    print(f"Consumo medio real:             {data[target].mean():.2f} kWh/mes")
    summary = data.groupby(["tipo", "frost_free"]).agg(
        n=(target, "size"), real_medio=(target, "mean"), mae_rf=("erro_abs", "mean"),
        vol_min=("volume_total_litros", "min"), vol_max=("volume_total_litros", "max")).round(2)
    print(summary.to_string())

    metrics = {"mae": mae(predicted_rf, data[target]), "mae_media_tipo": mae(predicted_mean, data[target]),
                "n": len(data), "por_segmento": summary.reset_index().to_dict("records")}
    return new_rf().fit(variables(data), data[target]), data, metrics


def compare_regression_2001(data):
    with_volume = data.dropna(subset=["volume_ajustado_l"])
    a, b = REGRESSION_2001
    predicted_2001 = a + b * with_volume["volume_ajustado_l"]
    real = with_volume["kwh_antigo"]
    print(f"\n=== Baseline: regressao de 2001 ({a} + {b} x volume ajustado), {len(with_volume)} modelos com volumes separados ===")
    print(f"MAE regressao 2001:  {mae(predicted_2001, real):.2f} kWh/mes (vies medio {float((predicted_2001 - real).mean()):+.2f})")
    print(f"MAE Random Forest:   {mae(with_volume['previsto'], real):.2f} kWh/mes (mesmos modelos, validacao cruzada)")
    one_door_only = with_volume[(with_volume["tipo"] == "Refrigerador") & ~with_volume["frost_free"]]
    if len(one_door_only):
        p = a + b * one_door_only["volume_ajustado_l"]
        print(f"So Refrigerador manual ({len(one_door_only)}): regressao 2001 {mae(p, one_door_only['kwh_antigo']):.2f} | "
              f"RF {mae(one_door_only['previsto'], one_door_only['kwh_antigo']):.2f} kWh/mes")
    return {"mae_regressao_2001": mae(predicted_2001, real), "mae_rf": mae(with_volume["previsto"], real),
            "n": len(with_volume)}


def era_factor(old_rf, old_data):
    t = pd.read_csv(TABLE_2001, encoding="utf-8-sig")
    t["tipo"] = t["tipo"].map(TYPE_2001)
    t["frost_free"] = False
    t["volume_total_litros"] = t["volume_refrigerador_l"] + t["volume_congelador_l"]
    t["previsto_rf"] = old_rf.predict(variables(t))
    t["razao"] = t["consumo_kwh_mes"] / t["previsto_rf"]
    unique = t.drop_duplicates(subset=["volume_refrigerador_l", "volume_congelador_l", "consumo_kwh_mes"])
    segment = old_data[(old_data["tipo"] == "Refrigerador") & ~old_data["frost_free"]]
    volume_max = float(segment["volume_total_litros"].max())
    outside = int((t["volume_total_litros"] > volume_max).sum())

    print(f"\n=== Ft: tabela Inmetro 2001 ({len(t)} geladeiras 1 porta) / RF atual (Refrigerador, degelo manual) ===")
    print(f"Treino do segmento: {len(segment)} modelos, ate {volume_max:g} L; {outside} geladeiras de 2001 acima disso (extrapolacao)")
    print(t[["marca", "modelo", "volume_total_litros", "consumo_kwh_mes", "previsto_rf", "razao"]].round(2).to_string(index=False))
    print(f"Ft = media das razoes:            {t['razao'].mean():.3f} (desvio {t['razao'].std():.3f}, "
          f"min {t['razao'].min():.2f}, max {t['razao'].max():.2f})")
    print(f"Mediana:                          {t['razao'].median():.3f}")
    print(f"Sem modelos repetidos ({len(unique)}):     {unique['razao'].mean():.3f}")
    return {"ft": float(t["razao"].mean()), "desvio": float(t["razao"].std()), "mediana": float(t["razao"].median()),
            "ft_sem_repetidos": float(unique["razao"].mean()), "n": len(t), "n_sem_repetidos": len(unique),
            "n_segmento_treino": len(segment), "volume_max_treino": volume_max, "n_extrapolados": outside}


def number(series):
    return pd.to_numeric(series.astype(str).str.replace(",", ".", regex=False), errors="coerce")


def summary(series):
    return {"mediana": float(series.median()), "media": float(series.mean()), "p25": float(series.quantile(0.25)),
            "p75": float(series.quantile(0.75)), "n": int(series.size)}


def method_factor():
    raw = config.read_csv_inmetro(RAW)
    raw["frost_free"] = raw["Sistema de Degelo"].fillna("").str.contains("Frost")
    raw["antigo"] = number(raw["Consumo de Energia Mensal (kWh/mês)"])
    raw["atual"] = number(raw["Consumo Médio de Energia Mensal (kWh/mês)"])
    pairs = raw.dropna(subset=["antigo", "atual"]).drop_duplicates(subset=["Tipo", "frost_free", "antigo", "atual"])
    pairs = pairs.assign(razao=pairs["atual"] / pairs["antigo"])
    copied = (pairs["razao"] - 1).abs() < 0.005
    outside = ~pairs["razao"].between(*VALID_RATIO)
    valid_items = pairs[~copied & ~outside]

    print(f"\n=== Conversao metodologia antiga -> 2025 (modelos com as duas medicoes no arquivo bruto) ===")
    print(f"{len(pairs)} pares; descartados {int(copied.sum())} com valor copiado (razao 1,000) e "
          f"{int((outside & ~copied).sum())} fora de {VALID_RATIO}")
    by_segment = {}
    for (kind, frost_free), group in valid_items.groupby(["Tipo", "frost_free"]):
        statistic = summary(group["razao"])
        print(f"  {kind:25s} frost_free={frost_free!s:5s} n={statistic['n']:3d} mediana={statistic['mediana']:.3f}")
        if statistic["n"] >= MIN_PAIRS:
            by_segment[(kind, bool(frost_free))] = statistic
    general = summary(valid_items["razao"])
    print(f"  geral n={general['n']} mediana={general['mediana']:.3f} (usada nos segmentos com menos de {MIN_PAIRS} pares)")
    return by_segment, general


def freezer_fraction(df):
    with_volume = df[~df["tipo"].str.startswith("Congelador") & df["volume_do_refrigerador_litros"].notna()
                    & (df["volume_total_litros"] > 0)]
    fraction = ((with_volume["volume_total_litros"] - with_volume["volume_do_refrigerador_litros"])
              / with_volume["volume_total_litros"]).clip(0, 1)
    by_segment = {(kind, bool(frost_free)): float(series.median())
                    for (kind, frost_free), series in fraction.groupby([with_volume["tipo"], with_volume["frost_free"]])}
    return by_segment, float(fraction.median())


def rule_index_2006(old_data):
    lines = old_data[old_data["volume_do_refrigerador_litros"].notna()
                          | old_data["tipo"].str.startswith("Congelador")].copy()
    stars = {n: lines[column].fillna(0) for n, column in zip((1, 2, 3), STARS)}
    lines["categoria_2006"] = [estimativa.category_2006(t, f) for t, f in zip(lines["tipo"], lines["frost_free"])]
    lines["av"] = [
        estimativa.adjusted_volume_2006(vr, {n: stars[n].loc[i] for n in stars}, ff)
        for i, vr, ff in zip(lines.index, lines["volume_do_refrigerador_litros"].fillna(0), lines["frost_free"])
    ]
    lines = lines[lines["av"] > 0]
    lines["ie"] = lines["kwh_antigo"] / [estimativa.default_consumption_2006(c, v)
                                           for c, v in zip(lines["categoria_2006"], lines["av"])]
    print(f"\n=== Indice Ie = C / Cp ({estimativa.ORDINANCE_SOURCE_2006}) nos modelos atuais com consumo antigo real ===")
    by_category = {}
    for category, group in lines.groupby("categoria_2006"):
        by_category[category] = summary(group["ie"])
        e = by_category[category]
        print(f"  {category:32s} n={e['n']:3d} p25={e['p25']:.3f} mediana={e['mediana']:.3f} p75={e['p75']:.3f}")
    return by_category, summary(lines["ie"])


def index_2001():
    t = pd.read_csv(TABLE_2001, encoding="utf-8-sig")
    av = [estimativa.adjusted_volume_2006(vr, {1: vc}, False)
          for vr, vc in zip(t["volume_refrigerador_l"], t["volume_congelador_l"])]
    ie = t["consumo_kwh_mes"] / [estimativa.default_consumption_2006("Refrigerador", v) for v in av]
    statistic = summary(ie)
    print(f"\n=== Ie da tabela de 2001 (o Cp da Portaria 20/2006 foi construido com ela): "
          f"media {statistic['media']:.3f}, p25 {statistic['p25']:.3f}, p75 {statistic['p75']:.3f} ===")
    return statistic


def grid(rf, data, target):
    table = {}
    for kind in TYPES:
        for frost_free in (False, True):
            base = pd.DataFrame({"tipo": kind, "frost_free": frost_free, "volume_total_litros": VOLUMES})
            segment = data[(data["tipo"] == kind) & (data["frost_free"] == frost_free)]
            table[(kind, frost_free)] = {
                "kwh_mes": rf.predict(variables(base)).round(3).tolist(),
                "n": len(segment),
                "volume_min": float(segment["volume_total_litros"].min()) if len(segment) else None,
                "volume_max": float(segment["volume_total_litros"].max()) if len(segment) else None,
            }
    return table


def main():
    df = load_current()
    old_rf, old_data, old_metrics = train(df, "kwh_antigo")
    rf_2025, data_2025, metrics_2025 = train(df, "kwh_2025")
    baseline = compare_regression_2001(old_data)
    ft = era_factor(old_rf, old_data)
    conversion, general_conversion = method_factor()
    fraction, general_fraction = freezer_fraction(df)
    ie_2006, general_ie_2006 = rule_index_2006(df[df["kwh_antigo"].notna()])
    ie_2001 = index_2001()

    model = {
        "fator_metodo": conversion,
        "fator_metodo_geral": general_conversion,
        "fracao_congelador": fraction,
        "fracao_congelador_geral": general_fraction,
        "ie_regra_2006": ie_2006,
        "ie_regra_2006_geral": general_ie_2006,
        "ie_2001": ie_2001,
        "vida_util_anos": USEFUL_LIFE_YEARS,
        "volumes": [int(VOLUMES[0]), int(VOLUMES[-1])],
        "tipos": TYPES,
        "grade_2025": grid(rf_2025, data_2025, "kwh_2025"),
        "grade_antigo": grid(old_rf, old_data, "kwh_antigo"),
        "ft_2001": ft,
        "metricas": {"antigo": old_metrics, "2025": metrics_2025, "baseline_2001": baseline},
        "fonte": (f"Random Forest (tipo, frost-free, volume total) treinado em {CURRENT.name}; "
                  f"Ft com {TABLE_2001.name} (Inmetro 2001 via Queiroz et al., ACEEE 2003)"),
    }
    MODEL.parent.mkdir(exist_ok=True)
    with open(MODEL, "wb") as f:
        pickle.dump(model, f)
    print(f"\nModelo salvo em {MODEL}")


if __name__ == "__main__":
    main()
