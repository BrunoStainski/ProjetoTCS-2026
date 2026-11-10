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
from calculadora_residencial import (
    AMPLIACOES_ESTIMATIVA, AVISO_EQUIVALENTES, COLUNAS_NUM, ECONOMIA_MINIMA, EQUIVALENCIA, ESTIMAVEIS,
    FRACAO_SUSPEITA, HORAS_OPCIONAIS, HORAS_REFERENCIA_INMETRO, LIMITE_BUSCA, LIMITE_MODELOS_MARCA,
    MINIMO_EQUIVALENTES, MINIMO_QUARTIS, NOMES_DOS_TIPOS, PREMISSAS, SEM_SUGESTAO, TOLERANCIA_ESTIMATIVA,
    consumo_mensal_kwh, montar_resultado, normalizar,
)

VELOCIDADES = ("baixa", "media", "alta")


def _registros(df):
    """DataFrame -> lista de dicts, trocando NaN por None (pronto para virar JSON)."""
    return df.astype(object).where(df.notna(), None).to_dict("records")


# 1. Aparelho -------------------------------------------------------------------

def buscar_modelos(con, texto, categoria=None, limite=LIMITE_BUSCA):
    """Busca por marca e/ou modelo. Todos os termos digitados precisam aparecer.

    O limite vale por tipo de aparelho: antes era no total e, numa marca com varios tipos
    (ex.: brastemp), so o primeiro tipo em ordem alfabetica aparecia. total_categoria diz
    quantos modelos o tipo tem ao todo, para o app avisar que ha mais.
    """
    termos = normalizar(texto).split()
    if not termos:
        return []
    filtro = " AND ".join("busca LIKE ?" for _ in termos)
    params = [f"%{t}%" for t in termos]
    if categoria:
        filtro += " AND categoria = ?"
        params.append(categoria)
    sql = ("SELECT id, categoria, marca, modelo, detalhe, total_categoria FROM ("
           " SELECT id, categoria, marca, modelo, detalhe,"
           " ROW_NUMBER() OVER (PARTITION BY categoria ORDER BY marca, modelo) AS ordem,"
           " COUNT(*) OVER (PARTITION BY categoria) AS total_categoria"
           f" FROM aparelhos WHERE {filtro}) achados"
           " WHERE ordem <= ? ORDER BY categoria, marca, modelo")
    params.append(limite)
    return _registros(banco.consulta(con, sql, params))


def listar_marcas(con, categoria):
    """Marcas de um tipo de aparelho com a quantidade de modelos (lista de marcas do app).

    O catalogo do Inmetro mistura maiusculas e minusculas na mesma marca ("Agratto" e "AGRATTO"):
    agrupa sem diferenciar, para a marca aparecer uma vez so.
    """
    sql = ("SELECT MIN(marca) AS marca, COUNT(*) AS modelos FROM aparelhos WHERE categoria = ? "
           "GROUP BY UPPER(TRIM(marca)) ORDER BY UPPER(TRIM(marca))")
    return _registros(banco.consulta(con, sql, (categoria,)))


def modelos_da_marca(con, categoria, marca, limite=LIMITE_MODELOS_MARCA):
    """Modelos de uma marca dentro de um tipo. total_categoria = quantos a marca tem nesse tipo
    (pode passar do limite: o app avisa para digitar o modelo)."""
    sql = ("SELECT id, categoria, marca, modelo, detalhe, COUNT(*) OVER () AS total_categoria "
           "FROM aparelhos WHERE categoria = ? AND UPPER(TRIM(marca)) = UPPER(TRIM(?)) "
           "ORDER BY modelo LIMIT ?")
    return _registros(banco.consulta(con, sql, (categoria, marca, limite)))


def aparelho_por_id(con, aparelho_id):
    df = banco.consulta(con, "SELECT * FROM aparelhos WHERE id = ?", (int(aparelho_id),))
    if df.empty:
        raise ValueError(f"aparelho {aparelho_id} nao existe")
    return df.iloc[0]


def dados_de_uso(con, aparelho_id):
    """Diz o que a tela precisa perguntar antes de calcular.
    pergunta: None, "velocidade", "ciclos" ou "horas"; padrao: valor sugerido (estimativa do grupo);
    opcional: True quando o usuario pode deixar em branco e ficar com o valor do Inmetro;
    perguntar_horas: True quando, depois da velocidade, tambem precisa das horas (ventiladores)."""
    a = aparelho_por_id(con, aparelho_id)
    horas_obrigatorias = a["categoria"] in HORAS_REFERENCIA_INMETRO and a["categoria"] not in HORAS_OPCIONAIS
    velocidades = [v for v in VELOCIDADES if pd.notna(a[f"kwh_mes_{v}"])]
    if velocidades:
        return {"pergunta": "velocidade", "opcoes": velocidades,
                "padrao": "media" if "media" in velocidades else velocidades[-1],
                "perguntar_horas": horas_obrigatorias}
    if horas_obrigatorias and pd.notna(a["kwh_mes"]):
        return {"pergunta": "horas", "padrao": None, "opcional": False}
    if a["categoria"] in HORAS_OPCIONAIS and (pd.notna(a["kwh_mes"]) or pd.notna(a["potencia_w"])):
        return {"pergunta": "horas", "padrao": None, "opcional": True}
    if pd.notna(a["kwh_mes"]):
        return {"pergunta": None}  # o Inmetro ja informa o consumo mensal
    premissa = PREMISSAS.get(a["categoria"], {})
    if pd.notna(a["kwh_ciclo"]):
        return {"pergunta": "ciclos", "padrao": premissa.get("ciclos_mes")}
    return {"pergunta": "horas", "padrao": premissa.get("horas_dia")}


# 2. Distribuidora --------------------------------------------------------------

def listar_ufs(con):
    return banco.consulta(
        con, "SELECT DISTINCT uf FROM vw_tarifa_vigente WHERE uf IS NOT NULL ORDER BY uf")["uf"].tolist()


def listar_distribuidoras(con, uf=None, busca=None):
    """So devolve distribuidoras que tem tarifa vigente (as que o usuario pode escolher)."""
    sql = ("SELECT distribuidora_id AS id, distribuidora AS nome, uf, tarifa_kwh, vigencia_inicio, fonte "
           "FROM vw_tarifa_vigente")
    params = []
    if uf:
        sql += " WHERE uf = ?"
        params.append(uf.strip().upper())
    df = banco.consulta(con, sql + " ORDER BY nome", params)
    if busca:
        alvo = normalizar(busca)
        df = df[df["nome"].map(normalizar).str.contains(alvo, regex=False)]
    return _registros(df)


def tarifa_por_id(con, distribuidora_id):
    df = banco.consulta(
        con, "SELECT distribuidora AS nome, uf, tarifa_kwh, fonte FROM vw_tarifa_vigente WHERE distribuidora_id = ?",
        (int(distribuidora_id),))
    if df.empty:
        raise ValueError(f"distribuidora {distribuidora_id} sem tarifa vigente")
    return df.iloc[0]


def escolher_tarifa(con, distribuidora_id=None, tarifa_manual=None):
    """(tarifa R$/kWh, nome da distribuidora, uf, origem da tarifa)."""
    if tarifa_manual is not None:
        if tarifa_manual <= 0:
            raise ValueError("a tarifa precisa ser maior que zero")
        return float(tarifa_manual), "-", None, "informada pelo usuario (conta de luz)"
    if distribuidora_id is not None:
        t = tarifa_por_id(con, distribuidora_id)
        return float(t["tarifa_kwh"]), t["nome"], t["uf"], t["fonte"]
    raise ValueError("escolha uma distribuidora ou informe a tarifa da conta de luz")


# 3. Calculo --------------------------------------------------------------------

def calcular(con, aparelho_id, distribuidora_id=None, tarifa_manual=None,
             horas_dia=None, ciclos_mes=None, velocidade=None, registrar=True):
    """Resultado final. Use distribuidora_id OU tarifa_manual (R$/kWh da conta de luz)."""
    aparelho = aparelho_por_id(con, aparelho_id)
    consumo = consumo_mensal_kwh(aparelho, horas_dia=horas_dia, ciclos_mes=ciclos_mes, velocidade=velocidade)
    tarifa, nome, uf, origem = escolher_tarifa(con, distribuidora_id, tarifa_manual)

    resultado = montar_resultado(aparelho, consumo, tarifa, nome, origem, uf, horas_dia,
                                 tarifa_do_usuario=tarifa_manual is not None)
    resultado["fonte_dados"] = "PostgreSQL"
    if registrar:
        banco.registrar_consulta(con, resultado, horas_dia=horas_dia,
                                 ciclos_mes=ciclos_mes, velocidade=velocidade)
    return resultado


def calcular_estimado(con, consumo, distribuidora_id=None, tarifa_manual=None, marca=None, modelo=None,
                      registrar=True):
    tarifa, nome, uf, origem = escolher_tarifa(con, distribuidora_id, tarifa_manual)
    aparelho = {"categoria": consumo["categoria"], "marca": marca or consumo["nome"],
                "modelo": modelo or "(estimativa)", "detalhe": consumo["detalhe"], "origem_dado": None}
    resultado = montar_resultado(aparelho, consumo, tarifa, nome, origem, uf, consumo.get("horas_dia"),
                                 tarifa_do_usuario=tarifa_manual is not None)
    resultado["avisos"] += consumo["avisos"]
    resultado["aproximado"] = consumo["aproximado"]
    resultado["fonte_dados"] = consumo["fonte"]
    resultado["tipo"] = consumo.get("tipo")
    resultado["capacidade"] = consumo.get("capacidade")
    resultado["pelos_parecidos"] = consumo.get("pelos_parecidos", False)
    if "kwh_min" in consumo:
        resultado["kwh_min"] = round(consumo["kwh_min"], 2)
        resultado["kwh_max"] = round(consumo["kwh_max"], 2)
        resultado["custo_min_mes"] = round(consumo["kwh_min"] * tarifa, 2)
        resultado["custo_max_mes"] = round(consumo["kwh_max"] * tarifa, 2)
    if registrar:
        banco.registrar_consulta(con, resultado, horas_dia=consumo.get("horas_dia"))
    return resultado


def listar_portateis(con):
    return _registros(banco.consulta(
        con, "SELECT categoria, nome, potencia_w, horas_dia, dias_mes, fonte FROM portateis ORDER BY nome"))


def portatil(con, categoria):
    df = banco.consulta(con, "SELECT categoria, nome, potencia_w, horas_dia, dias_mes, fonte FROM portateis "
                             "WHERE categoria = ?", (categoria,))
    if df.empty:
        raise ValueError(f"eletroportatil {categoria} nao existe")
    return _registros(df)[0]


def pergunta_de_uso_da_categoria(categoria):
    if categoria in HORAS_REFERENCIA_INMETRO and categoria not in HORAS_OPCIONAIS:
        return {"pergunta": "velocidade", "opcoes": list(VELOCIDADES), "padrao": "media", "perguntar_horas": True}
    if categoria in HORAS_OPCIONAIS:
        return {"pergunta": "horas", "padrao": None, "opcional": True}
    premissa = PREMISSAS.get(categoria, {})
    if "ciclos_mes" in premissa:
        return {"pergunta": "ciclos", "padrao": premissa["ciclos_mes"]}
    return {"pergunta": "horas", "padrao": premissa.get("horas_dia")}


def _nome_do_tipo(tipo):
    return NOMES_DOS_TIPOS.get(tipo, (tipo, None))[0] if tipo else tipo


def _unidade(config):
    return config["medida"].split("(")[-1].rstrip(")") if config.get("medida") else None


def categorias_estimaveis(con):
    lista = []
    for categoria, config in ESTIMAVEIS.items():
        regra = EQUIVALENCIA.get(categoria, {})
        tipos = []
        if regra.get("mesmo_tipo") and not config.get("especial"):
            tipos = banco.consulta(
                con, "SELECT DISTINCT tipo FROM aparelhos WHERE categoria = ? AND origem_dado = 'informado' "
                     "AND tipo IS NOT NULL AND tipo <> '' ORDER BY tipo", (categoria,))["tipo"].tolist()
            ordem = list(NOMES_DOS_TIPOS)
            tipos.sort(key=lambda t: ordem.index(t) if t in ordem else len(ordem))
        lista.append({
            "categoria": categoria,
            "nome": config["nome"],
            "especial": bool(config.get("especial")),
            "medida": config.get("medida"),
            "unidade_medida": _unidade(config),
            "tamanhos": config.get("tamanhos", []),
            "tipos": [{"valor": t, "nome": _nome_do_tipo(t), "descricao": NOMES_DOS_TIPOS.get(t, (t, None))[1]}
                      for t in tipos],
            "formas": config.get("formas", []),
            "valor_obrigatorio": bool(config.get("obrigatorio")),
            "uso": pergunta_de_uso_da_categoria(categoria),
        })
    return lista


def _equivalentes(con, categoria, tipo, medida):
    regra = EQUIVALENCIA.get(categoria, {})
    tolerancia = max(regra.get("tolerancia", TOLERANCIA_ESTIMATIVA), TOLERANCIA_ESTIMATIVA)
    filtro_tipo = bool(regra.get("mesmo_tipo") and tipo)
    sql_tipo = " AND tipo = ?" if filtro_tipo else ""
    params_tipo = [tipo] if filtro_tipo else []
    if medida is None:
        sql = "SELECT * FROM aparelhos WHERE categoria = ? AND origem_dado = 'informado'" + sql_tipo
        return banco.consulta(con, sql, [categoria, *params_tipo]), None, filtro_tipo
    candidatos = pd.DataFrame()
    for fator in AMPLIACOES_ESTIMATIVA:
        margem = float(medida) * tolerancia * fator
        sql = ("SELECT * FROM aparelhos WHERE categoria = ? AND origem_dado = 'informado' "
               "AND capacidade BETWEEN ? AND ?" + sql_tipo)
        candidatos = banco.consulta(con, sql, [categoria, float(medida) - margem, float(medida) + margem, *params_tipo])
        if len(candidatos) >= MINIMO_EQUIVALENTES:
            return candidatos, tolerancia * fator, filtro_tipo
    return candidatos, tolerancia * AMPLIACOES_ESTIMATIVA[-1], filtro_tipo


def estimar_por_equivalentes(con, categoria, tipo=None, medida=None, valor_etiqueta=None,
                             horas_dia=None, ciclos_mes=None, velocidade=None, campo_etiqueta=None):
    config = ESTIMAVEIS.get(categoria)
    if config is None or config.get("especial"):
        raise ValueError(f"categoria {categoria} nao tem esta estimativa")
    uso = {"horas_dia": horas_dia, "ciclos_mes": ciclos_mes, "velocidade": velocidade}
    base = {"categoria": categoria, "nome": config["nome"], "tipo": tipo or None}

    if valor_etiqueta is not None:
        formas = {f["campo"]: f for f in config["formas"]}
        forma = formas.get(campo_etiqueta or config["formas"][0]["campo"])
        if forma is None:
            raise ValueError(f"para {config['nome']} informe: {', '.join(f['nome'] for f in formas.values())}")
        if not 0 < valor_etiqueta <= forma["maximo"]:
            raise ValueError(f"{forma['rotulo']} precisa estar entre 0 e {forma['maximo']:g} {forma['unidade']}")
        aparelho = {**{c: math.nan for c in COLUNAS_NUM}, "categoria": categoria, forma["campo"]: float(valor_etiqueta)}
        if forma["campo"] == "potencia_w":
            uso["velocidade"] = None
        consumo = consumo_mensal_kwh(aparelho, **uso)
        return {**base, **consumo, "kwh_min": consumo["kwh_mes"], "kwh_max": consumo["kwh_mes"],
                "metodo": f"{forma['nome']}: {valor_etiqueta:g} {forma['unidade']}; {consumo['metodo']}",
                "capacidade": medida if config.get("medida") else float(valor_etiqueta),
                "detalhe": _detalhe_estimado(config, tipo, medida) or f"{valor_etiqueta:g} {forma['unidade']}",
                "pelos_parecidos": False,
                "aproximado": consumo["premissa"], "avisos": [], "fonte": "valor informado pelo usuário"}

    if config.get("obrigatorio"):
        raise ValueError(f"informe a {config['formas'][0]['rotulo'].lower()} do aparelho")
    if config.get("medida") and (medida is None or medida <= 0):
        raise ValueError(f"informe {config['medida'].lower()} ou o valor escrito no aparelho")
    candidatos, tolerancia, filtrou_tipo = _equivalentes(con, categoria, tipo, medida if config.get("medida") else None)
    validos = []
    for _, c in candidatos.iterrows():
        try:
            consumo_mensal_kwh(c, **uso)
        except ValueError:
            continue
        validos.append(c)
    if not validos:
        raise ValueError("nao ha modelos parecidos no catalogo para estimar; informe o valor escrito no aparelho")
    numeros = pd.DataFrame(validos)[COLUNAS_NUM].astype(float)

    def referencia(q):
        return consumo_mensal_kwh({**numeros.quantile(q).to_dict(), "categoria": categoria}, **uso)

    poucos = len(numeros) < MINIMO_QUARTIS
    central = referencia(0.5)
    menor, maior = (referencia(0), referencia(1)) if poucos else (referencia(0.25), referencia(0.75))
    partes = []
    if tolerancia is not None:
        nome_medida = config["medida"].split(" (")[0].lower()
        partes.append(f"{nome_medida} até {tolerancia:.0%} acima ou abaixo de {_detalhe_estimado(config, None, medida)}")
    if filtrou_tipo:
        partes.append(f"do tipo {_nome_do_tipo(tipo).lower()}")
    criterio = " e ".join(partes) or "todos os modelos do catálogo"
    if len(numeros) == 1:
        faixa = "só 1 modelo parecido, sem faixa"
    elif poucos:
        faixa = "faixa entre o menor e o maior valor"
    else:
        faixa = "faixa entre o 1º e o 3º quartil"
    return {
        **base,
        "kwh_mes": central["kwh_mes"],
        "kwh_min": menor["kwh_mes"],
        "kwh_max": maior["kwh_mes"],
        "metodo": (f"mediana de {len(numeros)} modelos atuais parecidos do Inmetro ({criterio}); "
                   f"{faixa}. Uso: {central['metodo']}"),
        "capacidade": float(medida) if tolerancia is not None else None,
        "detalhe": _detalhe_estimado(config, tipo, medida if tolerancia is not None else None),
        "premissa": central["premissa"],
        "aproximado": True,
        "avisos": [AVISO_EQUIVALENTES],
        "fonte": "catálogo do Inmetro (modelos equivalentes)",
        "pelos_parecidos": True,
    }


def _detalhe_estimado(config, tipo, medida):
    partes = [_nome_do_tipo(tipo)] if tipo else []
    if medida is not None:
        partes.append(f"{medida:g} {_unidade(config)}")
    return ", ".join(partes)


# 4. Aparelho mais economico ------------------------------------------------------

def _candidatos(con, atual, regra, velocidade):
    """Modelos que fazem o mesmo servico (ver EQUIVALENCIA) e tem consumo vindo do Inmetro."""
    medida = atual[regra["medida"]]
    if pd.isna(medida):
        return None
    margem = float(medida) * regra["tolerancia"]
    categorias = regra["categorias"]
    # regra["medida"] e a velocidade vem de listas fixas do codigo, nunca de texto do usuario
    sql = (f"SELECT * FROM aparelhos WHERE categoria IN ({', '.join('?' for _ in categorias)}) "
           f"AND id <> ? AND origem_dado = 'informado' AND {regra['medida']} BETWEEN ? AND ?")
    params = [*categorias, int(atual["id"]), float(medida) - margem, float(medida) + margem]
    tipo = _texto(atual["tipo"])
    if regra["mesmo_tipo"] and tipo:
        sql += " AND tipo = ?"
        params.append(tipo)
    if velocidade in VELOCIDADES:  # ventilador: precisa ter o consumo na mesma velocidade
        sql += f" AND kwh_mes_{velocidade} IS NOT NULL"
    return banco.consulta(con, sql, params)


def _texto(valor):
    return valor.strip() if isinstance(valor, str) else ""


def _resumo(aparelho):
    return {"id": int(aparelho["id"]), "categoria": aparelho["categoria"], "marca": aparelho["marca"],
            "modelo": aparelho["modelo"], "detalhe": _texto(aparelho["detalhe"]), "tipo": _texto(aparelho["tipo"])}


def sugerir_alternativas(con, aparelho_id, distribuidora_id=None, tarifa_manual=None,
                         horas_dia=None, ciclos_mes=None, velocidade=None, limite=5):
    """Modelos equivalentes que gastam pelo menos 5% menos, com o mesmo uso e a mesma tarifa.
    O catalogo nao tem precos: o payback sai em comparar(), com o preco que o usuario digitar."""
    atual = aparelho_por_id(con, aparelho_id)
    uso = {"horas_dia": horas_dia, "ciclos_mes": ciclos_mes, "velocidade": velocidade}
    kwh_atual = consumo_mensal_kwh(atual, **uso)["kwh_mes"]
    return _sugerir(con, atual, kwh_atual, uso, distribuidora_id, tarifa_manual, limite)


def sugerir_para_estimado(con, categoria, capacidade, kwh_mes, tipo=None, nome=None, distribuidora_id=None,
                          tarifa_manual=None, horas_dia=None, ciclos_mes=None, velocidade=None, limite=5,
                          pelos_parecidos=False):
    """pelos_parecidos: o kwh_mes saiu da mediana dos modelos parecidos (sem o numero do aparelho), entao
    comparar com esses mesmos modelos e circular e a mensagem precisa dizer isso."""
    if kwh_mes <= 0:
        raise ValueError("o consumo do aparelho precisa ser maior que zero")
    atual = {"id": 0, "categoria": categoria, "marca": nome or ESTIMAVEIS.get(categoria, {}).get("nome", categoria),
             "modelo": "(estimativa)", "detalhe": "", "tipo": tipo or "",
             "capacidade": math.nan if capacidade is None else float(capacidade), "fluxo_lm": math.nan}
    regra = EQUIVALENCIA.get(categoria, {})
    if regra.get("medida") == "fluxo_lm" and capacidade:
        atual["fluxo_lm"] = float(capacidade) * _eficiencia_luminosa(con, categoria)
    uso = {"horas_dia": horas_dia, "ciclos_mes": ciclos_mes, "velocidade": velocidade}
    return _sugerir(con, atual, float(kwh_mes), uso, distribuidora_id, tarifa_manual, limite, pelos_parecidos)


def _eficiencia_luminosa(con, categoria):
    df = banco.consulta(con, "SELECT fluxo_lm / potencia_w AS lm_por_w FROM aparelhos WHERE categoria = ? "
                             "AND fluxo_lm > 0 AND potencia_w > 0", (categoria,))
    return float(df["lm_por_w"].median()) if len(df) else math.nan


def _sugerir(con, atual, kwh_atual, uso, distribuidora_id, tarifa_manual, limite, pelos_parecidos=False):
    velocidade = uso.get("velocidade")
    tarifa, _, _, _ = escolher_tarifa(con, distribuidora_id, tarifa_manual)
    resposta = {
        "atual": {**_resumo(atual), "kwh_mes": round(kwh_atual, 2), "custo_mes": round(kwh_atual * tarifa, 2)},
        "tarifa_kwh": round(tarifa, 5),
        "criterio": None,
        "mensagem": None,
        "suspeitos_descartados": 0,
        "sugestoes": [],
    }

    regra = EQUIVALENCIA.get(atual["categoria"])
    if regra is None:
        resposta["mensagem"] = SEM_SUGESTAO.get(
            atual["categoria"], "Ainda não sugerimos trocas para este tipo de aparelho.")
        return resposta
    resposta["criterio"] = regra["texto"]
    candidatos = _candidatos(con, atual, regra, velocidade)
    if candidatos is None:
        resposta["mensagem"] = ("Para achar modelos parecidos precisamos do tamanho do aparelho. "
                                "Calcule de novo informando o tamanho.")
        return resposta

    consumos = []
    for _, c in candidatos.iterrows():
        try:
            consumos.append((c, consumo_mensal_kwh(c, **uso)["kwh_mes"]))
        except ValueError:
            continue  # o modelo nao tem o dado que esse uso precisa
    mediana = float(pd.Series([kwh_atual] + [k for _, k in consumos]).median())

    sugestoes = []
    for c, kwh in consumos:
        if kwh < mediana * FRACAO_SUSPEITA:
            resposta["suspeitos_descartados"] += 1
            continue
        economia = kwh_atual - kwh
        if economia >= kwh_atual * ECONOMIA_MINIMA:
            sugestoes.append({
                **_resumo(c),
                "kwh_mes": round(kwh, 2),
                "custo_mes": round(kwh * tarifa, 2),
                "economia_kwh_mes": round(economia, 2),
                "economia_mes": round(economia * tarifa, 2),
                "economia_ano": round(economia * tarifa * 12, 2),
                "economia_percentual": round(economia / kwh_atual * 100, 1),
            })
    sugestoes.sort(key=lambda s: (s["kwh_mes"], s["marca"], s["modelo"]))
    # variacoes do mesmo modelo (ex.: cor ou voltagem) aparecem uma vez so
    vistos, unicas = set(), []
    for s in sugestoes:
        chave = (s["marca"].lower(), s["detalhe"], s["kwh_mes"])
        if chave not in vistos:
            vistos.add(chave)
            unicas.append(s)
    resposta["sugestoes"] = unicas[:limite]
    if not sugestoes and pelos_parecidos:
        resposta["mensagem"] = (
            "O gasto do seu aparelho foi calculado pelos modelos atuais parecidos, então ele sai igual a eles e "
            "nenhum aparece como mais econômico. Se o seu for antigo, pode gastar mais. Para comparar de verdade, "
            "calcule de novo com o número da etiqueta ou a potência escrita no aparelho.")
    elif not sugestoes:
        resposta["mensagem"] = "Este aparelho já está entre os mais econômicos do catálogo do Inmetro."
    return resposta


def comparar(con, aparelho_id, alternativa_id, distribuidora_id=None, tarifa_manual=None,
             horas_dia=None, ciclos_mes=None, velocidade=None, preco_novo=None):
    """Economia de trocar o aparelho atual pela alternativa e, com o preco, em quantos meses a troca se paga."""
    if int(aparelho_id) == int(alternativa_id):
        raise ValueError("escolha um modelo diferente do atual para comparar")
    uso = {"horas_dia": horas_dia, "ciclos_mes": ciclos_mes, "velocidade": velocidade}
    atual = calcular(con, aparelho_id, distribuidora_id, tarifa_manual, registrar=False, **uso)
    novo = calcular(con, alternativa_id, distribuidora_id, tarifa_manual, registrar=False, **uso)
    return _comparacao(atual, novo, preco_novo)


def comparar_estimado(con, categoria, kwh_mes, alternativa_id, nome=None, distribuidora_id=None,
                      tarifa_manual=None, horas_dia=None, ciclos_mes=None, velocidade=None, preco_novo=None):
    if kwh_mes <= 0:
        raise ValueError("o consumo do aparelho precisa ser maior que zero")
    uso = {"horas_dia": horas_dia, "ciclos_mes": ciclos_mes, "velocidade": velocidade}
    novo = calcular(con, alternativa_id, distribuidora_id, tarifa_manual, registrar=False, **uso)
    tarifa, nome_distribuidora, uf, origem = escolher_tarifa(con, distribuidora_id, tarifa_manual)
    aparelho = {"categoria": categoria, "marca": nome or ESTIMAVEIS.get(categoria, {}).get("nome", categoria),
                "modelo": "(estimativa)", "detalhe": "", "origem_dado": None}
    consumo = {"kwh_mes": float(kwh_mes), "metodo": "estimativa feita no app", "premissa": False}
    atual = montar_resultado(aparelho, consumo, tarifa, nome_distribuidora, origem, uf, horas_dia,
                             tarifa_do_usuario=tarifa_manual is not None)
    atual["fonte_dados"] = "estimativa"
    return _comparacao(atual, novo, preco_novo)


def _comparacao(atual, novo, preco_novo):
    permitidas = EQUIVALENCIA.get(atual["categoria"], {}).get("categorias", [atual["categoria"]])
    if novo["categoria"] not in permitidas:
        raise ValueError("os dois aparelhos precisam fazer o mesmo servico para comparar")

    economia_mes = atual["custo_mes"] - novo["custo_mes"]
    payback = None
    if preco_novo is not None:
        if preco_novo <= 0:
            raise ValueError("o preco precisa ser maior que zero")
        payback = {"preco_novo": round(float(preco_novo), 2), "meses": None, "anos": None}
        if economia_mes > 0:
            meses = preco_novo / economia_mes
            payback.update(meses=round(meses, 1), anos=round(meses / 12, 1))
            payback["texto"] = (
                f"A troca se paga em cerca de {meses:.0f} meses ({meses / 12:.1f} anos) so com a economia na conta de luz."
                if meses >= 1 else "A troca se paga em menos de um mes.")
        else:
            payback["texto"] = "O modelo novo nao gasta menos, entao a troca nao se paga pela conta de luz."
    return {
        "atual": atual,
        "novo": novo,
        "economia_kwh_mes": round(atual["kwh_mes"] - novo["kwh_mes"], 2),
        "economia_mes": round(economia_mes, 2),
        "economia_ano": round(economia_mes * 12, 2),
        "payback": payback,
        "avisos": [
            ("Payback simples: preco do modelo novo dividido pela economia mensal, sem juros, "
             "sem a venda do aparelho antigo e sem reajuste da tarifa."),
            "O catálogo do Inmetro não tem preços: o valor usado é o que você digitou.",
        ],
    }
