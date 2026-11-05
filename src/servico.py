"""
Funcoes que a interface do iamp usa. Servem para qualquer tela
(terminal, FastAPI, Streamlit...). Tudo le do PostgreSQL (ver banco.py).

Fluxo:
  1. buscar_modelos(con, "brastemp brm44")        -> lista de aparelhos para o usuario escolher
  2. dados_de_uso(con, aparelho_id)               -> se precisa perguntar horas, ciclos ou velocidade
  3. listar_distribuidoras(con, uf="PR")          -> distribuidoras com tarifa para escolher
     ou listar_distribuidoras(con, busca="copel")
  4. calcular(con, aparelho_id, distribuidora_id) -> resultado com R$/kWh e custo por mes
"""

import pandas as pd

import banco
from calculadora_residencial import (
    HORAS_OPCIONAIS, LIMITE_BUSCA, PREMISSAS, consumo_mensal_kwh, montar_resultado, normalizar,
)


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
    velocidades = [v for v in ("baixa", "media", "alta") if pd.notna(a[f"kwh_mes_{v}"])]
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


# 3. Calculo --------------------------------------------------------------------

def calcular(con, aparelho_id, distribuidora_id=None, tarifa_manual=None,
             horas_dia=None, ciclos_mes=None, velocidade=None, registrar=True):
    """Resultado final. Use distribuidora_id OU tarifa_manual (R$/kWh da conta de luz)."""
    aparelho = aparelho_por_id(con, aparelho_id)
    consumo = consumo_mensal_kwh(aparelho, horas_dia=horas_dia, ciclos_mes=ciclos_mes, velocidade=velocidade)

    if tarifa_manual is not None:
        if tarifa_manual <= 0:
            raise ValueError("a tarifa precisa ser maior que zero")
        tarifa, nome, uf, origem = float(tarifa_manual), "-", None, "informada pelo usuario (conta de luz)"
    elif distribuidora_id is not None:
        t = tarifa_por_id(con, distribuidora_id)
        tarifa, nome, uf, origem = float(t["tarifa_kwh"]), t["nome"], t["uf"], t["fonte"]
    else:
        raise ValueError("escolha uma distribuidora ou informe a tarifa da conta de luz")

    resultado = montar_resultado(aparelho, consumo, tarifa, nome, origem, uf, horas_dia,
                                 tarifa_do_usuario=tarifa_manual is not None)
    resultado["fonte_dados"] = "PostgreSQL"
    if registrar:
        banco.registrar_consulta(con, resultado, horas_dia=horas_dia,
                                 ciclos_mes=ciclos_mes, velocidade=velocidade)
    return resultado
