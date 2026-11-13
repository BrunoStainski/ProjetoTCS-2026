"""
Funcoes que a interface do iamp usa. Servem para qualquer tela
(terminal, FastAPI, Streamlit...). Tudo le do PostgreSQL (ver banco.py).

Fluxo:
  1. buscar_modelos(con, "brastemp brm44")        -> lista de aparelhos para o usuario escolher
  2. dados_de_uso(con, aparelho_id)               -> se precisa perguntar horas, ciclos ou velocidade
  3. listar_distribuidoras(con, uf="PR")          -> distribuidoras com tarifa para escolher
     ou listar_distribuidoras(con, busca="copel")
  4. calcular(con, aparelho_id, distribuidora_id) -> resultado com R$/kWh e custo por mes
  5. sugerir_alternativas(con, aparelho_id, ...)   -> modelos equivalentes que gastam menos
     comparar(con, aparelho_id, alternativa_id, preco_novo=...) -> economia e payback da troca
"""

import math

import pandas as pd

import banco
from idioma import measure as measure_in_language
from idioma import t, tr, units
from calculadora_residencial import (
    ESTIMATE_EXPANSIONS, EQUIVALENT_NOTICE, NUM_COLUMNS, MIN_SAVINGS, EQUIVALENCE, ESTIMABLE,
    SUSPECT_FRACTION, OPTIONAL_HOURS, INMETRO_REFERENCE_HOURS, SEARCH_LIMIT, BRAND_MODEL_LIMIT,
    MIN_EQUIVALENTS, MIN_QUARTILES, TYPE_NAMES, ASSUMPTIONS, NO_SUGGESTION, ESTIMATE_TOLERANCE,
    monthly_consumption_kwh, build_result, normalize,
)

SPEEDS = ("baixa", "media", "alta")


def _records(df):
    """DataFrame -> lista de dicts, trocando NaN por None (pronto para virar JSON)."""
    return df.astype(object).where(df.notna(), None).to_dict("records")


def _models_in_language(records):
    """Unidades do detalhe no idioma da requisicao ("43 pol" -> "43 in")."""
    for r in records:
        r["detalhe"] = units(r.get("detalhe"))
    return records


# 1. Aparelho -------------------------------------------------------------------

def search_models(con, text, category=None, limit=SEARCH_LIMIT):
    """Busca por marca e/ou modelo. Todos os termos digitados precisam aparecer.

    O limite vale por tipo de aparelho: antes era no total e, numa marca com varios tipos
    (ex.: brastemp), so o primeiro tipo em ordem alfabetica aparecia. total_categoria diz
    quantos modelos o tipo tem ao todo, para o app avisar que ha mais.
    """
    terms = normalize(text).split()
    if not terms:
        return []
    conditions = " AND ".join("busca LIKE ?" for _ in terms)
    params = [f"%{term}%" for term in terms]
    if category:
        conditions += " AND categoria = ?"
        params.append(category)
    sql = ("SELECT id, categoria, marca, modelo, detalhe, total_categoria FROM ("
           " SELECT id, categoria, marca, modelo, detalhe,"
           " ROW_NUMBER() OVER (PARTITION BY categoria ORDER BY marca, modelo) AS ordem,"
           " COUNT(*) OVER (PARTITION BY categoria) AS total_categoria"
           f" FROM aparelhos WHERE {conditions}) achados"
           " WHERE ordem <= ? ORDER BY categoria, marca, modelo")
    params.append(limit)
    return _models_in_language(_records(banco.query(con, sql, params)))


def list_brands(con, category):
    """Marcas de um tipo de aparelho com a quantidade de modelos (lista de marcas do app).

    O catalogo do Inmetro mistura maiusculas e minusculas na mesma marca ("Agratto" e "AGRATTO"):
    agrupa sem diferenciar, para a marca aparecer uma vez so.
    """
    sql = ("SELECT MIN(marca) AS marca, COUNT(DISTINCT modelo) AS modelos FROM aparelhos WHERE categoria = ? "
           "GROUP BY UPPER(TRIM(marca)) ORDER BY UPPER(TRIM(marca))")
    return _records(banco.query(con, sql, (category,)))


def brand_models(con, category, brand, limit=BRAND_MODEL_LIMIT):
    """Modelos de uma marca dentro de um tipo. total_categoria = quantos a marca tem nesse tipo
    (pode passar do limite: o app avisa para digitar o modelo)."""
    sql = ("SELECT id, categoria, marca, modelo, detalhe, COUNT(*) OVER () AS total_categoria "
           "FROM aparelhos WHERE categoria = ? AND UPPER(TRIM(marca)) = UPPER(TRIM(?)) "
           "ORDER BY modelo LIMIT ?")
    return _models_in_language(_records(banco.query(con, sql, (category, brand, limit))))


def appliance_by_id(con, appliance_id):
    df = banco.query(con, "SELECT * FROM aparelhos WHERE id = ?", (int(appliance_id),))
    if df.empty:
        raise ValueError(tr(f"aparelho {appliance_id} nao existe", f"appliance {appliance_id} does not exist"))
    return df.iloc[0]


def usage_data(con, appliance_id):
    """Diz o que a tela precisa perguntar antes de calcular.
    pergunta: None, "velocidade", "ciclos" ou "horas"; padrao: valor sugerido (estimativa do grupo);
    opcional: True quando o usuario pode deixar em branco e ficar com o valor do Inmetro;
    perguntar_horas: True quando, depois da velocidade, tambem precisa das horas (ventiladores)."""
    a = appliance_by_id(con, appliance_id)
    required_hours = a["categoria"] in INMETRO_REFERENCE_HOURS and a["categoria"] not in OPTIONAL_HOURS
    speeds = [v for v in SPEEDS if pd.notna(a[f"kwh_mes_{v}"])]
    if speeds:
        return {"pergunta": "velocidade", "opcoes": speeds,
                "padrao": "media" if "media" in speeds else speeds[-1],
                "perguntar_horas": required_hours}
    if required_hours and pd.notna(a["kwh_mes"]):
        return {"pergunta": "horas", "padrao": None, "opcional": False}
    if a["categoria"] in OPTIONAL_HOURS and (pd.notna(a["kwh_mes"]) or pd.notna(a["potencia_w"])):
        return {"pergunta": "horas", "padrao": None, "opcional": True}
    if pd.notna(a["kwh_mes"]):
        return {"pergunta": None}  # o Inmetro ja informa o consumo mensal
    assumption = ASSUMPTIONS.get(a["categoria"], {})
    if pd.notna(a["kwh_ciclo"]):
        return {"pergunta": "ciclos", "padrao": assumption.get("ciclos_mes")}
    return {"pergunta": "horas", "padrao": assumption.get("horas_dia")}


# 2. Distribuidora --------------------------------------------------------------

def list_ufs(con):
    return banco.query(
        con, "SELECT DISTINCT uf FROM vw_tarifa_vigente WHERE uf IS NOT NULL ORDER BY uf")["uf"].tolist()


def list_distributors(con, uf=None, search_text=None):
    """So devolve distribuidoras que tem tarifa vigente (as que o usuario pode escolher)."""
    sql = ("SELECT distribuidora_id AS id, distribuidora AS nome, uf, tarifa_kwh, vigencia_inicio, fonte "
           "FROM vw_tarifa_vigente")
    params = []
    if uf:
        sql += " WHERE uf = ?"
        params.append(uf.strip().upper())
    df = banco.query(con, sql + " ORDER BY nome", params)
    if search_text:
        target = normalize(search_text)
        df = df[df["nome"].map(normalize).str.contains(target, regex=False)]
    return _records(df)


def tariff_by_id(con, distributor_id):
    df = banco.query(
        con, "SELECT distribuidora AS nome, uf, tarifa_kwh, fonte FROM vw_tarifa_vigente WHERE distribuidora_id = ?",
        (int(distributor_id),))
    if df.empty:
        raise ValueError(tr(f"distribuidora {distributor_id} sem tarifa vigente",
                            f"power company {distributor_id} has no current tariff"))
    return df.iloc[0]


def choose_tariff(con, distributor_id=None, manual_tariff=None):
    """(tarifa R$/kWh, nome da distribuidora, uf, origem da tarifa)."""
    if manual_tariff is not None:
        if manual_tariff <= 0:
            raise ValueError(tr("a tarifa precisa ser maior que zero", "the rate must be greater than zero"))
        return float(manual_tariff), "-", None, tr("informada pelo usuario (conta de luz)",
                                                   "entered by the user (electricity bill)")
    if distributor_id is not None:
        in_force = tariff_by_id(con, distributor_id)
        return float(in_force["tarifa_kwh"]), in_force["nome"], in_force["uf"], t(in_force["fonte"])
    raise ValueError(tr("escolha uma distribuidora ou informe a tarifa da conta de luz",
                        "choose a power company or enter the rate from the electricity bill"))


# 3. Calculo --------------------------------------------------------------------

def calculate(con, appliance_id, distributor_id=None, manual_tariff=None,
             daily_hours=None, monthly_cycles=None, speed=None, register=True):
    """Resultado final. Use distribuidora_id OU tarifa_manual (R$/kWh da conta de luz)."""
    appliance = appliance_by_id(con, appliance_id)
    consumption = monthly_consumption_kwh(appliance, daily_hours=daily_hours, monthly_cycles=monthly_cycles, speed=speed)
    tariff, name, uf, origin = choose_tariff(con, distributor_id, manual_tariff)

    result = build_result(appliance, consumption, tariff, name, origin, uf, daily_hours,
                                 user_tariff=manual_tariff is not None)
    result["fonte_dados"] = "PostgreSQL"
    if register:
        banco.register_query(con, result, daily_hours=daily_hours,
                                 monthly_cycles=monthly_cycles, speed=speed)
    return result


def calculate_estimated(con, consumption, distributor_id=None, manual_tariff=None, brand=None, model=None,
                      register=True):
    tariff, name, uf, origin = choose_tariff(con, distributor_id, manual_tariff)
    appliance = {"categoria": consumption["categoria"], "marca": brand or consumption["nome"],
                "modelo": model or tr("(estimativa)", "(estimate)"), "detalhe": consumption["detalhe"], "origem_dado": None}
    result = build_result(appliance, consumption, tariff, name, origin, uf, consumption.get("horas_dia"),
                                 user_tariff=manual_tariff is not None)
    result["avisos"] += consumption["avisos"]
    result["aproximado"] = consumption["aproximado"]
    result["fonte_dados"] = consumption["fonte"]
    result["tipo"] = consumption.get("tipo")
    result["capacidade"] = consumption.get("capacidade")
    result["pelos_parecidos"] = consumption.get("pelos_parecidos", False)
    if "kwh_min" in consumption:
        result["kwh_min"] = round(consumption["kwh_min"], 2)
        result["kwh_max"] = round(consumption["kwh_max"], 2)
        result["custo_min_mes"] = round(consumption["kwh_min"] * tariff, 2)
        result["custo_max_mes"] = round(consumption["kwh_max"] * tariff, 2)
    if register:
        banco.register_query(con, result, daily_hours=consumption.get("horas_dia"))
    return result


def _small_appliances_in_language(records):
    for r in records:
        r["nome"] = t(r["nome"])
    return records


def list_small_appliances(con):
    item_list = _small_appliances_in_language(_records(banco.query(
        con, "SELECT categoria, nome, potencia_w, horas_dia, dias_mes, fonte FROM portateis ORDER BY nome")))
    return sorted(item_list, key=lambda r: normalize(r["nome"]))  # em ingles a ordem alfabetica muda


def smallAppliance(con, category):
    df = banco.query(con, "SELECT categoria, nome, potencia_w, horas_dia, dias_mes, fonte FROM portateis "
                             "WHERE categoria = ?", (category,))
    if df.empty:
        raise ValueError(tr(f"eletroportatil {category} nao existe", f"small appliance {category} does not exist"))
    return _small_appliances_in_language(_records(df))[0]


def category_usage_question(category):
    if category in INMETRO_REFERENCE_HOURS and category not in OPTIONAL_HOURS:
        return {"pergunta": "velocidade", "opcoes": list(SPEEDS), "padrao": "media", "perguntar_horas": True}
    if category in OPTIONAL_HOURS:
        return {"pergunta": "horas", "padrao": None, "opcional": True}
    assumption = ASSUMPTIONS.get(category, {})
    if "ciclos_mes" in assumption:
        return {"pergunta": "ciclos", "padrao": assumption["ciclos_mes"]}
    return {"pergunta": "horas", "padrao": assumption.get("horas_dia")}


def _type_name(kind):
    return t(TYPE_NAMES.get(kind, (kind, None))[0]) if kind else kind


def _unit(config):
    return units(config["medida"].split("(")[-1].rstrip(")")) if config.get("medida") else None


def _shape_in_language(shape):
    """Numero do aparelho que a pessoa pode informar (etiqueta ou plaqueta), no idioma da requisicao."""
    return {**shape, "nome": t(shape["nome"]), "rotulo": t(shape["rotulo"]), "unidade": t(shape["unidade"]),
            "onde": t(shape["onde"]), "dica": t(shape["dica"]), "exemplo": measure_in_language(shape["exemplo"])}


def estimable_categories(con):
    item_list = []
    for category, config in ESTIMABLE.items():
        rule = EQUIVALENCE.get(category, {})
        types = []
        if rule.get("mesmo_tipo") and not config.get("especial"):
            types = banco.query(
                con, "SELECT DISTINCT tipo FROM aparelhos WHERE categoria = ? AND origem_dado = 'informado' "
                     "AND tipo IS NOT NULL AND tipo <> '' ORDER BY tipo", (category,))["tipo"].tolist()
            order = list(TYPE_NAMES)
            types.sort(key=lambda kind: order.index(kind) if kind in order else len(order))
        item_list.append({
            "categoria": category,
            "nome": t(config["nome"]),
            "especial": bool(config.get("especial")),
            "medida": t(config.get("medida")),
            "unidade_medida": _unit(config),
            "tamanhos": [{**size, "nome": measure_in_language(size["nome"])} for size in config.get("tamanhos", [])],
            "tipos": [{"valor": kind, "nome": _type_name(kind), "descricao": t(TYPE_NAMES.get(kind, (kind, None))[1])}
                      for kind in types],
            "formas": [_shape_in_language(shape) for shape in config.get("formas", [])],
            "valor_obrigatorio": bool(config.get("obrigatorio")),
            "uso": category_usage_question(category),
        })
    return item_list


def _equivalent(con, category, kind, measure):
    rule = EQUIVALENCE.get(category, {})
    tolerance = max(rule.get("tolerancia", ESTIMATE_TOLERANCE), ESTIMATE_TOLERANCE)
    type_filter = bool(rule.get("mesmo_tipo") and kind)
    sql_type = " AND tipo = ?" if type_filter else ""
    params_type = [kind] if type_filter else []
    if measure is None:
        sql = "SELECT * FROM aparelhos WHERE categoria = ? AND origem_dado = 'informado'" + sql_type
        return banco.query(con, sql, [category, *params_type]), None, type_filter
    candidates = pd.DataFrame()
    for factor in ESTIMATE_EXPANSIONS:
        margin = float(measure) * tolerance * factor
        sql = ("SELECT * FROM aparelhos WHERE categoria = ? AND origem_dado = 'informado' "
               "AND capacidade BETWEEN ? AND ?" + sql_type)
        candidates = banco.query(con, sql, [category, float(measure) - margin, float(measure) + margin, *params_type])
        if len(candidates) >= MIN_EQUIVALENTS:
            return candidates, tolerance * factor, type_filter
    return candidates, tolerance * ESTIMATE_EXPANSIONS[-1], type_filter


def estimate_from_equivalents(con, category, kind=None, measure=None, label_value=None,
                             daily_hours=None, monthly_cycles=None, speed=None, label_field=None):
    config = ESTIMABLE.get(category)
    if config is None or config.get("especial"):
        raise ValueError(tr(f"categoria {category} nao tem esta estimativa", f"category {category} has no such estimate"))
    usage = {"daily_hours": daily_hours, "monthly_cycles": monthly_cycles, "speed": speed}  # vira **kwargs
    base = {"categoria": category, "nome": t(config["nome"]), "tipo": kind or None}

    if label_value is not None:
        shapes = {f["campo"]: _shape_in_language(f) for f in config["formas"]}
        shape = shapes.get(label_field or config["formas"][0]["campo"])
        if shape is None:
            raise ValueError(tr(f"para {base['nome']} informe: {', '.join(f['nome'] for f in shapes.values())}",
                                f"for {base['nome']} enter: {', '.join(f['nome'] for f in shapes.values())}"))
        if not 0 < label_value <= shape["maximo"]:
            raise ValueError(tr(f"{shape['rotulo']} precisa estar entre 0 e {shape['maximo']:g} {shape['unidade']}",
                                f"{shape['rotulo']} must be between 0 and {shape['maximo']:g} {shape['unidade']}"))
        appliance = {**{c: math.nan for c in NUM_COLUMNS}, "categoria": category, shape["campo"]: float(label_value)}
        if shape["campo"] == "potencia_w":
            usage["speed"] = None
        consumption = monthly_consumption_kwh(appliance, **usage)
        return {**base, **consumption, "kwh_min": consumption["kwh_mes"], "kwh_max": consumption["kwh_mes"],
                "metodo": f"{shape['nome']}: {label_value:g} {shape['unidade']}; {consumption['metodo']}",
                "capacidade": measure if config.get("medida") else float(label_value),
                "detalhe": _estimated_detail(config, kind, measure) or f"{label_value:g} {shape['unidade']}",
                "pelos_parecidos": False,
                "aproximado": consumption["premissa"], "avisos": [], "fonte": "valor informado pelo usuário"}

    if config.get("obrigatorio"):
        label = t(config["formas"][0]["rotulo"]).lower()
        raise ValueError(tr(f"informe a {label} do aparelho", f"enter the appliance's {label}"))
    if config.get("medida") and (measure is None or measure <= 0):
        raise ValueError(tr(f"informe {config['medida'].lower()} ou o valor escrito no aparelho",
                            f"enter the {t(config['medida']).lower()} or the value written on the appliance"))
    candidates, tolerance, filtered_type = _equivalent(con, category, kind, measure if config.get("medida") else None)
    valid_items = []
    for _, c in candidates.iterrows():
        try:
            monthly_consumption_kwh(c, **usage)
        except ValueError:
            continue
        valid_items.append(c)
    if not valid_items:
        raise ValueError(tr("nao ha modelos parecidos no catalogo para estimar; informe o valor escrito no aparelho",
                            "there are no similar models in the catalog to estimate from; "
                            "enter the value written on the appliance"))
    numbers = pd.DataFrame(valid_items)[NUM_COLUMNS].astype(float)

    def reference(q):
        return monthly_consumption_kwh({**numbers.quantile(q).to_dict(), "categoria": category}, **usage)

    few = len(numbers) < MIN_QUARTILES
    central = reference(0.5)
    smallest, largest = (reference(0), reference(1)) if few else (reference(0.25), reference(0.75))
    parts = []
    if tolerance is not None:
        measure_name = t(config["medida"]).split(" (")[0].lower()
        measure_reference = _estimated_detail(config, None, measure)
        parts.append(tr(f"{measure_name} até {tolerance:.0%} acima ou abaixo de {measure_reference}",
                         f"{measure_name} within {tolerance:.0%} above or below {measure_reference}"))
    if filtered_type:
        parts.append(tr(f"do tipo {_type_name(kind).lower()}", f"of the type {_type_name(kind).lower()}"))
    criterion = tr(" e ", " and ").join(parts) or tr("todos os modelos do catálogo", "all models in the catalog")
    if len(numbers) == 1:
        range_text = tr("só 1 modelo parecido, sem faixa", "only 1 similar model, no range")
    elif few:
        range_text = tr("faixa entre o menor e o maior valor", "range between the lowest and the highest value")
    else:
        range_text = tr("faixa entre o 1º e o 3º quartil", "range between the 1st and the 3rd quartile")
    return {
        **base,
        "kwh_mes": central["kwh_mes"],
        "kwh_min": smallest["kwh_mes"],
        "kwh_max": largest["kwh_mes"],
        "metodo": tr(f"mediana de {len(numbers)} modelos atuais parecidos do Inmetro ({criterion}); "
                     f"{range_text}. Uso: {central['metodo']}",
                     f"median of {len(numbers)} similar current Inmetro models ({criterion}); "
                     f"{range_text}. Use: {central['metodo']}"),
        "capacidade": float(measure) if tolerance is not None else None,
        "detalhe": _estimated_detail(config, kind, measure if tolerance is not None else None),
        "premissa": central["premissa"],
        "aproximado": True,
        "avisos": [t(EQUIVALENT_NOTICE)],
        "fonte": "catálogo do Inmetro (modelos equivalentes)",
        "pelos_parecidos": True,
    }


def _estimated_detail(config, kind, measure):
    parts = [_type_name(kind)] if kind else []  # tipo e unidade ja no idioma da requisicao
    if measure is not None:
        parts.append(f"{measure:g} {_unit(config)}")
    return ", ".join(parts)


# 4. Aparelho mais economico ------------------------------------------------------

def _candidates(con, current, rule, speed):
    """Modelos que fazem o mesmo servico (ver EQUIVALENCIA) e tem consumo vindo do Inmetro."""
    measure = current[rule["medida"]]
    if pd.isna(measure):
        return None
    margin = float(measure) * rule["tolerancia"]
    categories = rule["categorias"]
    # regra["medida"] e a velocidade vem de listas fixas do codigo, nunca de texto do usuario
    sql = (f"SELECT * FROM aparelhos WHERE categoria IN ({', '.join('?' for _ in categories)}) "
           f"AND id <> ? AND origem_dado = 'informado' AND {rule['medida']} BETWEEN ? AND ?")
    params = [*categories, int(current["id"]), float(measure) - margin, float(measure) + margin]
    kind = _text(current["tipo"])
    if rule["mesmo_tipo"] and kind:
        sql += " AND tipo = ?"
        params.append(kind)
    volts = _text(current.get("tensao"))
    if volts:  # quem tem a versao 220 V nao recebe sugestao de 127 V (vazio = vale para as duas)
        sql += " AND tensao IN ('', ?)"
        params.append(volts)
    if speed in SPEEDS:  # ventilador: precisa ter o consumo na mesma velocidade
        sql += f" AND kwh_mes_{speed} IS NOT NULL"
    return banco.query(con, sql, params)


def _text(value):
    return value.strip() if isinstance(value, str) else ""


def _summary(appliance):
    # o tipo do Inmetro so tem traducao onde ele e padronizado (geladeira, ar, maquina de lavar)
    return {"id": int(appliance["id"]), "categoria": appliance["categoria"], "marca": appliance["marca"],
            "modelo": appliance["modelo"], "detalhe": units(_text(appliance["detalhe"])),
            "tipo": t(_text(appliance["tipo"]))}


def suggest_alternatives(con, appliance_id, distributor_id=None, manual_tariff=None,
                         daily_hours=None, monthly_cycles=None, speed=None, limit=5):
    """Modelos equivalentes que gastam pelo menos 5% menos, com o mesmo uso e a mesma tarifa.
    O catalogo nao tem precos: o payback sai em comparar(), com o preco que o usuario digitar."""
    current = appliance_by_id(con, appliance_id)
    usage = {"daily_hours": daily_hours, "monthly_cycles": monthly_cycles, "speed": speed}  # vira **kwargs
    current_kwh = monthly_consumption_kwh(current, **usage)["kwh_mes"]
    return _suggest(con, current, current_kwh, usage, distributor_id, manual_tariff, limit)


def suggest_for_estimated(con, category, capacity, monthly_kwh, kind=None, name=None, distributor_id=None,
                          manual_tariff=None, daily_hours=None, monthly_cycles=None, speed=None, limit=5,
                          by_similar=False):
    """pelos_parecidos: o kwh_mes saiu da mediana dos modelos parecidos (sem o numero do aparelho), entao
    comparar com esses mesmos modelos e circular e a mensagem precisa dizer isso."""
    if monthly_kwh <= 0:
        raise ValueError(tr("o consumo do aparelho precisa ser maior que zero",
                            "the appliance's consumption must be greater than zero"))
    current = {"id": 0, "categoria": category, "marca": name or t(ESTIMABLE.get(category, {}).get("nome", category)),
             "modelo": tr("(estimativa)", "(estimate)"), "detalhe": "", "tipo": kind or "",
             "capacidade": math.nan if capacity is None else float(capacity), "fluxo_lm": math.nan}
    rule = EQUIVALENCE.get(category, {})
    if rule.get("medida") == "fluxo_lm" and capacity:
        current["fluxo_lm"] = float(capacity) * _luminous_efficiency(con, category)
    usage = {"daily_hours": daily_hours, "monthly_cycles": monthly_cycles, "speed": speed}  # vira **kwargs
    return _suggest(con, current, float(monthly_kwh), usage, distributor_id, manual_tariff, limit, by_similar)


def _luminous_efficiency(con, category):
    df = banco.query(con, "SELECT fluxo_lm / potencia_w AS lm_por_w FROM aparelhos WHERE categoria = ? "
                             "AND fluxo_lm > 0 AND potencia_w > 0", (category,))
    return float(df["lm_por_w"].median()) if len(df) else math.nan


def _suggest(con, current, current_kwh, usage, distributor_id, manual_tariff, limit, by_similar=False):
    speed = usage.get("speed")
    tariff, _, _, _ = choose_tariff(con, distributor_id, manual_tariff)
    response = {
        "atual": {**_summary(current), "kwh_mes": round(current_kwh, 2), "custo_mes": round(current_kwh * tariff, 2)},
        "tarifa_kwh": round(tariff, 5),
        "criterio": None,
        "mensagem": None,
        "suspeitos_descartados": 0,
        "sugestoes": [],
    }

    if current_kwh <= 0:
        # 0 h por dia ou 0 ciclos: nao ha consumo para reduzir (e a economia em % dividiria por zero)
        response["mensagem"] = tr("Com esse uso o aparelho não gasta energia, então não há o que economizar "
                                  "trocando de modelo. Calcule de novo com o tempo de uso real.",
                                  "With this use the appliance uses no energy, so there is nothing to save by "
                                  "changing models. Calculate again with the actual time of use.")
        return response
    rule = EQUIVALENCE.get(current["categoria"])
    if rule is None:
        response["mensagem"] = t(NO_SUGGESTION.get(
            current["categoria"], "Ainda não sugerimos trocas para este tipo de aparelho."))
        return response
    response["criterio"] = t(rule["texto"])
    candidates = _candidates(con, current, rule, speed)
    if candidates is None:
        response["mensagem"] = tr("Para achar modelos parecidos precisamos do tamanho do aparelho. "
                                  "Calcule de novo informando o tamanho.",
                                  "To find similar models we need the appliance's size. "
                                  "Calculate again and enter the size.")
        return response

    consumptions = []
    for _, c in candidates.iterrows():
        try:
            consumptions.append((c, monthly_consumption_kwh(c, **usage)["kwh_mes"]))
        except ValueError:
            continue  # o modelo nao tem o dado que esse uso precisa
    median = float(pd.Series([current_kwh] + [k for _, k in consumptions]).median())

    suggestions = []
    for c, kwh in consumptions:
        if kwh < median * SUSPECT_FRACTION:
            response["suspeitos_descartados"] += 1
            continue
        savings = current_kwh - kwh
        if savings >= current_kwh * MIN_SAVINGS:
            suggestions.append({
                **_summary(c),
                "kwh_mes": round(kwh, 2),
                "custo_mes": round(kwh * tariff, 2),
                "economia_kwh_mes": round(savings, 2),
                "economia_mes": round(savings * tariff, 2),
                "economia_ano": round(savings * tariff * 12, 2),
                "economia_percentual": round(savings / current_kwh * 100, 1),
            })
    suggestions.sort(key=lambda s: (s["kwh_mes"], s["marca"], s["modelo"]))
    # variacoes do mesmo modelo (ex.: cor ou voltagem) aparecem uma vez so
    seen, unique_items = set(), []
    for s in suggestions:
        key = (s["marca"].lower(), s["detalhe"], s["kwh_mes"])
        if key not in seen:
            seen.add(key)
            unique_items.append(s)
    response["sugestoes"] = unique_items[:limit]
    if not suggestions and by_similar:
        response["mensagem"] = tr(
            "O gasto do seu aparelho foi calculado pelos modelos atuais parecidos, então ele sai igual a eles e "
            "nenhum aparece como mais econômico. Se o seu for antigo, pode gastar mais. Para comparar de verdade, "
            "calcule de novo com o número da etiqueta ou a potência escrita no aparelho.",
            "Your appliance's cost was calculated from similar current models, so it comes out the same as them and "
            "none shows up as more economical. If yours is old, it may use more. To compare for real, "
            "calculate again with the number on the label or the power written on the appliance.")
    elif not suggestions:
        response["mensagem"] = tr("Este aparelho já está entre os mais econômicos do catálogo do Inmetro.",
                                  "This appliance is already among the most economical in Inmetro's catalog.")
    return response


def compare(con, appliance_id, alternative_id, distributor_id=None, manual_tariff=None,
             daily_hours=None, monthly_cycles=None, speed=None, new_price=None):
    """Economia de trocar o aparelho atual pela alternativa e, com o preco, em quantos meses a troca se paga."""
    if int(appliance_id) == int(alternative_id):
        raise ValueError(tr("escolha um modelo diferente do atual para comparar",
                            "choose a model different from the current one to compare"))
    usage = {"daily_hours": daily_hours, "monthly_cycles": monthly_cycles, "speed": speed}  # vira **kwargs
    current = calculate(con, appliance_id, distributor_id, manual_tariff, register=False, **usage)
    rewritten = calculate(con, alternative_id, distributor_id, manual_tariff, register=False, **usage)
    return _comparison(current, rewritten, new_price)


def compare_estimated(con, category, monthly_kwh, alternative_id, name=None, distributor_id=None,
                      manual_tariff=None, daily_hours=None, monthly_cycles=None, speed=None, new_price=None):
    if monthly_kwh <= 0:
        raise ValueError(tr("o consumo do aparelho precisa ser maior que zero",
                            "the appliance's consumption must be greater than zero"))
    usage = {"daily_hours": daily_hours, "monthly_cycles": monthly_cycles, "speed": speed}  # vira **kwargs
    rewritten = calculate(con, alternative_id, distributor_id, manual_tariff, register=False, **usage)
    tariff, distributor_name, uf, origin = choose_tariff(con, distributor_id, manual_tariff)
    appliance = {"categoria": category, "marca": name or t(ESTIMABLE.get(category, {}).get("nome", category)),
                "modelo": tr("(estimativa)", "(estimate)"), "detalhe": "", "origem_dado": None}
    consumption = {"kwh_mes": float(monthly_kwh), "metodo": tr("estimativa feita no app", "estimate made in the app"),
               "premissa": False}
    current = build_result(appliance, consumption, tariff, distributor_name, origin, uf, daily_hours,
                             user_tariff=manual_tariff is not None)
    current["fonte_dados"] = "estimativa"
    return _comparison(current, rewritten, new_price)


def _comparison(current, rewritten, new_price):
    allowed = EQUIVALENCE.get(current["categoria"], {}).get("categorias", [current["categoria"]])
    if rewritten["categoria"] not in allowed:
        raise ValueError(tr("os dois aparelhos precisam fazer o mesmo servico para comparar",
                            "both appliances must do the same job to be compared"))

    monthly_savings = current["custo_mes"] - rewritten["custo_mes"]
    payback = None
    if new_price is not None:
        if new_price <= 0:
            raise ValueError(tr("o preco precisa ser maior que zero", "the price must be greater than zero"))
        payback = {"preco_novo": round(float(new_price), 2), "meses": None, "anos": None}
        if monthly_savings > 0:
            months = new_price / monthly_savings
            payback.update(meses=round(months, 1), anos=round(months / 12, 1))
            payback["texto"] = (
                tr(f"A troca se paga em cerca de {months:.0f} meses ({months / 12:.1f} anos) so com a economia na conta de luz.",
                   f"The replacement pays for itself in about {months:.0f} months ({months / 12:.1f} years) "
                   "from the electricity bill savings alone.")
                if months >= 1 else tr("A troca se paga em menos de um mes.",
                                      "The replacement pays for itself in less than a month."))
        else:
            payback["texto"] = tr("O modelo novo nao gasta menos, entao a troca nao se paga pela conta de luz.",
                                  "The new model does not use less, so the replacement does not pay off "
                                  "through the electricity bill.")
    return {
        "atual": current,
        "novo": rewritten,
        "economia_kwh_mes": round(current["kwh_mes"] - rewritten["kwh_mes"], 2),
        "economia_mes": round(monthly_savings, 2),
        "economia_ano": round(monthly_savings * 12, 2),
        "payback": payback,
        "avisos": [
            tr("Payback simples: preco do modelo novo dividido pela economia mensal, sem juros, "
               "sem a venda do aparelho antigo e sem reajuste da tarifa.",
               "Simple payback: price of the new model divided by the monthly savings, without interest, "
               "without selling the old appliance and without rate increases."),
            tr("O catálogo do Inmetro não tem preços: o valor usado é o que você digitou.",
               "Inmetro's catalog has no prices: the value used is the one you typed."),
        ],
    }
