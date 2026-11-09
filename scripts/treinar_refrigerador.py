import pickle
import sys

import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import GroupKFold

import config

sys.path.insert(0, str(config.RAIZ_PROJETO / "src"))
import estimativa

BRUTO = "refrigeradores-e-assemelhados.csv"
ATUAL = config.PASTA_PROCESSED / "refrigeradores-e-assemelhados_limpo.csv"
TABELA_2001 = config.PASTA_RAW / "refrigeradores_inmetro_2001.csv"
MODELO = config.RAIZ_PROJETO / "models" / "refrigerador.pkl"

TIPOS = ["Refrigerador", "Refrigerador-Congelador", "Frigobar", "Congelador Vertical", "Congelador Horizontal"]
TIPO_2001 = {"1 porta": "Refrigerador"}
ESTRELAS = [f"volume_do_compartimento_de_alimentos_congelados_do_tipo_{n}_litros"
            for n in ("1_estrela", "2_estrelas", "3_estrelas")]
CONSUMO_ANTIGO = "consumo_de_energia_mensal_kwh_mes"
CONSUMO_2025 = "consumo_medio_de_energia_mensal_kwh_mes"
FATOR_CONGELADOR_2001 = 1.42
REGRESSAO_2001 = (21.1678, 0.0279)
VOLUMES = np.arange(40, 901)
MONOTONIA = [0] * len(TIPOS) + [0, 1]
DOBRAS = 5
SEMENTE = 42
MINIMO_PARES = 5
RAZAO_VALIDA = (0.3, 1.5)
VIDA_UTIL_ANOS = 16


def carregar_atual():
    df = pd.read_csv(ATUAL, encoding="utf-8-sig")
    df = df[df["tipo"].isin(TIPOS)].copy()
    df["frost_free"] = df["sistema_de_degelo"].fillna("").str.contains("Frost")
    congelador = df[ESTRELAS].fillna(0).sum(axis=1)
    df["volume_ajustado_l"] = df["volume_do_refrigerador_litros"] + FATOR_CONGELADOR_2001 * congelador
    tem_2025 = df[CONSUMO_2025].notna()
    imputado = df["consumo_imputado"].astype(str).str.lower().isin(["true", "1"])
    df["kwh_antigo"] = df[CONSUMO_ANTIGO].where(~tem_2025 & ~imputado)
    df["kwh_2025"] = df[CONSUMO_2025]
    df["grupo"] = df["marca"].str.lower().str.split().str[0]
    return df


def variaveis(df):
    x = pd.DataFrame({f"tipo_{t}": (df["tipo"] == t).astype(float) for t in TIPOS}, index=df.index)
    x["frost_free"] = df["frost_free"].astype(float)
    x["volume_total_litros"] = df["volume_total_litros"].astype(float)
    return x


def novo_rf():
    return RandomForestRegressor(n_estimators=300, min_samples_leaf=3, random_state=SEMENTE, n_jobs=-1,
                                 monotonic_cst=MONOTONIA)


def validar(dados, alvo):
    previsto_rf = pd.Series(np.nan, index=dados.index)
    previsto_media = pd.Series(np.nan, index=dados.index)
    for treino, teste in GroupKFold(n_splits=DOBRAS).split(dados, groups=dados["grupo"]):
        a, b = dados.iloc[treino], dados.iloc[teste]
        previsto_rf.iloc[teste] = novo_rf().fit(variaveis(a), a[alvo]).predict(variaveis(b))
        medias = a.groupby(["tipo", "frost_free"])[alvo].mean()
        chave = pd.MultiIndex.from_frame(b[["tipo", "frost_free"]])
        previsto_media.iloc[teste] = medias.reindex(chave).fillna(a[alvo].mean()).to_numpy()
    return previsto_rf, previsto_media


def mae(previsto, real):
    return float((previsto - real).abs().mean())


def treinar(df, alvo):
    dados = df.dropna(subset=[alvo]).drop_duplicates(
        subset=["grupo", "tipo", "frost_free", "volume_total_litros", alvo]).reset_index(drop=True)
    previsto_rf, previsto_media = validar(dados, alvo)
    dados["previsto"] = previsto_rf
    dados["erro_abs"] = (previsto_rf - dados[alvo]).abs()

    print(f"\n=== {alvo}: {len(dados)} modelos, {dados['grupo'].nunique()} marcas, GroupKFold por marca (k={DOBRAS}) ===")
    print(f"MAE Random Forest:              {mae(previsto_rf, dados[alvo]):.2f} kWh/mes")
    print(f"MAE media por tipo+degelo:      {mae(previsto_media, dados[alvo]):.2f} kWh/mes")
    print(f"Consumo medio real:             {dados[alvo].mean():.2f} kWh/mes")
    resumo = dados.groupby(["tipo", "frost_free"]).agg(
        n=(alvo, "size"), real_medio=(alvo, "mean"), mae_rf=("erro_abs", "mean"),
        vol_min=("volume_total_litros", "min"), vol_max=("volume_total_litros", "max")).round(2)
    print(resumo.to_string())

    metricas = {"mae": mae(previsto_rf, dados[alvo]), "mae_media_tipo": mae(previsto_media, dados[alvo]),
                "n": len(dados), "por_segmento": resumo.reset_index().to_dict("records")}
    return novo_rf().fit(variaveis(dados), dados[alvo]), dados, metricas


def comparar_regressao_2001(dados):
    com_volume = dados.dropna(subset=["volume_ajustado_l"])
    a, b = REGRESSAO_2001
    previsto_2001 = a + b * com_volume["volume_ajustado_l"]
    real = com_volume["kwh_antigo"]
    print(f"\n=== Baseline: regressao de 2001 ({a} + {b} x volume ajustado), {len(com_volume)} modelos com volumes separados ===")
    print(f"MAE regressao 2001:  {mae(previsto_2001, real):.2f} kWh/mes (vies medio {float((previsto_2001 - real).mean()):+.2f})")
    print(f"MAE Random Forest:   {mae(com_volume['previsto'], real):.2f} kWh/mes (mesmos modelos, validacao cruzada)")
    so_1_porta = com_volume[(com_volume["tipo"] == "Refrigerador") & ~com_volume["frost_free"]]
    if len(so_1_porta):
        p = a + b * so_1_porta["volume_ajustado_l"]
        print(f"So Refrigerador manual ({len(so_1_porta)}): regressao 2001 {mae(p, so_1_porta['kwh_antigo']):.2f} | "
              f"RF {mae(so_1_porta['previsto'], so_1_porta['kwh_antigo']):.2f} kWh/mes")
    return {"mae_regressao_2001": mae(previsto_2001, real), "mae_rf": mae(com_volume["previsto"], real),
            "n": len(com_volume)}


def fator_epoca(rf_antigo, dados_antigo):
    t = pd.read_csv(TABELA_2001, encoding="utf-8-sig")
    t["tipo"] = t["tipo"].map(TIPO_2001)
    t["frost_free"] = False
    t["volume_total_litros"] = t["volume_refrigerador_l"] + t["volume_congelador_l"]
    t["previsto_rf"] = rf_antigo.predict(variaveis(t))
    t["razao"] = t["consumo_kwh_mes"] / t["previsto_rf"]
    unicos = t.drop_duplicates(subset=["volume_refrigerador_l", "volume_congelador_l", "consumo_kwh_mes"])
    segmento = dados_antigo[(dados_antigo["tipo"] == "Refrigerador") & ~dados_antigo["frost_free"]]
    volume_max = float(segmento["volume_total_litros"].max())
    fora = int((t["volume_total_litros"] > volume_max).sum())

    print(f"\n=== Ft: tabela Inmetro 2001 ({len(t)} geladeiras 1 porta) / RF atual (Refrigerador, degelo manual) ===")
    print(f"Treino do segmento: {len(segmento)} modelos, ate {volume_max:g} L; {fora} geladeiras de 2001 acima disso (extrapolacao)")
    print(t[["marca", "modelo", "volume_total_litros", "consumo_kwh_mes", "previsto_rf", "razao"]].round(2).to_string(index=False))
    print(f"Ft = media das razoes:            {t['razao'].mean():.3f} (desvio {t['razao'].std():.3f}, "
          f"min {t['razao'].min():.2f}, max {t['razao'].max():.2f})")
    print(f"Mediana:                          {t['razao'].median():.3f}")
    print(f"Sem modelos repetidos ({len(unicos)}):     {unicos['razao'].mean():.3f}")
    return {"ft": float(t["razao"].mean()), "desvio": float(t["razao"].std()), "mediana": float(t["razao"].median()),
            "ft_sem_repetidos": float(unicos["razao"].mean()), "n": len(t), "n_sem_repetidos": len(unicos),
            "n_segmento_treino": len(segmento), "volume_max_treino": volume_max, "n_extrapolados": fora}


def numero(serie):
    return pd.to_numeric(serie.astype(str).str.replace(",", ".", regex=False), errors="coerce")


def resumo(serie):
    return {"mediana": float(serie.median()), "media": float(serie.mean()), "p25": float(serie.quantile(0.25)),
            "p75": float(serie.quantile(0.75)), "n": int(serie.size)}


def fator_metodo():
    bruto = config.ler_csv_inmetro(BRUTO)
    bruto["frost_free"] = bruto["Sistema de Degelo"].fillna("").str.contains("Frost")
    bruto["antigo"] = numero(bruto["Consumo de Energia Mensal (kWh/mês)"])
    bruto["atual"] = numero(bruto["Consumo Médio de Energia Mensal (kWh/mês)"])
    pares = bruto.dropna(subset=["antigo", "atual"]).drop_duplicates(subset=["Tipo", "frost_free", "antigo", "atual"])
    pares = pares.assign(razao=pares["atual"] / pares["antigo"])
    copiados = (pares["razao"] - 1).abs() < 0.005
    fora = ~pares["razao"].between(*RAZAO_VALIDA)
    validos = pares[~copiados & ~fora]

    print(f"\n=== Conversao metodologia antiga -> 2025 (modelos com as duas medicoes no arquivo bruto) ===")
    print(f"{len(pares)} pares; descartados {int(copiados.sum())} com valor copiado (razao 1,000) e "
          f"{int((fora & ~copiados).sum())} fora de {RAZAO_VALIDA}")
    por_segmento = {}
    for (tipo, frost_free), grupo in validos.groupby(["Tipo", "frost_free"]):
        estatistica = resumo(grupo["razao"])
        print(f"  {tipo:25s} frost_free={frost_free!s:5s} n={estatistica['n']:3d} mediana={estatistica['mediana']:.3f}")
        if estatistica["n"] >= MINIMO_PARES:
            por_segmento[(tipo, bool(frost_free))] = estatistica
    geral = resumo(validos["razao"])
    print(f"  geral n={geral['n']} mediana={geral['mediana']:.3f} (usada nos segmentos com menos de {MINIMO_PARES} pares)")
    return por_segmento, geral


def fracao_congelador(df):
    com_volume = df[~df["tipo"].str.startswith("Congelador") & df["volume_do_refrigerador_litros"].notna()
                    & (df["volume_total_litros"] > 0)]
    fracao = ((com_volume["volume_total_litros"] - com_volume["volume_do_refrigerador_litros"])
              / com_volume["volume_total_litros"]).clip(0, 1)
    por_segmento = {(tipo, bool(frost_free)): float(serie.median())
                    for (tipo, frost_free), serie in fracao.groupby([com_volume["tipo"], com_volume["frost_free"]])}
    return por_segmento, float(fracao.median())


def indice_regra_2006(dados_antigo):
    linhas = dados_antigo[dados_antigo["volume_do_refrigerador_litros"].notna()
                          | dados_antigo["tipo"].str.startswith("Congelador")].copy()
    estrelas = {n: linhas[coluna].fillna(0) for n, coluna in zip((1, 2, 3), ESTRELAS)}
    linhas["categoria_2006"] = [estimativa.categoria_2006(t, f) for t, f in zip(linhas["tipo"], linhas["frost_free"])]
    linhas["av"] = [
        estimativa.volume_ajustado_2006(vr, {n: estrelas[n].loc[i] for n in estrelas}, ff)
        for i, vr, ff in zip(linhas.index, linhas["volume_do_refrigerador_litros"].fillna(0), linhas["frost_free"])
    ]
    linhas = linhas[linhas["av"] > 0]
    linhas["ie"] = linhas["kwh_antigo"] / [estimativa.consumo_padrao_2006(c, v)
                                           for c, v in zip(linhas["categoria_2006"], linhas["av"])]
    print(f"\n=== Indice Ie = C / Cp ({estimativa.FONTE_PORTARIA_2006}) nos modelos atuais com consumo antigo real ===")
    por_categoria = {}
    for categoria, grupo in linhas.groupby("categoria_2006"):
        por_categoria[categoria] = resumo(grupo["ie"])
        e = por_categoria[categoria]
        print(f"  {categoria:32s} n={e['n']:3d} p25={e['p25']:.3f} mediana={e['mediana']:.3f} p75={e['p75']:.3f}")
    return por_categoria, resumo(linhas["ie"])


def indice_2001():
    t = pd.read_csv(TABELA_2001, encoding="utf-8-sig")
    av = [estimativa.volume_ajustado_2006(vr, {1: vc}, False)
          for vr, vc in zip(t["volume_refrigerador_l"], t["volume_congelador_l"])]
    ie = t["consumo_kwh_mes"] / [estimativa.consumo_padrao_2006("Refrigerador", v) for v in av]
    estatistica = resumo(ie)
    print(f"\n=== Ie da tabela de 2001 (o Cp da Portaria 20/2006 foi construido com ela): "
          f"media {estatistica['media']:.3f}, p25 {estatistica['p25']:.3f}, p75 {estatistica['p75']:.3f} ===")
    return estatistica


def grade(rf, dados, alvo):
    tabela = {}
    for tipo in TIPOS:
        for frost_free in (False, True):
            base = pd.DataFrame({"tipo": tipo, "frost_free": frost_free, "volume_total_litros": VOLUMES})
            segmento = dados[(dados["tipo"] == tipo) & (dados["frost_free"] == frost_free)]
            tabela[(tipo, frost_free)] = {
                "kwh_mes": rf.predict(variaveis(base)).round(3).tolist(),
                "n": len(segmento),
                "volume_min": float(segmento["volume_total_litros"].min()) if len(segmento) else None,
                "volume_max": float(segmento["volume_total_litros"].max()) if len(segmento) else None,
            }
    return tabela


def main():
    df = carregar_atual()
    rf_antigo, dados_antigo, metricas_antigo = treinar(df, "kwh_antigo")
    rf_2025, dados_2025, metricas_2025 = treinar(df, "kwh_2025")
    baseline = comparar_regressao_2001(dados_antigo)
    ft = fator_epoca(rf_antigo, dados_antigo)
    conversao, conversao_geral = fator_metodo()
    fracao, fracao_geral = fracao_congelador(df)
    ie_2006, ie_2006_geral = indice_regra_2006(df[df["kwh_antigo"].notna()])
    ie_2001 = indice_2001()

    modelo = {
        "fator_metodo": conversao,
        "fator_metodo_geral": conversao_geral,
        "fracao_congelador": fracao,
        "fracao_congelador_geral": fracao_geral,
        "ie_regra_2006": ie_2006,
        "ie_regra_2006_geral": ie_2006_geral,
        "ie_2001": ie_2001,
        "vida_util_anos": VIDA_UTIL_ANOS,
        "volumes": [int(VOLUMES[0]), int(VOLUMES[-1])],
        "tipos": TIPOS,
        "grade_2025": grade(rf_2025, dados_2025, "kwh_2025"),
        "grade_antigo": grade(rf_antigo, dados_antigo, "kwh_antigo"),
        "ft_2001": ft,
        "metricas": {"antigo": metricas_antigo, "2025": metricas_2025, "baseline_2001": baseline},
        "fonte": (f"Random Forest (tipo, frost-free, volume total) treinado em {ATUAL.name}; "
                  f"Ft com {TABELA_2001.name} (Inmetro 2001 via Queiroz et al., ACEEE 2003)"),
    }
    MODELO.parent.mkdir(exist_ok=True)
    with open(MODELO, "wb") as f:
        pickle.dump(modelo, f)
    print(f"\nModelo salvo em {MODELO}")


if __name__ == "__main__":
    main()
