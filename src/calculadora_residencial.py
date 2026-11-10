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
from estimativa import tempo_por_dia

DIAS_MES = 30
LIMITE_BUSCA = 15  # modelos por tipo de aparelho na busca (uma marca pode ter varios tipos)
LIMITE_MODELOS_MARCA = 50  # modelos de uma marca na lista de marcas do app (o resto: digitar o modelo)

# Padroes de uso para aparelhos em que o Inmetro so informa potencia ou consumo por ciclo.
# ATENCAO: valores escolhidos pelo grupo, ainda sem fonte. O app mostra como "estimativa"
# e deixa o usuario trocar. Aparelho sem padrao aqui (ex.: chuveiro) obriga o usuario a informar.
PREMISSAS = {
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
HORAS_REFERENCIA_INMETRO = {"televisor": 6.59, "ventilador_de_mesa": 1.0, "ventilador_de_teto": 1.0}
HORAS_OPCIONAIS = {"ar_condicionado", "televisor"}
NOMES_VELOCIDADES = {"baixa": "baixa", "media": "média", "alta": "alta"}

COLUNAS_NUM = [
    "kwh_mes", "kwh_mes_baixa", "kwh_mes_media", "kwh_mes_alta",
    "kwh_ciclo", "potencia_w", "standby_kwh_mes", "fluxo_lm",
]

# Sugestao de aparelho mais economico: so comparamos modelos que fazem o mesmo servico.
#  - categorias: onde procurar (fluorescente -> LED e permitido, as duas tem lumens)
#  - medida: coluna que precisa ser parecida (capacidade = litros, polegadas, BTU/h, kg, cm ou cv)
#  - tolerancia: diferenca maxima da medida (0.15 = 15% para mais ou para menos)
#  - mesmo_tipo: exige o mesmo tipo (so onde o tipo vem padronizado no Inmetro)
EQUIVALENCIA = {
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


def _etiqueta(campo, unidade, onde, exemplo, maximo):
    return {"campo": campo, "nome": "Etiqueta amarela do Inmetro", "rotulo": "Consumo de energia",
            "unidade": unidade, "onde": onde, "dica": None, "exemplo": exemplo, "maximo": maximo}


def _plaqueta(onde, exemplo, maximo, dica=None):
    return {"campo": "potencia_w", "nome": "Potência escrita no aparelho", "rotulo": "Potência",
            "unidade": "W", "onde": onde, "dica": dica, "exemplo": exemplo, "maximo": maximo}


def _tamanhos(unidade, *valores):
    return [{"valor": v, "nome": f"{v:,} {unidade}".replace(",", ".")} for v in valores]


# Aparelho fora do catalogo (antigo ou sem modelo). O usuario informa o numero do proprio aparelho
# (formas: etiqueta do Inmetro ou potencia da plaqueta, que vale tambem para aparelho antigo) ou,
# sem ele, o tipo e o tamanho, e o gasto sai da mediana dos modelos parecidos do catalogo.
#  - ar-condicionado e ventiladores: sem etiqueta. A do ar mudou de kWh/mes para kWh/ano em 2023 e a do
#    ventilador e de 1 h por dia; a potencia da plaqueta x horas evita essa confusao.
#  - ventilador de teto: sem tamanho (o diametro do catalogo tem erros e ninguem sabe o seu de cabeca).
#  - obrigatorio: sem catalogo para comparar, o usuario precisa informar a potencia.
ESTIMAVEIS = {
    "refrigerador": {"nome": "Geladeira ou freezer", "especial": True},
    "maquina_de_lavar": {
        "nome": "Máquina de lavar", "medida": "Capacidade de lavagem (kg)", "tamanhos": _tamanhos("kg", 6, 8, 10, 12, 15),
        "formas": [_etiqueta("kwh_ciclo", "kWh/ciclo", "Adesivo amarelo colado na máquina, na linha \"Consumo de energia\".",
                             "Ex.: 0,25", 5)]},
    "ar_condicionado": {
        "nome": "Ar-condicionado", "medida": "Capacidade (BTU/h)",
        "tamanhos": _tamanhos("BTU/h", 7500, 9000, 12000, 18000, 24000),
        "formas": [_plaqueta("Etiqueta branca com o modelo, na lateral do aparelho (no split, na parte de dentro).",
                             "Ex.: 1100", 10000,
                             dica="Use a potência elétrica (consumida). Não use a capacidade de refrigeração, "
                                  "que é um número bem maior.")]},
    "televisor": {
        "nome": "Televisor", "medida": "Tamanho da tela (polegadas)",
        "tamanhos": _tamanhos("polegadas", 24, 32, 43, 50, 55, 65),
        "formas": [_plaqueta("Etiqueta atrás da TV, com o modelo e a voltagem. Toda TV tem, até as antigas.",
                             "Ex.: 120", 1500),
                   _etiqueta("kwh_mes", "kWh/mês", "Adesivo amarelo, só nas TVs mais novas.", "Ex.: 9,9", 300)]},
    "ventilador_de_mesa": {
        "nome": "Ventilador de mesa, coluna ou parede", "medida": "Diâmetro da hélice (cm)",
        "tamanhos": _tamanhos("cm", 30, 40, 50),
        "formas": [_plaqueta("Etiqueta embaixo da base ou atrás do motor, com a voltagem e a potência.",
                             "Ex.: 120", 500)]},
    "ventilador_de_teto": {
        "nome": "Ventilador de teto",
        "formas": [_plaqueta("Etiqueta em cima do motor ou na caixa, com a voltagem e a potência.", "Ex.: 130", 500)]},
    "microondas": {
        "nome": "Micro-ondas", "medida": "Capacidade (litros)", "tamanhos": _tamanhos("litros", 20, 25, 30, 35),
        "formas": [_plaqueta("Etiqueta atrás do aparelho ou na parte de dentro da porta.", "Ex.: 1300", 5000,
                             dica="Use a potência consumida (de entrada), que é a maior. A potência de saída, "
                                  "de cozimento, é menor.")]},
    "bomba": {
        "nome": "Bomba d'água", "medida": "Potência do motor (cv)",
        "tamanhos": [{"valor": v, "nome": n} for v, n in
                     ((0.25, "1/4 cv"), (0.33, "1/3 cv"), (0.5, "1/2 cv"), (0.75, "3/4 cv"), (1, "1 cv"), (1.5, "1,5 cv"))],
        "formas": [_plaqueta("Placa de metal presa no motor.", "Ex.: 750", 20000,
                             dica="Se estiver em kW, multiplique por 1.000 (0,75 kW = 750 W).")]},
    "chuveiro": {
        "nome": "Chuveiro elétrico", "obrigatorio": True,
        "formas": [_plaqueta("Na embalagem ou gravada no próprio chuveiro.", "Ex.: 5500", 12000,
                             dica="Use a potência da posição que você mais usa. A de inverno é a maior.")]},
    "lampada_led": {"nome": "Lâmpada LED", "obrigatorio": True,
                    "formas": [_plaqueta("Escrita na própria lâmpada ou na caixa.", "Ex.: 9", 1000)]},
    "lampada_fluorescente": {"nome": "Lâmpada fluorescente", "obrigatorio": True,
                             "formas": [_plaqueta("Escrita na própria lâmpada ou na caixa.", "Ex.: 20", 1000)]},
    "lampada_vapor_sodio": {"nome": "Lâmpada de vapor de sódio", "obrigatorio": True,
                            "formas": [_plaqueta("Escrita na própria lâmpada ou na caixa.", "Ex.: 70", 1000)]},
}
# Nomes do Inmetro trocados por uma descricao que o usuario reconhece olhando o aparelho (na ordem da tela).
NOMES_DOS_TIPOS = {
    "Top Load (automatica)": ("Automática que abre por cima", "Tampa em cima. Lava, enxágua e centrifuga sozinha."),
    "Semiautomaticas": ("Tanquinho ou semiautomática", "Lava, mas você tira a água ou muda a roupa de lugar."),
    "Front Load (automatica)": ("Automática que abre na frente", "Porta redonda na frente."),
    "Front Load (lava e seca)": ("Lava e seca", "Porta na frente. Também seca a roupa."),
    "Split Hi-Wall": ("Split de parede", "Aparelho comprido no alto da parede e uma caixa do lado de fora."),
    "Janela": ("De janela", "Uma caixa só, encaixada na parede ou na janela."),
    "Split Piso-teto": ("Split de piso-teto", "Aparelho grande preso no teto ou embaixo, na parede."),
    "Split Cassete": ("Split cassete", "Embutido no forro do teto, solta ar para os quatro lados."),
}
TOLERANCIA_ESTIMATIVA = 0.10
AMPLIACOES_ESTIMATIVA = (1, 2, 4)
MINIMO_EQUIVALENTES = 5
MINIMO_QUARTIS = 4
AVISO_EQUIVALENTES = ("Gasto aproximado pelos modelos atuais parecidos do catálogo do Inmetro. Aparelhos antigos "
                      "costumam gastar mais que os atuais; com o valor da etiqueta o cálculo fica exato.")

# Onde nao sugerimos troca, e o motivo (aparece no app).
SEM_SUGESTAO = {
    "chuveiro": ("Chuveiros elétricos têm eficiência parecida: um modelo de menor potência só esquenta "
                 "menos a água. Para economizar, reduza o tempo de banho ou use a posição verão."),
    "microondas": ("O Inmetro informa só a potência do micro-ondas. Um modelo de menor potência demora mais "
                   "para aquecer, então a economia não pode ser estimada só com esses dados."),
    "lampada_vapor_sodio": ("O catálogo de vapor de sódio não traz a luminosidade (lumens), então não dá "
                            "para achar uma lâmpada equivalente."),
}
# Uma sugestao precisa gastar pelo menos 5% menos que o aparelho atual.
ECONOMIA_MINIMA = 0.05
# Consumo abaixo de 40% da mediana dos modelos equivalentes e tratado como erro de digitacao no
# Inmetro e nao e sugerido (ex.: HISENSE RS3P428NEDA = 28,0 kWh e a versao 127 V = 2,8 kWh).
FRACAO_SUSPEITA = 0.4

ORIGEM_CONVERTIDA = "convertido da metodologia antiga do Inmetro"
AVISO_CONVERTIDO = ("Este modelo so tem o consumo medido pela regra antiga do Inmetro (anterior a 2021); o valor foi "
                    "convertido para a regra atual para comparar com os modelos novos, entao e aproximado.")

AVISO_PADRAO = ("Estimativa sem impostos (ICMS, PIS/COFINS), bandeira tarifária e iluminação "
                "pública. O uso real muda o resultado.")
# Com a tarifa da conta de luz, os impostos e a bandeira ja podem estar no valor digitado.
AVISO_TARIFA_USUARIO = ("Calculado com a tarifa que voce informou. O uso real muda o resultado.")

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
    },
    {
        "arquivo": "maquinas-de-lavar_limpo.csv", "categoria": "maquina_de_lavar",
        "tipo": "tipo_de_lavadora", "capacidade": ("capacidade_de_lavagem_kg", "kg"),
        "kwh_ciclo": ["consumo_de_energia_kwh_ciclo_agua_fria"],
    },
    {
        "arquivo": "bombas-e-motobombas_limpo.csv", "categoria": "bomba",
        "tipo": "tipo_de_bomba", "capacidade": ("potencia_motor_cv", "cv"),
        # monofasico (uso residencial) primeiro; se faltar, trifasico
        "potencia_w": ["potencia_eletrica_consumida_1_w", "potencia_eletrica_consumida_3_w"],
    },
]

ARQUIVOS_FORA_DO_ESCOPO = {
    "aquecedores-de-agua-e-gas_limpo.csv": "consome gas, nao energia eletrica",
    "fornos-eletricos-comerciais_limpo.csv": "uso comercial e unidade do consumo nao confirmada",
    "sistemas-acoplados-equipamentos-solar-de-agua_limpo.csv": "gera economia de energia, nao consome",
}


def normalizar(texto):
    """Minusculo, sem acento, so letras, numeros e espaco."""
    texto = unicodedata.normalize("NFKD", str(texto)).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", " ", texto).strip()


def _num(df, colunas):
    """Primeira coluna numerica preenchida da lista (fallback na ordem)."""
    serie = pd.Series(float("nan"), index=df.index)
    for coluna in colunas:
        if coluna in df.columns:
            serie = serie.fillna(pd.to_numeric(df[coluna], errors="coerce"))
    return serie


def _construir(df, spec):
    out = pd.DataFrame(index=df.index)
    out["categoria"] = spec["categoria"]
    out["marca"] = df["marca"].astype(str).str.strip()
    out["modelo"] = df["modelo"].astype(str).str.strip()
    out["tipo"] = df[spec["tipo"]].fillna("").astype(str).str.strip() if spec.get("tipo") else ""

    if spec.get("capacidade"):
        coluna, unidade = spec["capacidade"]
        out["capacidade"] = _num(df, [coluna])
        out["unidade"] = unidade
        out["detalhe"] = out["capacidade"].map(lambda v: "" if pd.isna(v) else f"{v:g} {unidade}")
    else:
        out["capacidade"], out["unidade"], out["detalhe"] = float("nan"), None, ""

    for coluna in COLUNAS_NUM:
        out[coluna] = float("nan")
    if "kwh_mes" in spec:
        out["kwh_mes"] = _num(df, spec["kwh_mes"]) / spec.get("kwh_mes_div", 1)
    if "velocidades" in spec:
        for nome, coluna in spec["velocidades"].items():
            out[f"kwh_mes_{nome}"] = _num(df, [coluna])
        out["kwh_mes"] = out["kwh_mes_media"].fillna(out["kwh_mes_alta"]).fillna(out["kwh_mes_baixa"])
    if "kwh_ciclo" in spec:
        out["kwh_ciclo"] = _num(df, spec["kwh_ciclo"])
    if "potencia_w" in spec:
        out["potencia_w"] = _num(df, spec["potencia_w"])
    if "standby_dia" in spec:
        out["standby_kwh_mes"] = _num(df, [spec["standby_dia"]]) * DIAS_MES
    if "fluxo_lm" in spec:  # lumens: usado para achar lampada equivalente
        out["fluxo_lm"] = _num(df, [spec["fluxo_lm"]])
        out.loc[out["fluxo_lm"] <= 0, "fluxo_lm"] = float("nan")
        com_lm = out["fluxo_lm"].notna()
        out.loc[com_lm, "detalhe"] = out.loc[com_lm, "detalhe"] + ", " + out.loc[com_lm, "fluxo_lm"].map("{:g} lm".format)

    out["origem_dado"] = "informado"
    if "kwh_mes_metodologia_antiga" in spec:
        _converter_metodologia_antiga(df, out, spec["kwh_mes_metodologia_antiga"])
    if spec.get("derivado"):
        out.loc[spec["derivado"](df), "origem_dado"] = "derivado ou estimado na limpeza"
    if "consumo_imputado" in df.columns:  # marcado pelos scripts de limpeza
        imputado = df["consumo_imputado"].astype(str).str.lower().isin(["true", "1"])
        out.loc[imputado, "origem_dado"] = "derivado ou estimado na limpeza"
    out["arquivo"] = spec["arquivo"]

    # descarta linhas sem nenhum dado de consumo e valores impossiveis
    for coluna in COLUNAS_NUM:
        out.loc[out[coluna] <= 0, coluna] = float("nan")
    tem_dado = out[["kwh_mes", "kwh_ciclo", "potencia_w"]].notna().any(axis=1)
    return out[tem_dado & (out["marca"] != "") & (out["modelo"] != "")]


def _converter_metodologia_antiga(df, out, regra):
    antigo = _num(df, [regra["coluna"]])
    falta = out["kwh_mes"].isna() & antigo.notna()
    if not falta.any():
        return
    frost_free = df[regra["degelo"]].fillna("").astype(str).str.contains("Frost")
    try:
        modelo = estimativa.carregar_modelo()
    except FileNotFoundError as erro:
        print(f"[aviso] {erro}; consumo da metodologia antiga usado sem conversao")
        out.loc[falta, "kwh_mes"] = antigo[falta]
        return
    fator = pd.Series([estimativa.fator_metodologia(t, f, modelo) for t, f in zip(out["tipo"], frost_free)],
                      index=out.index)
    out.loc[falta, "kwh_mes"] = antigo[falta] * fator[falta]
    out.loc[falta, "origem_dado"] = ORIGEM_CONVERTIDA


def carregar_catalogo(pasta=None):
    """Junta todos os CSVs limpos num catalogo unico de aparelhos."""
    pasta = pasta or config.DADOS
    partes = []
    for spec in SPECS:
        caminho = pasta / spec["arquivo"]
        if not caminho.exists():
            print(f"[aviso] {spec['arquivo']} nao encontrado, categoria {spec['categoria']} fica de fora")
            continue
        df = pd.read_csv(caminho, encoding="utf-8-sig")
        try:
            partes.append(_construir(df, spec))
        except KeyError as erro:
            print(f"[aviso] {spec['arquivo']}: coluna {erro} nao existe, arquivo ignorado")
    if not partes:
        raise FileNotFoundError(f"nenhum dataset carregado em {pasta}")
    catalogo = pd.concat(partes, ignore_index=True)
    catalogo = catalogo.drop_duplicates(subset=["categoria", "marca", "modelo"], keep="first")
    catalogo["busca"] = (catalogo["marca"] + " " + catalogo["modelo"]).map(normalizar)
    return catalogo.reset_index(drop=True)


def consumo_mensal_kwh(aparelho, horas_dia=None, ciclos_mes=None, velocidade=None, dias=DIAS_MES):
    """Consumo em kWh/mes e como foi calculado. Ordem: tabela > ciclos > potencia x horas."""
    premissa = PREMISSAS.get(aparelho["categoria"], {})
    referencia = HORAS_REFERENCIA_INMETRO.get(aparelho["categoria"])
    if horas_dia is not None and not 0 <= horas_dia <= 24:
        raise ValueError("horas por dia precisa estar entre 0 e 24")

    if velocidade and pd.notna(aparelho.get(f"kwh_mes_{velocidade}")):
        kwh = float(aparelho[f"kwh_mes_{velocidade}"])
        nome = NOMES_VELOCIDADES.get(velocidade, velocidade)
        if horas_dia is not None and referencia:
            return {"kwh_mes": kwh * horas_dia / referencia,
                    "metodo": (f"consumo do Inmetro na velocidade {nome} ({kwh:g} kWh/mês para "
                               f"{tempo_por_dia(referencia)}) ajustado para {tempo_por_dia(horas_dia)} (informado)"),
                    "premissa": False}
        metodo = f"consumo mensal do Inmetro, velocidade {nome}"
        if referencia:
            metodo += f" ({tempo_por_dia(referencia)} no ensaio; informe as horas de uso para ajustar)"
        return {"kwh_mes": kwh, "metodo": metodo, "premissa": False}

    if horas_dia is not None and (aparelho["categoria"] in HORAS_OPCIONAIS or referencia):
        if aparelho["categoria"] == "ar_condicionado" and pd.notna(aparelho["potencia_w"]):
            return {"kwh_mes": float(aparelho["potencia_w"]) * horas_dia * dias / 1000,
                    "metodo": (f"{aparelho['potencia_w']:g} W (potência em carga total) x "
                               f"{tempo_por_dia(horas_dia)} x {dias} dias (informado); valor máximo, "
                               "o compressor não fica ligado o tempo todo"),
                    "premissa": False}
        if referencia and pd.notna(aparelho["kwh_mes"]):
            return {"kwh_mes": float(aparelho["kwh_mes"]) * horas_dia / referencia,
                    "metodo": (f"consumo mensal do Inmetro ({aparelho['kwh_mes']:g} kWh para {referencia:g} h/dia) "
                               f"ajustado para {tempo_por_dia(horas_dia)} (informado)"),
                    "premissa": False}

    if pd.notna(aparelho["kwh_mes"]):
        metodo = "consumo mensal do Inmetro"
        if referencia:
            metodo += f" ({tempo_por_dia(referencia)} no ensaio; informe as horas de uso para ajustar)"
        elif aparelho["categoria"] in HORAS_OPCIONAIS:
            metodo += " (uso padrão do ensaio; informe as horas de uso para ajustar)"
        return {"kwh_mes": float(aparelho["kwh_mes"]), "metodo": metodo, "premissa": False}

    if pd.notna(aparelho["kwh_ciclo"]):
        ciclos = ciclos_mes if ciclos_mes is not None else premissa.get("ciclos_mes")
        if ciclos is None:
            raise ValueError("informe quantos ciclos por mes")
        if ciclos < 0:
            raise ValueError("ciclos por mes nao pode ser negativo")
        origem = "informado" if ciclos_mes is not None else "estimativa do grupo"
        return {"kwh_mes": float(aparelho["kwh_ciclo"]) * ciclos,
                "metodo": f"{aparelho['kwh_ciclo']:g} kWh por ciclo x {ciclos:g} ciclos por mês ({origem})",
                "premissa": ciclos_mes is None}

    if pd.notna(aparelho["potencia_w"]):
        horas = horas_dia if horas_dia is not None else premissa.get("horas_dia")
        if horas is None:
            raise ValueError("informe quantas horas por dia o aparelho fica ligado")
        if not 0 <= horas <= 24:
            raise ValueError("horas por dia precisa estar entre 0 e 24")
        standby = aparelho.get("standby_kwh_mes")
        standby = 0.0 if pd.isna(standby) else float(standby)
        origem = "informado" if horas_dia is not None else "estimativa do grupo"
        metodo = f"{aparelho['potencia_w']:g} W x {tempo_por_dia(horas)} x {dias} dias ({origem})"
        if standby:
            metodo += f" + {standby:.2f} kWh de stand-by"
        return {"kwh_mes": float(aparelho["potencia_w"]) * horas * dias / 1000 + standby,
                "metodo": metodo, "premissa": horas_dia is None}

    raise ValueError("aparelho sem dados de consumo")


def montar_resultado(aparelho, consumo, tarifa_kwh, distribuidora, origem_tarifa, uf, horas_dia=None,
                     tarifa_do_usuario=False):
    """Dicionario final que a tela mostra e que vai para a tabela consultas."""
    custo_mes = consumo["kwh_mes"] * tarifa_kwh
    avisos = [AVISO_TARIFA_USUARIO if tarifa_do_usuario else AVISO_PADRAO]
    if consumo.get("premissa"):
        avisos.append("O tempo de uso e uma estimativa do grupo. Informe o seu para um valor mais preciso.")
    if aparelho.get("origem_dado") == ORIGEM_CONVERTIDA:
        avisos.append(AVISO_CONVERTIDO)
    elif aparelho.get("origem_dado") not in (None, "informado"):
        avisos.append("O consumo deste modelo foi completado na limpeza dos dados (nao veio do Inmetro).")
    detalhe = aparelho.get("detalhe")
    return {
        "categoria": aparelho["categoria"],
        "marca": aparelho["marca"],
        "modelo": aparelho["modelo"],
        "detalhe": "" if detalhe is None or pd.isna(detalhe) else detalhe,
        "distribuidora": distribuidora or "-",
        "uf": uf if isinstance(uf, str) and uf else "-",
        "horas_dia": horas_dia,
        "kwh_mes": round(consumo["kwh_mes"], 2),
        "metodo": consumo["metodo"],
        "tarifa_kwh": round(float(tarifa_kwh), 5),
        "origem_tarifa": origem_tarifa,
        "custo_mes": round(custo_mes, 2),
        "custo_ano": round(custo_mes * 12, 2),
        "avisos": avisos,
    }
