"""
Regras de calculo do iamp: catalogo de aparelhos, consumo mensal e custo.

Usado por criar_banco.py (monta o catalogo a partir dos CSVs limpos) e por
servico.py (calcula o consumo e monta o resultado para a tela).
"""

import re
import unicodedata

import pandas as pd

import config
import estimativa
from estimativa import time_per_day
from idioma import t, tr, units

DAYS_PER_MONTH = 30
SEARCH_LIMIT = 15  # modelos por tipo de aparelho na busca (uma marca pode ter varios tipos)
BRAND_MODEL_LIMIT = 50  # modelos de uma marca na lista de marcas do app (o resto: digitar o modelo)

# Padroes de uso para aparelhos em que o Inmetro so informa potencia ou consumo por ciclo.
# ATENCAO: valores escolhidos pelo grupo, ainda sem fonte. O app mostra como "estimativa"
# e deixa o usuario trocar. Aparelho sem padrao aqui (ex.: chuveiro) obriga o usuario a informar.
ASSUMPTIONS = {
    "lampada_led": {"horas_dia": 5.0},
    "lampada_fluorescente": {"horas_dia": 5.0},
    "lampada_vapor_sodio": {"horas_dia": 12.0},
    "microondas": {"horas_dia": 0.33},
    "bomba": {"horas_dia": 1.0},
    "maquina_de_lavar": {"ciclos_mes": 12},
}

# Aparelhos em que o Inmetro ja informa o kWh/mes, mas o uso real varia muito de casa para casa.
# O app pergunta as horas (resposta opcional); sem resposta, fica o valor da tabela do Inmetro.
#  - ar-condicionado: usa a potencia a 35 C em carga total (teto: o inverter costuma gastar menos)
#  - televisor: o dataset nao traz a potencia ligada, entao o kWh/mes e reescalado pelas horas
#    do ensaio (regra de tres: kWh/mes x horas do usuario / 6,59).
#    6,59 h ligada + 17,41 h em stand-by por dia = padrao de ensaio levantado pelo grupo.
#    LIMITACAO: ainda sem o documento oficial (regulamento do PBE de televisores) e sem saber se
#    o kWh/mes do Inmetro inclui o stand-by; por isso o consumo inteiro e reescalado.
#  - ventiladores: o kWh/mes do Inmetro e de 1 h por dia (potencia x 30 h, conferido nos CSVs brutos).
#    Sem as horas, o ventilador sairia como se ficasse ligado 1 h por dia, entao a resposta e obrigatoria.
INMETRO_REFERENCE_HOURS = {"televisor": 6.59, "ventilador_de_mesa": 1.0, "ventilador_de_teto": 1.0}
OPTIONAL_HOURS = {"ar_condicionado", "televisor"}
# Aparelhos em que o app pergunta em quantos dias do mes a pessoa liga (resposta opcional; em branco = 30).
# Ar-condicionado: muita gente liga so no verao ou em alguns dias da semana; contar 30 dias exagerava o
# gasto. Os dias multiplicam a potencia x horas ou, sem horas, reescalam o kWh/mes do Inmetro (x dias / 30).
ASK_DAYS = {"ar_condicionado"}
SPEED_NAMES = {"baixa": "baixa", "media": "média", "alta": "alta"}
SPEED_NAMES_EN = {"baixa": "low", "media": "medium", "alta": "high"}

NUM_COLUMNS = [
    "kwh_mes", "kwh_mes_baixa", "kwh_mes_media", "kwh_mes_alta",
    "kwh_ciclo", "potencia_w", "standby_kwh_mes", "fluxo_lm",
]

# Sugestao de aparelho mais economico: so comparamos modelos que fazem o mesmo servico.
#  - categorias: onde procurar (fluorescente -> LED e permitido, as duas tem lumens)
#  - medida: coluna que precisa ser parecida (capacidade = litros, polegadas, BTU/h, kg, cm ou cv)
#  - tolerancia: diferenca maxima da medida (0.15 = 15% para mais ou para menos)
#  - mesmo_tipo: exige o mesmo tipo (so onde o tipo vem padronizado no Inmetro)
EQUIVALENCE = {
    "refrigerador": {"categorias": ["refrigerador"], "medida": "capacidade", "tolerancia": 0.15,
                     "mesmo_tipo": True, "texto": "mesmo tipo e volume parecido (até 15% de diferença)"},
    "televisor": {"categorias": ["televisor"], "medida": "capacidade", "tolerancia": 0.05,
                  "mesmo_tipo": False, "texto": "tela do mesmo tamanho (até 5% de diferença)"},
    "ar_condicionado": {"categorias": ["ar_condicionado"], "medida": "capacidade", "tolerancia": 0.05,
                        "mesmo_tipo": True, "texto": "mesmo tipo e mesma capacidade em BTU/h (até 5% de diferença)"},
    "ventilador_de_mesa": {"categorias": ["ventilador_de_mesa"], "medida": "capacidade", "tolerancia": 0.10,
                           "mesmo_tipo": False, "texto": "hélice de diâmetro parecido (até 10% de diferença)"},
    "ventilador_de_teto": {"categorias": ["ventilador_de_teto"], "medida": "capacidade", "tolerancia": 0.10,
                           "mesmo_tipo": False, "texto": "diâmetro parecido (até 10% de diferença)"},
    "maquina_de_lavar": {"categorias": ["maquina_de_lavar"], "medida": "capacidade", "tolerancia": 0.15,
                         "mesmo_tipo": True, "texto": "mesmo tipo e capacidade parecida em kg (até 15% de diferença)"},
    "lampada_led": {"categorias": ["lampada_led"], "medida": "fluxo_lm", "tolerancia": 0.10,
                    "mesmo_tipo": False, "texto": "mesma luminosidade em lumens (até 10% de diferença)"},
    "lampada_fluorescente": {"categorias": ["lampada_led", "lampada_fluorescente"], "medida": "fluxo_lm",
                             "tolerancia": 0.10, "mesmo_tipo": False,
                             "texto": "mesma luminosidade em lumens (até 10% de diferença), incluindo lâmpadas LED"},
    "bomba": {"categorias": ["bomba"], "medida": "capacidade", "tolerancia": 0.0, "mesmo_tipo": False,
              "texto": "motor de mesma potência (cv); confira vazão e altura com o fabricante"},
}


def _label(field, unit, where, example, maximum):
    return {"campo": field, "nome": "Etiqueta amarela do Inmetro", "rotulo": "Consumo de energia",
            "unidade": unit, "onde": where, "dica": None, "exemplo": example, "maximo": maximum}


def _nameplate(where, example, maximum, tip=None):
    return {"campo": "potencia_w", "nome": "Potência escrita no aparelho", "rotulo": "Potência",
            "unidade": "W", "onde": where, "dica": tip, "exemplo": example, "maximo": maximum}


def _sizes(unit, *values):
    return [{"valor": v, "nome": f"{v:,} {unit}".replace(",", ".")} for v in values]


# Aparelho fora do catalogo (antigo ou sem modelo). O usuario informa o numero do proprio aparelho
# (formas: etiqueta do Inmetro ou potencia da plaqueta, que vale tambem para aparelho antigo) ou,
# sem ele, o tipo e o tamanho, e o gasto sai da mediana dos modelos parecidos do catalogo.
#  - ar-condicionado e ventiladores: sem etiqueta. A do ar mudou de kWh/mes para kWh/ano em 2023 e a do
#    ventilador e de 1 h por dia; a potencia da plaqueta x horas evita essa confusao.
#  - ventilador de teto: sem tamanho (o diametro do catalogo tem erros e ninguem sabe o seu de cabeca).
#  - obrigatorio: sem catalogo para comparar, o usuario precisa informar a potencia.
ESTIMABLE = {
    "refrigerador": {"nome": "Geladeira ou freezer", "especial": True},
    "maquina_de_lavar": {
        "nome": "Máquina de lavar", "medida": "Capacidade de lavagem (kg)", "tamanhos": _sizes("kg", 6, 8, 10, 12, 15),
        "formas": [_label("kwh_ciclo", "kWh/ciclo", "Adesivo amarelo colado na máquina, na linha \"Consumo de energia\".",
                             "Ex.: 0,25", 5)]},
    "ar_condicionado": {
        "nome": "Ar-condicionado", "medida": "Capacidade (BTU/h)",
        "tamanhos": _sizes("BTU/h", 7500, 9000, 12000, 18000, 24000),
        "formas": [_nameplate("Etiqueta branca com o modelo, na lateral do aparelho (no split, na parte de dentro).",
                             "Ex.: 1100", 10000,
                             tip="Use a potência elétrica (consumida). Não use a capacidade de refrigeração, "
                                  "que é um número bem maior.")]},
    "televisor": {
        "nome": "Televisor", "medida": "Tamanho da tela (polegadas)",
        "tamanhos": _sizes("polegadas", 24, 32, 43, 50, 55, 65),
        "formas": [_nameplate("Etiqueta atrás da TV, com o modelo e a voltagem. Toda TV tem, até as antigas.",
                             "Ex.: 120", 1500),
                   _label("kwh_mes", "kWh/mês", "Adesivo amarelo, só nas TVs mais novas.", "Ex.: 9,9", 300)]},
    "ventilador_de_mesa": {
        "nome": "Ventilador de mesa, coluna ou parede", "medida": "Diâmetro da hélice (cm)",
        "tamanhos": _sizes("cm", 30, 40, 50),
        "formas": [_nameplate("Etiqueta embaixo da base ou atrás do motor, com a voltagem e a potência.",
                             "Ex.: 120", 500)]},
    "ventilador_de_teto": {
        "nome": "Ventilador de teto",
        "formas": [_nameplate("Etiqueta em cima do motor ou na caixa, com a voltagem e a potência.", "Ex.: 130", 500)]},
    "microondas": {
        "nome": "Micro-ondas", "medida": "Capacidade (litros)", "tamanhos": _sizes("litros", 20, 25, 30, 35),
        "formas": [_nameplate("Etiqueta atrás do aparelho ou na parte de dentro da porta.", "Ex.: 1300", 5000,
                             tip="Use a potência consumida (de entrada), que é a maior. A potência de saída, "
                                  "de cozimento, é menor.")]},
    "bomba": {
        "nome": "Bomba d'água", "medida": "Potência do motor (cv)",
        "tamanhos": [{"valor": v, "nome": n} for v, n in
                     ((0.25, "1/4 cv"), (0.33, "1/3 cv"), (0.5, "1/2 cv"), (0.75, "3/4 cv"), (1, "1 cv"), (1.5, "1,5 cv"))],
        "formas": [_nameplate("Placa de metal presa no motor.", "Ex.: 750", 20000,
                             tip="Se estiver em kW, multiplique por 1.000 (0,75 kW = 750 W).")]},
    "chuveiro": {
        "nome": "Chuveiro elétrico", "obrigatorio": True,
        "formas": [_nameplate("Na embalagem ou gravada no próprio chuveiro.", "Ex.: 5500", 12000,
                             tip="Use a potência da posição que você mais usa. A de inverno é a maior.")]},
    "lampada_led": {"nome": "Lâmpada LED", "obrigatorio": True,
                    "formas": [_nameplate("Escrita na própria lâmpada ou na caixa.", "Ex.: 9", 1000)]},
    "lampada_fluorescente": {"nome": "Lâmpada fluorescente", "obrigatorio": True,
                             "formas": [_nameplate("Escrita na própria lâmpada ou na caixa.", "Ex.: 20", 1000)]},
    "lampada_vapor_sodio": {"nome": "Lâmpada de vapor de sódio", "obrigatorio": True,
                            "formas": [_nameplate("Escrita na própria lâmpada ou na caixa.", "Ex.: 70", 1000)]},
}
# Nomes do Inmetro trocados por uma descricao que o usuario reconhece olhando o aparelho (na ordem da tela).
TYPE_NAMES = {
    "Top Load (automatica)": ("Automática que abre por cima", "Tampa em cima. Lava, enxágua e centrifuga sozinha."),
    "Semiautomaticas": ("Tanquinho ou semiautomática", "Lava, mas você tira a água ou muda a roupa de lugar."),
    "Front Load (automatica)": ("Automática que abre na frente", "Porta redonda na frente."),
    "Front Load (lava e seca)": ("Lava e seca", "Porta na frente. Também seca a roupa."),
    "Split Hi-Wall": ("Split de parede", "Aparelho comprido no alto da parede e uma caixa do lado de fora."),
    "Janela": ("De janela", "Uma caixa só, encaixada na parede ou na janela."),
    "Split Piso-teto": ("Split de piso-teto", "Aparelho grande preso no teto ou embaixo, na parede."),
    "Split Cassete": ("Split cassete", "Embutido no forro do teto, solta ar para os quatro lados."),
}
ESTIMATE_TOLERANCE = 0.10
ESTIMATE_EXPANSIONS = (1, 2, 4)
MIN_EQUIVALENTS = 5
MIN_QUARTILES = 4
EQUIVALENT_NOTICE = ("Gasto aproximado pelos modelos atuais parecidos do catálogo do Inmetro. Aparelhos antigos "
                      "costumam gastar mais que os atuais; com o valor da etiqueta o cálculo fica exato.")

# Onde nao sugerimos troca, e o motivo (aparece no app).
NO_SUGGESTION = {
    "chuveiro": ("Chuveiros elétricos têm eficiência parecida: um modelo de menor potência só esquenta "
                 "menos a água. Para economizar, reduza o tempo de banho ou use a posição verão."),
    "microondas": ("O Inmetro informa só a potência do micro-ondas. Um modelo de menor potência demora mais "
                   "para aquecer, então a economia não pode ser estimada só com esses dados."),
    "lampada_vapor_sodio": ("O catálogo de vapor de sódio não traz a luminosidade (lumens), então não dá "
                            "para achar uma lâmpada equivalente."),
}
# Uma sugestao precisa gastar pelo menos 5% menos que o aparelho atual.
MIN_SAVINGS = 0.05
# Consumo abaixo de 40% da mediana dos modelos equivalentes e tratado como erro de digitacao no
# Inmetro e nao e sugerido (ex.: HISENSE RS3P428NEDA = 28,0 kWh e a versao 127 V = 2,8 kWh).
SUSPECT_FRACTION = 0.4

CONVERTED_ORIGIN = "convertido da metodologia antiga do Inmetro"
CONVERTED_NOTICE = ("Este modelo só tem o consumo medido pela regra antiga do Inmetro (anterior a 2021); o valor foi "
                    "convertido para a regra atual para comparar com os modelos novos, então é aproximado.")

DEFAULT_NOTICE = ("Estimativa sem impostos (ICMS, PIS/COFINS), bandeira tarifária e iluminação "
                "pública. O uso real muda o resultado.")
# Com a tarifa da conta de luz, os impostos e a bandeira ja podem estar no valor digitado.
USER_TARIFF_NOTICE = ("Calculado com a tarifa que você informou. O uso real muda o resultado.")

# Cada spec diz quais colunas do CSV limpo viram cada campo do catalogo.
# "capacidade": (coluna, unidade) aparece na tela, ex.: "490 L".
SPECS = [
    {
        "arquivo": "refrigeradores-e-assemelhados_limpo.csv", "categoria": "refrigerador",
        "tipo": "tipo", "capacidade": ("volume_total_litros", "L"),
        "kwh_mes": ["consumo_medio_de_energia_mensal_kwh_mes"],
        "kwh_mes_metodologia_antiga": {"coluna": "consumo_de_energia_mensal_kwh_mes", "degelo": "sistema_de_degelo"},
    },
    {
        "arquivo": "televisores_limpo.csv", "categoria": "televisor",
        "tipo": "tipo", "capacidade": ("diagonal_em_polegadas", "pol"),
        "kwh_mes": ["consumo_kwh_mes"],
    },
    {
        "arquivo": "ar-condicionado_limpo.csv", "categoria": "ar_condicionado",
        "tipo": "tipo", "capacidade": ("capacidade_btu", "BTU/h"),
        "kwh_mes": ["consumo_anual_kwh"], "kwh_mes_div": 12,
        "potencia_w": ["potencia_w"],
        "derivado": lambda df: df["consumo_anual_de_energia_kwh"].isna(),
    },
    {
        "arquivo": "ventiladores_de_mesa_limpo.csv", "categoria": "ventilador_de_mesa",
        "tipo": "tipo_de_produto", "capacidade": ("diametro_da_helice_cm", "cm"),
        "velocidades": {
            "baixa": "consumo_de_energia_mensalkwh_mes_baixa",
            "media": "consumo_de_energia_mensalkwh_mes_media",
            "alta": "consumo_de_energia_mensalkwh_mes_alta",
        },
    },
    {
        "arquivo": "ventiladores_teto_limpo.csv", "categoria": "ventilador_de_teto",
        "capacidade": ("diametro_cm", "cm"),
        "velocidades": {
            "baixa": "consumo_de_energia_mensal_na_vel_baixa_kwh_mes",
            "media": "consumo_de_energia_mensal_na_vel_media_kwh_mes",
            "alta": "consumo_de_energia_mensal_na_vel_alta_kwh_mes",
        },
    },
    {
        "arquivo": "chuveiros_eletricos_limpo.csv", "categoria": "chuveiro",
        "tipo": "familia", "capacidade": ("potencia_w", "W"),
        # o consumo mensal da tabela do Inmetro depende de um tempo de banho padrao;
        # usamos a potencia e pedimos ao usuario o tempo de banho por dia
        "potencia_w": ["potencia_w"],
        "tensao": "tensao_v",  # versao 220 V costuma ter outra potencia (ver keep_voltage_versions)
    },
    {
        "arquivo": "lampadas_led_limpo.csv", "categoria": "lampada_led",
        "tipo": "tipo_de_lampada", "capacidade": ("potencia_w", "W"),
        "potencia_w": ["potencia_w"], "fluxo_lm": "fluxo_luminoso_lm",
    },
    {
        "arquivo": "lampadas_fluorescentes_limpo.csv", "categoria": "lampada_fluorescente",
        "tipo": "tipo_de_bulbo", "capacidade": ("potencia_w", "W"),
        "potencia_w": ["potencia_w"], "fluxo_lm": "fluxo_luminoso_lm",
    },
    {
        "arquivo": "lampadas_vapor_sodio_limpo.csv", "categoria": "lampada_vapor_sodio",
        "capacidade": ("potencia_w", "W"),
        "potencia_w": ["potencia_w"],
    },
    {
        "arquivo": "microondas_limpo.csv", "categoria": "microondas",
        "capacidade": ("volume_l", "L"),
        "potencia_w": ["potencia_nominal_w"],
        "standby_dia": "consumo_modo_espera_stand_by_kwh_dia",
        "tensao": "tensao_v",
    },
    {
        "arquivo": "maquinas-de-lavar_limpo.csv", "categoria": "maquina_de_lavar",
        "tipo": "tipo_de_lavadora", "capacidade": ("capacidade_de_lavagem_kg", "kg"),
        "kwh_ciclo": ["consumo_de_energia_kwh_ciclo_agua_fria"],
        "tensao": "tensao_v",
    },
    {
        "arquivo": "bombas-e-motobombas_limpo.csv", "categoria": "bomba",
        "tipo": "tipo_de_bomba", "capacidade": ("potencia_motor_cv", "cv"),
        # monofasico (uso residencial) primeiro; se faltar, trifasico
        "potencia_w": ["potencia_eletrica_consumida_1_w", "potencia_eletrica_consumida_3_w"],
    },
]

OUT_OF_SCOPE_FILES = {
    "aquecedores-de-agua-e-gas_limpo.csv": "consome gas, nao energia eletrica",
    "fornos-eletricos-comerciais_limpo.csv": "uso comercial e unidade do consumo nao confirmada",
    "sistemas-acoplados-equipamentos-solar-de-agua_limpo.csv": "gera economia de energia, nao consome",
}


def normalize(text):
    """Minusculo, sem acento, so letras, numeros e espaco."""
    text = unicodedata.normalize("NFKD", str(text)).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", " ", text).strip()


def _num(df, columns):
    """Primeira coluna numerica preenchida da lista (fallback na ordem)."""
    series = pd.Series(float("nan"), index=df.index)
    for column in columns:
        if column in df.columns:
            series = series.fillna(pd.to_numeric(df[column], errors="coerce"))
    return series


def _build(df, spec):
    out = pd.DataFrame(index=df.index)
    out["categoria"] = spec["categoria"]
    out["marca"] = df["marca"].astype(str).str.strip()
    out["modelo"] = df["modelo"].astype(str).str.strip()
    out["tipo"] = df[spec["tipo"]].fillna("").astype(str).str.strip() if spec.get("tipo") else ""
    if spec.get("tensao"):  # 127 ou 220 (texto); vazio = nao informada ou nao muda o consumo
        volts = pd.to_numeric(df[spec["tensao"]], errors="coerce")
        out["tensao"] = volts.map(lambda v: "" if pd.isna(v) else f"{v:g}")
    else:
        out["tensao"] = ""

    if spec.get("capacidade"):
        column, unit = spec["capacidade"]
        out["capacidade"] = _num(df, [column])
        out["unidade"] = unit
        out["detalhe"] = out["capacidade"].map(lambda v: "" if pd.isna(v) else f"{v:g} {unit}")
    else:
        out["capacidade"], out["unidade"], out["detalhe"] = float("nan"), None, ""

    for column in NUM_COLUMNS:
        out[column] = float("nan")
    if "kwh_mes" in spec:
        out["kwh_mes"] = _num(df, spec["kwh_mes"]) / spec.get("kwh_mes_div", 1)
    if "velocidades" in spec:
        for name, column in spec["velocidades"].items():
            out[f"kwh_mes_{name}"] = _num(df, [column])
        out["kwh_mes"] = out["kwh_mes_media"].fillna(out["kwh_mes_alta"]).fillna(out["kwh_mes_baixa"])
    if "kwh_ciclo" in spec:
        out["kwh_ciclo"] = _num(df, spec["kwh_ciclo"])
    if "potencia_w" in spec:
        out["potencia_w"] = _num(df, spec["potencia_w"])
    if "standby_dia" in spec:
        out["standby_kwh_mes"] = _num(df, [spec["standby_dia"]]) * DAYS_PER_MONTH
    if "fluxo_lm" in spec:  # lumens: usado para achar lampada equivalente
        out["fluxo_lm"] = _num(df, [spec["fluxo_lm"]])
        out.loc[out["fluxo_lm"] <= 0, "fluxo_lm"] = float("nan")
        with_lm = out["fluxo_lm"].notna()
        out.loc[with_lm, "detalhe"] = out.loc[with_lm, "detalhe"] + ", " + out.loc[with_lm, "fluxo_lm"].map("{:g} lm".format)

    out["origem_dado"] = "informado"
    if "kwh_mes_metodologia_antiga" in spec:
        _convert_old_methodology(df, out, spec["kwh_mes_metodologia_antiga"])
    if spec.get("derivado"):
        out.loc[spec["derivado"](df), "origem_dado"] = "derivado ou estimado na limpeza"
    if "consumo_imputado" in df.columns:  # marcado pelos scripts de limpeza
        imputed = df["consumo_imputado"].astype(str).str.lower().isin(["true", "1"])
        out.loc[imputed, "origem_dado"] = "derivado ou estimado na limpeza"
    out["arquivo"] = spec["arquivo"]

    # descarta linhas sem nenhum dado de consumo e valores impossiveis
    for column in NUM_COLUMNS:
        out.loc[out[column] <= 0, column] = float("nan")
    has_data = out[["kwh_mes", "kwh_ciclo", "potencia_w"]].notna().any(axis=1)
    return out[has_data & (out["marca"] != "") & (out["modelo"] != "")]


def _convert_old_methodology(df, out, rule):
    old = _num(df, [rule["coluna"]])
    missing = out["kwh_mes"].isna() & old.notna()
    if not missing.any():
        return
    frost_free = df[rule["degelo"]].fillna("").astype(str).str.contains("Frost")
    try:
        model = estimativa.load_model()
    except FileNotFoundError as error:
        print(f"[aviso] {error}; consumo da metodologia antiga usado sem conversao")
        out.loc[missing, "kwh_mes"] = old[missing]
        return
    factor = pd.Series([estimativa.methodology_factor(t, f, model) for t, f in zip(out["tipo"], frost_free)],
                      index=out.index)
    out.loc[missing, "kwh_mes"] = old[missing] * factor[missing]
    out.loc[missing, "origem_dado"] = CONVERTED_ORIGIN


def load_catalog(folder=None):
    """Junta todos os CSVs limpos num catalogo unico de aparelhos."""
    folder = folder or config.DATA
    parts = []
    for spec in SPECS:
        path = folder / spec["arquivo"]
        if not path.exists():
            print(f"[aviso] {spec['arquivo']} nao encontrado, categoria {spec['categoria']} fica de fora")
            continue
        df = pd.read_csv(path, encoding="utf-8-sig")
        try:
            parts.append(_build(df, spec))
        except KeyError as error:
            print(f"[aviso] {spec['arquivo']}: coluna {error} nao existe, arquivo ignorado")
    if not parts:
        raise FileNotFoundError(f"nenhum dataset carregado em {folder}")
    catalog = keep_voltage_versions(pd.concat(parts, ignore_index=True))
    catalog["busca"] = (catalog["marca"] + " " + catalog["modelo"]).map(normalize)
    return catalog.reset_index(drop=True)


# Colunas que mudam o calculo: se diferem entre a versao 127 V e a 220 V, as duas ficam no catalogo.
VOLTAGE_CONSUMPTION = ["kwh_mes", "kwh_ciclo", "potencia_w", "standby_kwh_mes"]


def keep_voltage_versions(catalog):
    """Um modelo por linha, como antes, menos quando a versao de outra tensao gasta diferente.

    Antes ficava so a 1a linha de cada marca + modelo, e o chuveiro de 220 V sumia: ele costuma ter outra
    potencia (ex.: Cardal Ducha 5 Luxo, 5500 W em 127 V e 7600 W em 220 V) e o catalogo ficava com a de 127 V
    em 77 de 84 modelos. Agora cada tensao vira uma linha, com "220 V" no detalhe, para a pessoa escolher a do
    aparelho dela. Quando o consumo e igual nas duas, fica uma linha so e a tensao fica vazia (vale para as duas).
    Modelo vendido numa tensao so guarda essa tensao (e mostra no detalhe): a troca nao sugere a quem tem 127 V
    uma maquina que so existe em 220 V.
    """
    key = ["categoria", "marca", "modelo"]
    versions = catalog.drop_duplicates(subset=key + ["tensao"], keep="first")
    signature = versions[VOLTAGE_CONSUMPTION].round(4).fillna(-1).astype(str).agg("|".join, axis=1)
    differs = (signature.groupby([versions[k] for k in key]).transform("nunique") > 1) & (versions["tensao"] != "")
    split = versions[differs].copy()
    split["detalhe"] = [f"{d} · {v} V" if d else f"{v} V" for d, v in zip(split["detalhe"], split["tensao"])]
    single = catalog[~catalog.set_index(key).index.isin(split.set_index(key).index)]
    single = single.drop_duplicates(subset=key, keep="first")
    volts_per_model = catalog[catalog["tensao"] != ""].groupby(key)["tensao"].nunique()
    only_one = single.set_index(key).index.map(lambda k: volts_per_model.get(k, 0) == 1)
    single = single.assign(tensao=single["tensao"].where(only_one, ""))
    shown = single["tensao"] != ""
    single.loc[shown, "detalhe"] = [f"{d} · {v} V" if d else f"{v} V"
                                    for d, v in zip(single.loc[shown, "detalhe"], single.loc[shown, "tensao"])]
    return pd.concat([single, split]).sort_index()


def monthly_consumption_kwh(appliance, daily_hours=None, monthly_cycles=None, speed=None, days_per_month=None):
    """Consumo em kWh/mes e como foi calculado. Ordem: tabela > ciclos > potencia x horas.
    days_per_month: dias de uso no mes, so nas categorias de ASK_DAYS (nas outras e ignorado; vazio = 30)."""
    assumption = ASSUMPTIONS.get(appliance["categoria"], {})
    reference = INMETRO_REFERENCE_HOURS.get(appliance["categoria"])
    if daily_hours is not None and not 0 <= daily_hours <= 24:
        raise ValueError(tr("horas por dia precisa estar entre 0 e 24", "hours per day must be between 0 and 24"))
    if appliance["categoria"] not in ASK_DAYS:
        days_per_month = None
    if days_per_month is not None and not 1 <= days_per_month <= 31:
        raise ValueError(tr("os dias de uso no mês precisam estar entre 1 e 31",
                            "days of use per month must be between 1 and 31"))
    days = DAYS_PER_MONTH if days_per_month is None else days_per_month
    given = tr("informado", "entered")
    adjustment = tr("informe as horas de uso para ajustar", "enter the hours of use to adjust")

    if speed and pd.notna(appliance.get(f"kwh_mes_{speed}")):
        kwh = float(appliance[f"kwh_mes_{speed}"])
        name = tr(SPEED_NAMES.get(speed, speed), SPEED_NAMES_EN.get(speed, speed))
        if daily_hours is not None and reference:
            return {"kwh_mes": kwh * daily_hours / reference,
                    "metodo": tr(f"consumo do Inmetro na velocidade {name} ({kwh:g} kWh/mês para "
                                 f"{time_per_day(reference)}) ajustado para {time_per_day(daily_hours)} (informado)",
                                 f"Inmetro consumption at {name} speed ({kwh:g} kWh/month for "
                                 f"{time_per_day(reference)}) adjusted to {time_per_day(daily_hours)} (entered)"),
                    "premissa": False}
        method = tr(f"consumo mensal do Inmetro, velocidade {name}", f"Inmetro monthly consumption, {name} speed")
        if reference:
            method += tr(f" ({time_per_day(reference)} no ensaio; {adjustment})",
                         f" ({time_per_day(reference)} in the test; {adjustment})")
        return {"kwh_mes": kwh, "metodo": method, "premissa": False}

    if daily_hours is not None and (appliance["categoria"] in OPTIONAL_HOURS or reference):
        if appliance["categoria"] == "ar_condicionado" and pd.notna(appliance["potencia_w"]):
            return {"kwh_mes": float(appliance["potencia_w"]) * daily_hours * days / 1000,
                    "metodo": tr(f"{appliance['potencia_w']:g} W (potência em carga total) x "
                                 f"{time_per_day(daily_hours)} x {days:g} dias (informado); valor máximo, "
                                 "o compressor não fica ligado o tempo todo",
                                 f"{appliance['potencia_w']:g} W (power at full load) x "
                                 f"{time_per_day(daily_hours)} x {days:g} days (entered); maximum value, "
                                 "the compressor is not on all the time"),
                    "premissa": False}
        if reference and pd.notna(appliance["kwh_mes"]):
            return {"kwh_mes": float(appliance["kwh_mes"]) * daily_hours / reference,
                    "metodo": tr(f"consumo mensal do Inmetro ({appliance['kwh_mes']:g} kWh para {reference:g} h/dia) "
                                 f"ajustado para {time_per_day(daily_hours)} (informado)",
                                 f"Inmetro monthly consumption ({appliance['kwh_mes']:g} kWh for {reference:g} h/day) "
                                 f"adjusted to {time_per_day(daily_hours)} (entered)"),
                    "premissa": False}

    if pd.notna(appliance["kwh_mes"]):
        method = tr("consumo mensal do Inmetro", "Inmetro monthly consumption")
        if reference:
            method += tr(f" ({time_per_day(reference)} no ensaio; {adjustment})",
                         f" ({time_per_day(reference)} in the test; {adjustment})")
        elif appliance["categoria"] in OPTIONAL_HOURS:
            method += tr(f" (uso padrão do ensaio; {adjustment})", f" (standard test use; {adjustment})")
        kwh = float(appliance["kwh_mes"])
        if days_per_month is not None:
            kwh *= days_per_month / DAYS_PER_MONTH
            method += tr(f", ajustado para {days_per_month:g} dias de uso no mês (informado)",
                         f", adjusted to {days_per_month:g} days of use per month (entered)")
        return {"kwh_mes": kwh, "metodo": method, "premissa": False}

    if pd.notna(appliance["kwh_ciclo"]):
        cycles = monthly_cycles if monthly_cycles is not None else assumption.get("ciclos_mes")
        if cycles is None:
            raise ValueError(tr("informe quantos ciclos por mês", "enter how many cycles per month"))
        if cycles < 0:
            raise ValueError(tr("ciclos por mês não pode ser negativo", "cycles per month cannot be negative"))
        origin = given if monthly_cycles is not None else tr("estimativa do grupo", "group estimate")
        return {"kwh_mes": float(appliance["kwh_ciclo"]) * cycles,
                "metodo": tr(f"{appliance['kwh_ciclo']:g} kWh por ciclo x {cycles:g} ciclos por mês ({origin})",
                             f"{appliance['kwh_ciclo']:g} kWh per cycle x {cycles:g} cycles per month ({origin})"),
                "premissa": monthly_cycles is None}

    if pd.notna(appliance["potencia_w"]):
        hours = daily_hours if daily_hours is not None else assumption.get("horas_dia")
        if hours is None:
            raise ValueError(tr("informe quantas horas por dia o aparelho fica ligado",
                                "enter how many hours per day the appliance is on"))
        if not 0 <= hours <= 24:
            raise ValueError(tr("horas por dia precisa estar entre 0 e 24", "hours per day must be between 0 and 24"))
        standby = appliance.get("standby_kwh_mes")
        standby = 0.0 if pd.isna(standby) else float(standby)
        origin = given if daily_hours is not None else tr("estimativa do grupo", "group estimate")
        method = tr(f"{appliance['potencia_w']:g} W x {time_per_day(hours)} x {days:g} dias ({origin})",
                    f"{appliance['potencia_w']:g} W x {time_per_day(hours)} x {days:g} days ({origin})")
        if standby:
            method += tr(f" + {standby:.2f} kWh de stand-by", f" + {standby:.2f} kWh of standby")
        return {"kwh_mes": float(appliance["potencia_w"]) * hours * days / 1000 + standby,
                "metodo": method, "premissa": daily_hours is None}

    raise ValueError(tr("aparelho sem dados de consumo", "appliance without consumption data"))


def build_result(appliance, consumption, tariff_kwh, distributor, tariff_origin, uf, daily_hours=None,
                     user_tariff=False):
    """Dicionario final que a tela mostra e que vai para a tabela consultas."""
    monthly_cost = consumption["kwh_mes"] * tariff_kwh
    notices = [t(USER_TARIFF_NOTICE if user_tariff else DEFAULT_NOTICE)]
    if consumption.get("premissa"):
        notices.append(tr("O tempo de uso é uma estimativa do grupo. Informe o seu para um valor mais preciso.",
                         "The time of use is an estimate made by our team. Enter yours for a more accurate value."))
    if appliance.get("origem_dado") == CONVERTED_ORIGIN:
        notices.append(t(CONVERTED_NOTICE))
    elif appliance.get("origem_dado") not in (None, "informado"):
        notices.append(tr("O consumo deste modelo foi completado na limpeza dos dados (não veio do Inmetro).",
                         "This model's consumption was filled in during data cleaning (it did not come from Inmetro)."))
    detail = appliance.get("detalhe")
    return {
        "categoria": appliance["categoria"],
        "marca": appliance["marca"],
        "modelo": appliance["modelo"],
        "detalhe": "" if detail is None or pd.isna(detail) else units(detail),
        "distribuidora": distributor or "-",
        "uf": uf if isinstance(uf, str) and uf else "-",
        "horas_dia": daily_hours,
        "kwh_mes": round(consumption["kwh_mes"], 2),
        "metodo": consumption["metodo"],
        "tarifa_kwh": round(float(tariff_kwh), 5),
        "origem_tarifa": tariff_origin,
        "custo_mes": round(monthly_cost, 2),
        "custo_ano": round(monthly_cost * 12, 2),
        "avisos": notices,
    }
