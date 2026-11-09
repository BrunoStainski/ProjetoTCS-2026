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

import pandas as pd

import banco
from calculadora_residencial import (
    ECONOMIA_MINIMA, EQUIVALENCIA, FRACAO_SUSPEITA, HORAS_OPCIONAIS, LIMITE_BUSCA, PREMISSAS, SEM_SUGESTAO,
    consumo_mensal_kwh, montar_resultado, normalizar,
)

VELOCIDADES = ("baixa", "media", "alta")


def _registros(df):
    """DataFrame -> lista de dicts, trocando NaN por None (pronto para virar JSON)."""
    return df.astype(object).where(df.notna(), None).to_dict("records")


# 1. Aparelho -------------------------------------------------------------------

def buscar_modelos(con, texto, categoria=None, limite=LIMITE_BUSCA):
    """Busca por marca e/ou modelo. Todos os termos digitados precisam aparecer."""
    termos = normalizar(texto).split()
    if not termos:
        return []
    sql = "SELECT id, categoria, marca, modelo, detalhe FROM aparelhos WHERE "
    sql += " AND ".join("busca LIKE ?" for _ in termos)
    params = [f"%{t}%" for t in termos]
    if categoria:
        sql += " AND categoria = ?"
        params.append(categoria)
    sql += " ORDER BY categoria, marca, modelo LIMIT ?"
    params.append(limite)
    return _registros(banco.consulta(con, sql, params))


def aparelho_por_id(con, aparelho_id):
    df = banco.consulta(con, "SELECT * FROM aparelhos WHERE id = ?", (int(aparelho_id),))
    if df.empty:
        raise ValueError(f"aparelho {aparelho_id} nao existe")
    return df.iloc[0]


def dados_de_uso(con, aparelho_id):
    """Diz o que a tela precisa perguntar antes de calcular.
    pergunta: None, "velocidade", "ciclos" ou "horas"; padrao: valor sugerido (estimativa do grupo);
    opcional: True quando o usuario pode deixar em branco e ficar com o valor do Inmetro."""
    a = aparelho_por_id(con, aparelho_id)
    velocidades = [v for v in VELOCIDADES if pd.notna(a[f"kwh_mes_{v}"])]
    if velocidades:
        return {"pergunta": "velocidade", "opcoes": velocidades,
                "padrao": "media" if "media" in velocidades else velocidades[-1]}
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
    aparelho = {"categoria": consumo["categoria"], "marca": marca or "Nao informado",
                "modelo": modelo or "Estimado", "detalhe": consumo["detalhe"], "origem_dado": None}
    resultado = montar_resultado(aparelho, consumo, tarifa, nome, origem, uf, consumo.get("horas_dia"),
                                 tarifa_do_usuario=tarifa_manual is not None)
    resultado["avisos"] += consumo["avisos"]
    resultado["aproximado"] = consumo["aproximado"]
    resultado["fonte_dados"] = consumo["fonte"]
    if "kwh_min" in consumo:
        resultado["kwh_min"] = round(consumo["kwh_min"], 2)
        resultado["kwh_max"] = round(consumo["kwh_max"], 2)
        resultado["custo_min_mes"] = round(consumo["kwh_min"] * tarifa, 2)
        resultado["custo_max_mes"] = round(consumo["kwh_max"] * tarifa, 2)
    if registrar:
        banco.registrar_consulta(con, resultado, horas_dia=consumo.get("horas_dia"))
    return resultado


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
            atual["categoria"], "Ainda nao sugerimos trocas para este tipo de aparelho.")
        return resposta
    resposta["criterio"] = regra["texto"]
    candidatos = _candidatos(con, atual, regra, velocidade)
    if candidatos is None:
        resposta["mensagem"] = "Este modelo nao tem a medida usada na comparacao, entao nao da para achar um equivalente."
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
    if not sugestoes:
        resposta["mensagem"] = "Este modelo ja esta entre os mais economicos do catalogo do Inmetro."
    return resposta


def comparar(con, aparelho_id, alternativa_id, distribuidora_id=None, tarifa_manual=None,
             horas_dia=None, ciclos_mes=None, velocidade=None, preco_novo=None):
    """Economia de trocar o aparelho atual pela alternativa e, com o preco, em quantos meses a troca se paga."""
    if int(aparelho_id) == int(alternativa_id):
        raise ValueError("escolha um modelo diferente do atual para comparar")
    uso = {"horas_dia": horas_dia, "ciclos_mes": ciclos_mes, "velocidade": velocidade}
    atual = calcular(con, aparelho_id, distribuidora_id, tarifa_manual, registrar=False, **uso)
    novo = calcular(con, alternativa_id, distribuidora_id, tarifa_manual, registrar=False, **uso)
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
            "O catalogo do Inmetro nao tem precos: o valor usado e o que voce digitou.",
        ],
    }
