import pickle
from datetime import date
from functools import lru_cache
from pathlib import Path

MODELO = Path(__file__).resolve().parents[1] / "models" / "refrigerador.pkl"

FONTE_PORTARIA_2006 = "Portaria Inmetro 20/2006, RESP/001-REF, Anexo VI"
FONTE_TABELA_2001 = "Tabela Inmetro 2001 via Queiroz et al., ACEEE Summer Study 2003"
FONTE_FI = "Fatores de desgaste por idade: Jannuzzi/Unicamp e estudo de campo da Unifei (premissa do grupo)"

RETAS_2006 = {
    "Refrigerador": (0.0346, 19.117),
    "Combinado": (0.0916, 17.083),
    "Combinado frost free": (0.1059, 7.4862),
    "Congelador vertical": (0.0211, 39.228),
    "Congelador vertical frost free": (0.0178, 58.712),
    "Congelador horizontal": (0.0758, 13.095),
}
LIMITE_CLASSE_A_2006 = {"Combinado frost free": 0.846}
LIMITE_CLASSE_A_2006_PADRAO = 0.855
FATOR_ESTRELAS_2006 = {1: 1.41, 2: 1.63, 3: 1.85}
FATOR_FROST_FREE_2006 = 1.2

ANO_REGRA_2006 = 2006
ANO_ETIQUETA_NOVA = 2023
ANO_MINIMO = 1980
VOLUME_MAXIMO_L = 1000
FAIXAS_FI = ((5, 1.00), (10, 1.10), (float("inf"), 1.30))

TIPOS = {
    "1_porta": {"nome": "geladeira 1 porta", "tipo_inmetro": "Refrigerador", "estrelas": 1, "so_congelador": False},
    "frigobar": {"nome": "frigobar", "tipo_inmetro": "Frigobar", "estrelas": 1, "so_congelador": False},
    "duplex": {"nome": "geladeira duplex", "tipo_inmetro": "Refrigerador-Congelador", "estrelas": 3, "so_congelador": False},
    "freezer_vertical": {"nome": "freezer vertical", "tipo_inmetro": "Congelador Vertical", "estrelas": 3, "so_congelador": True},
    "freezer_horizontal": {"nome": "freezer horizontal", "tipo_inmetro": "Congelador Horizontal", "estrelas": 3, "so_congelador": True},
}

RESISTIVOS = {
    "air_fryer": {"nome": "Air fryer", "potencia_w": 1500, "horas_dia": 0.5, "dias_mes": 15},
    "secador_cabelo": {"nome": "Secador de cabelo", "potencia_w": 2000, "horas_dia": 0.25, "dias_mes": 20},
    "chuveiro": {"nome": "Chuveiro elétrico", "potencia_w": 5500, "horas_dia": 0.25, "dias_mes": 30},
    "ferro_passar": {"nome": "Ferro de passar", "potencia_w": 1200, "horas_dia": 1.0, "dias_mes": 8},
    "sanduicheira": {"nome": "Sanduicheira", "potencia_w": 800, "horas_dia": 0.25, "dias_mes": 8},
}

AVISO_APROXIMADO = ("Gasto aproximado: o modelo nao esta no catalogo do Inmetro, entao o consumo foi estimado "
                    "pelo tipo, volume e ano de compra. O valor real pode estar em qualquer ponto da faixa.")
AVISO_ETIQUETA = ("Consumo da etiqueta do aparelho, convertido para a metodologia de ensaio atual e ajustado "
                  "pelo desgaste da idade.")
AVISO_POTENCIA_TIPICA = ("A potencia usada e a tipica da categoria (estimativa do grupo). Informe a da etiqueta "
                         "do aparelho para um valor mais preciso.")


@lru_cache(maxsize=1)
def carregar_modelo(caminho=MODELO):
    if not Path(caminho).exists():
        raise FileNotFoundError(f"{caminho} nao existe. Rode: python scripts/treinar_refrigerador.py")
    with open(caminho, "rb") as f:
        return pickle.load(f)


def categoria_2006(tipo_inmetro, frost_free):
    if tipo_inmetro in ("Refrigerador", "Frigobar"):
        return "Refrigerador"
    if tipo_inmetro == "Refrigerador-Congelador":
        return "Combinado frost free" if frost_free else "Combinado"
    if tipo_inmetro == "Congelador Vertical":
        return "Congelador vertical frost free" if frost_free else "Congelador vertical"
    return "Congelador horizontal"


def volume_ajustado_2006(volume_refrigerador, congelador_por_estrelas, frost_free):
    congelador = sum(FATOR_ESTRELAS_2006[estrelas] * volume for estrelas, volume in congelador_por_estrelas.items())
    return (volume_refrigerador + congelador) * (FATOR_FROST_FREE_2006 if frost_free else 1.0)


def consumo_padrao_2006(categoria, volume_ajustado):
    a, b = RETAS_2006[categoria]
    return a * volume_ajustado + b


def tempo_por_dia(horas):
    total = round(horas * 60)
    h, m = divmod(total, 60)
    texto = f"{m} min" if h == 0 else (f"{h} h" if m == 0 else f"{h} h {m} min")
    return f"{texto}/dia"


def fator_idade(idade):
    if idade < 0:
        raise ValueError("o ano de compra nao pode ser no futuro")
    return next(fator for limite, fator in FAIXAS_FI if idade <= limite)


def _validar(tipo, volume_total_l, volume_congelador_l, ano_compra, ano_referencia):
    if tipo not in TIPOS:
        raise ValueError(f"tipo precisa ser um de: {', '.join(TIPOS)}")
    if not 0 < volume_total_l <= VOLUME_MAXIMO_L:
        raise ValueError(f"o volume total precisa estar entre 1 e {VOLUME_MAXIMO_L} litros")
    if volume_congelador_l is not None and not 0 <= volume_congelador_l <= volume_total_l:
        raise ValueError("o volume do freezer precisa estar entre 0 e o volume total")
    if not ANO_MINIMO <= ano_compra <= ano_referencia:
        raise ValueError(f"o ano de compra precisa estar entre {ANO_MINIMO} e {ano_referencia}")


def _segmento(modelo, grade, tipo_inmetro, frost_free):
    return modelo[grade][(tipo_inmetro, frost_free)]


def _previsao(segmento, modelo, volume):
    inicio, fim = modelo["volumes"]
    indice = int(round(min(max(volume, inicio), fim))) - inicio
    return segmento["kwh_mes"][indice]


def _conversao(modelo, tipo_inmetro, frost_free):
    return modelo["fator_metodo"].get((tipo_inmetro, frost_free), modelo["fator_metodo_geral"])


def fator_metodologia(tipo_inmetro, frost_free, modelo=None):
    return _conversao(modelo or carregar_modelo(), tipo_inmetro, bool(frost_free))["mediana"]


def _mae_2025(modelo, tipo_inmetro, frost_free):
    for linha in modelo["metricas"]["2025"]["por_segmento"]:
        if linha["tipo"] == tipo_inmetro and bool(linha["frost_free"]) == frost_free:
            return float(linha["mae_rf"])
    return float(modelo["metricas"]["2025"]["mae"])


def _por_etiqueta(modelo, info, frost_free, kwh_etiqueta, ano_compra, fi):
    if ano_compra >= ANO_ETIQUETA_NOVA:
        base = kwh_etiqueta
        return {"kwh_mes": base * fi, "kwh_min": base * fi, "kwh_max": base * fi,
                "metodo": f"etiqueta {kwh_etiqueta:g} kWh/mes (metodologia atual) x Fi {fi:.2f}"}
    conversao = _conversao(modelo, info["tipo_inmetro"], frost_free)
    return {
        "kwh_mes": kwh_etiqueta * conversao["mediana"] * fi,
        "kwh_min": kwh_etiqueta * conversao["p25"] * fi,
        "kwh_max": kwh_etiqueta * conversao["p75"] * fi,
        "metodo": (f"etiqueta {kwh_etiqueta:g} kWh/mes (metodologia antiga) x {conversao['mediana']:.2f} "
                   f"(conversao para a metodologia atual) x Fi {fi:.2f}"),
    }


def _pela_regra_2006(modelo, info, frost_free, volume_total_l, volume_congelador_l, ano_compra, fi):
    tipo_inmetro = info["tipo_inmetro"]
    if info["so_congelador"]:
        refrigerador, congelador = 0.0, volume_total_l
    else:
        if volume_congelador_l is None:
            volume_congelador_l = volume_total_l * modelo["fracao_congelador"].get(
                (tipo_inmetro, frost_free), modelo["fracao_congelador_geral"])
        refrigerador, congelador = volume_total_l - volume_congelador_l, volume_congelador_l
    categoria = categoria_2006(tipo_inmetro, frost_free)
    av = volume_ajustado_2006(refrigerador, {info["estrelas"]: congelador}, frost_free)
    cp = consumo_padrao_2006(categoria, av)

    if ano_compra < ANO_REGRA_2006:
        ie = modelo["ie_2001"]
        ie_min, ie_ponto, ie_max, epoca = ie["p25"], ie["media"], ie["p75"], "tabela Inmetro 2001"
    else:
        ie_min = modelo["ie_regra_2006"].get(categoria, modelo["ie_regra_2006_geral"])["mediana"]
        ie_max = LIMITE_CLASSE_A_2006.get(categoria, LIMITE_CLASSE_A_2006_PADRAO)
        ie_ponto, epoca = (ie_min + ie_max) / 2, "regra de 2006 (classe A)"
    conversao = _conversao(modelo, tipo_inmetro, frost_free)["mediana"]
    return {
        "kwh_mes": ie_ponto * cp * conversao * fi,
        "kwh_min": ie_min * cp * conversao * fi,
        "kwh_max": ie_max * cp * conversao * fi,
        "metodo": (f"consumo padrao {cp:.1f} kWh/mes ({categoria}, volume ajustado {av:.0f} L) x indice "
                   f"{ie_ponto:.2f} ({epoca}, faixa {ie_min:.2f} a {ie_max:.2f}) x {conversao:.2f} "
                   f"(conversao para a metodologia atual) x Fi {fi:.2f}"),
    }


def _pelo_modelo_atual(modelo, info, frost_free, volume_total_l, fi):
    segmento = _segmento(modelo, "grade_2025", info["tipo_inmetro"], frost_free)
    previsto = _previsao(segmento, modelo, volume_total_l)
    erro = _mae_2025(modelo, info["tipo_inmetro"], frost_free)
    return {
        "kwh_mes": previsto * fi,
        "kwh_min": max(previsto - erro, 0.0) * fi,
        "kwh_max": (previsto + erro) * fi,
        "metodo": (f"Random Forest com os modelos atuais do Inmetro: {previsto:.1f} kWh/mes "
                   f"(erro medio {erro:.1f}) x Fi {fi:.2f}"),
    }


def consumo_refrigerador_estimado(tipo, frost_free, volume_total_l, ano_compra, volume_congelador_l=None,
                                  kwh_etiqueta=None, ano_referencia=None, modelo=None):
    ano_referencia = ano_referencia or date.today().year
    _validar(tipo, volume_total_l, volume_congelador_l, ano_compra, ano_referencia)
    if kwh_etiqueta is not None and kwh_etiqueta <= 0:
        raise ValueError("o consumo da etiqueta precisa ser maior que zero")
    modelo = modelo or carregar_modelo()
    info = TIPOS[tipo]
    idade = ano_referencia - ano_compra
    fi = fator_idade(idade)

    if kwh_etiqueta is not None:
        calculo, avisos, fontes = _por_etiqueta(modelo, info, frost_free, kwh_etiqueta, ano_compra, fi), [AVISO_ETIQUETA], [FONTE_FI]
    elif ano_compra >= ANO_ETIQUETA_NOVA:
        calculo, avisos, fontes = _pelo_modelo_atual(modelo, info, frost_free, volume_total_l, fi), [AVISO_APROXIMADO], [modelo["fonte"], FONTE_FI]
    else:
        calculo = _pela_regra_2006(modelo, info, frost_free, volume_total_l, volume_congelador_l, ano_compra, fi)
        avisos, fontes = [AVISO_APROXIMADO], [FONTE_PORTARIA_2006, FONTE_TABELA_2001, FONTE_FI]

    if idade > modelo["vida_util_anos"]:
        avisos.append(f"Com {idade} anos, o aparelho passou da vida util media de {modelo['vida_util_anos']} anos.")
    descricao = f"{info['nome']}{' frost-free' if frost_free else ''}, {volume_total_l:g} L, comprada em {ano_compra}"
    return {
        **calculo,
        "categoria": "refrigerador",
        "nome": info["nome"].capitalize(),
        "tipo": info["tipo_inmetro"],
        "capacidade": float(volume_total_l),
        "detalhe": descricao,
        "idade_anos": idade,
        "fator_idade": fi,
        "premissa": False,
        "aproximado": True,
        "avisos": avisos,
        "fonte": "; ".join(fontes),
    }


def consumo_resistivo(categoria, potencia_w=None, horas_dia=None, dias_mes=None):
    if categoria not in RESISTIVOS:
        raise ValueError(f"categoria precisa ser uma de: {', '.join(RESISTIVOS)}")
    padrao = RESISTIVOS[categoria]
    potencia = padrao["potencia_w"] if potencia_w is None else potencia_w
    horas = padrao["horas_dia"] if horas_dia is None else horas_dia
    dias = padrao["dias_mes"] if dias_mes is None else dias_mes
    if potencia <= 0:
        raise ValueError("a potencia precisa ser maior que zero")
    if not 0 <= horas <= 24:
        raise ValueError("horas por dia precisa estar entre 0 e 24")
    if not 0 <= dias <= 31:
        raise ValueError("dias de uso por mes precisa estar entre 0 e 31")

    return {
        "kwh_mes": potencia / 1000 * horas * dias,
        "metodo": (f"{potencia:g} W ({_origem(potencia_w)}) / 1000 x {tempo_por_dia(horas)} ({_origem(horas_dia)}) "
                   f"x {dias:g} dias ({_origem(dias_mes)})"),
        "categoria": categoria,
        "nome": padrao["nome"],
        "detalhe": f"{padrao['nome']}, {potencia:g} W",
        "horas_dia": horas,
        "premissa": horas_dia is None or dias_mes is None,
        "aproximado": None in (potencia_w, horas_dia, dias_mes),
        "avisos": [] if potencia_w is not None else [AVISO_POTENCIA_TIPICA],
        "fonte": "potencia x tempo de uso" + ("" if potencia_w is not None else "; potencia tipica: premissa do grupo"),
    }


def _origem(informado):
    return "informado" if informado is not None else "padrao do grupo"
