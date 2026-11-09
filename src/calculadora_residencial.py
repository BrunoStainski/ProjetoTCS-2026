"""
Regras de calculo do iamp: catalogo de aparelhos, consumo mensal e custo.

Usado por criar_banco.py (monta o catalogo a partir dos CSVs limpos) e por
servico.py (calcula o consumo e monta o resultado para a tela).
"""

import re
import unicodedata

import pandas as pd

import config

DIAS_MES = 30
LIMITE_BUSCA = 15  # modelos por tipo de aparelho na busca (uma marca pode ter varios tipos)

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
HORAS_REFERENCIA_INMETRO = {"televisor": 6.59}
HORAS_OPCIONAIS = {"ar_condicionado"} | {c for c, h in HORAS_REFERENCIA_INMETRO.items() if h}

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
                     "mesmo_tipo": True, "texto": "mesmo tipo e volume parecido (15% para mais ou para menos)"},
    "televisor": {"categorias": ["televisor"], "medida": "capacidade", "tolerancia": 0.05,
                  "mesmo_tipo": False, "texto": "tela do mesmo tamanho (5% para mais ou para menos)"},
    "ar_condicionado": {"categorias": ["ar_condicionado"], "medida": "capacidade", "tolerancia": 0.05,
                        "mesmo_tipo": True, "texto": "mesmo tipo e mesma capacidade em BTU/h (5%)"},
    "ventilador_de_mesa": {"categorias": ["ventilador_de_mesa"], "medida": "capacidade", "tolerancia": 0.10,
                           "mesmo_tipo": False, "texto": "helice de diametro parecido (10%)"},
    "ventilador_de_teto": {"categorias": ["ventilador_de_teto"], "medida": "capacidade", "tolerancia": 0.10,
                           "mesmo_tipo": False, "texto": "diametro parecido (10%)"},
    "maquina_de_lavar": {"categorias": ["maquina_de_lavar"], "medida": "capacidade", "tolerancia": 0.15,
                         "mesmo_tipo": True, "texto": "mesmo tipo e capacidade parecida em kg (15%)"},
    "lampada_led": {"categorias": ["lampada_led"], "medida": "fluxo_lm", "tolerancia": 0.10,
                    "mesmo_tipo": False, "texto": "mesma luminosidade em lumens (10%)"},
    "lampada_fluorescente": {"categorias": ["lampada_led", "lampada_fluorescente"], "medida": "fluxo_lm",
                             "tolerancia": 0.10, "mesmo_tipo": False,
                             "texto": "mesma luminosidade em lumens (10%), incluindo lampadas LED"},
    "bomba": {"categorias": ["bomba"], "medida": "capacidade", "tolerancia": 0.0, "mesmo_tipo": False,
              "texto": "motor de mesma potencia (cv); confira vazao e altura com o fabricante"},
}
# Onde nao sugerimos troca, e o motivo (aparece no app).
SEM_SUGESTAO = {
    "chuveiro": ("Chuveiros eletricos tem eficiencia parecida: um modelo de menor potencia so esquenta "
                 "menos a agua. Para economizar, reduza o tempo de banho ou use a posicao verao."),
    "microondas": ("O Inmetro informa so a potencia do micro-ondas. Um modelo de menor potencia demora mais "
                   "para aquecer, entao a economia nao pode ser estimada so com esses dados."),
    "lampada_vapor_sodio": ("O dataset de vapor de sodio nao traz a luminosidade (lumens), entao nao da "
                            "para achar uma lampada equivalente."),
}
# Uma sugestao precisa gastar pelo menos 5% menos que o aparelho atual.
ECONOMIA_MINIMA = 0.05
# Consumo abaixo de 40% da mediana dos modelos equivalentes e tratado como erro de digitacao no
# Inmetro e nao e sugerido (ex.: HISENSE RS3P428NEDA = 28,0 kWh e a versao 127 V = 2,8 kWh).
FRACAO_SUSPEITA = 0.4

AVISO_PADRAO = ("Estimativa sem impostos (ICMS, PIS/COFINS), bandeira tarifaria e iluminacao "
                "publica. O uso real muda o resultado.")
# Com a tarifa da conta de luz, os impostos e a bandeira ja podem estar no valor digitado.
AVISO_TARIFA_USUARIO = ("Calculado com a tarifa que voce informou. O uso real muda o resultado.")

# Cada spec diz quais colunas do CSV limpo viram cada campo do catalogo.
# "capacidade": (coluna, unidade) aparece na tela, ex.: "490 L".
SPECS = [
    {
        "arquivo": "refrigeradores-e-assemelhados_limpo.csv", "categoria": "refrigerador",
        "tipo": "tipo", "capacidade": ("volume_total_litros", "L"),
        # padrao 2025 do Inmetro primeiro; se faltar, o padrao antigo
        "kwh_mes": ["consumo_medio_de_energia_mensal_kwh_mes", "consumo_de_energia_mensal_kwh_mes"],
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
    "fogoes_fornos_gas_limpo.csv": "consome gas, nao energia eletrica",
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

    if velocidade and pd.notna(aparelho.get(f"kwh_mes_{velocidade}")):
        return {"kwh_mes": float(aparelho[f"kwh_mes_{velocidade}"]),
                "metodo": f"consumo mensal do Inmetro, velocidade {velocidade}", "premissa": False}

    if horas_dia is not None and aparelho["categoria"] in HORAS_OPCIONAIS:
        if not 0 <= horas_dia <= 24:
            raise ValueError("horas por dia precisa estar entre 0 e 24")
        if aparelho["categoria"] == "ar_condicionado" and pd.notna(aparelho["potencia_w"]):
            return {"kwh_mes": float(aparelho["potencia_w"]) * horas_dia * dias / 1000,
                    "metodo": (f"{aparelho['potencia_w']:g} W (potencia do Inmetro a 35 C, carga total) x "
                               f"{horas_dia:g} h/dia x {dias} dias (informado); valor maximo, "
                               "o compressor nao fica ligado o tempo todo"),
                    "premissa": False}
        referencia = HORAS_REFERENCIA_INMETRO.get(aparelho["categoria"])
        if referencia and pd.notna(aparelho["kwh_mes"]):
            return {"kwh_mes": float(aparelho["kwh_mes"]) * horas_dia / referencia,
                    "metodo": (f"consumo mensal do Inmetro ({aparelho['kwh_mes']:g} kWh para {referencia:g} h/dia) "
                               f"ajustado para {horas_dia:g} h/dia (informado)"),
                    "premissa": False}

    if pd.notna(aparelho["kwh_mes"]):
        metodo = "consumo mensal do Inmetro"
        if aparelho["categoria"] in HORAS_OPCIONAIS:
            metodo += " (uso padrao do ensaio; informe as horas de uso para ajustar)"
        return {"kwh_mes": float(aparelho["kwh_mes"]), "metodo": metodo, "premissa": False}

    if pd.notna(aparelho["kwh_ciclo"]):
        ciclos = ciclos_mes if ciclos_mes is not None else premissa.get("ciclos_mes")
        if ciclos is None:
            raise ValueError("informe quantos ciclos por mes")
        if ciclos < 0:
            raise ValueError("ciclos por mes nao pode ser negativo")
        origem = "informado" if ciclos_mes is not None else "estimativa do grupo"
        return {"kwh_mes": float(aparelho["kwh_ciclo"]) * ciclos,
                "metodo": f"{aparelho['kwh_ciclo']:g} kWh por ciclo x {ciclos:g} ciclos por mes ({origem})",
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
        metodo = f"{aparelho['potencia_w']:g} W x {horas:g} h/dia x {dias} dias ({origem})"
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
    if aparelho.get("origem_dado") not in (None, "informado"):
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
