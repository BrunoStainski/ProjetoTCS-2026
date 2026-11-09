PCI_GLP_KWH_KG = 12.8
POTENCIA_BOCA_KW = 1.75
RENDIMENTO_REFERENCIA_PCT = 63.0
CONSUMO_FORNO_PADRAO_KG_H = 0.12
KG_POR_BOTIJAO = 13
USO_PADRAO = {"horas_bocas_dia": 1.0, "horas_forno_dia": 0.25, "dias_mes": 30}

FONTE_FOGAO = "Inmetro, tabela de fogoes e fornos a gas (consumo do forno e rendimento das bocas)"
AVISO_BOCAS = ("O consumo das bocas usa uma boca media de 1,75 kW e o poder calorifico do GLP (cerca de "
               "12,8 kWh por kg), premissas do grupo; o Inmetro informa so o rendimento das bocas.")
AVISO_SEM_MODELO = "Sem o modelo do fogao, usamos os valores medianos dos fogoes do catalogo do Inmetro."
AVISO_USO_PADRAO = "O tempo de uso e uma estimativa do grupo. Informe o seu para um valor mais preciso."
AVISO_PRECO = "Preco medio do GLP no estado (ANP); o preco do seu botijao pode ser diferente."


def _tempo(horas):
    total = round(horas * 60)
    h, m = divmod(total, 60)
    return f"{m} min" if h == 0 else (f"{h} h" if m == 0 else f"{h} h {m} min")


def kg_por_hora_da_boca(rendimento_pct=None):
    rendimento = rendimento_pct or RENDIMENTO_REFERENCIA_PCT
    return POTENCIA_BOCA_KW / PCI_GLP_KWH_KG * RENDIMENTO_REFERENCIA_PCT / rendimento


def consumo_gas(fogao=None, horas_bocas_dia=None, horas_forno_dia=None, dias_mes=None):
    usados = {
        "horas_bocas_dia": USO_PADRAO["horas_bocas_dia"] if horas_bocas_dia is None else horas_bocas_dia,
        "horas_forno_dia": USO_PADRAO["horas_forno_dia"] if horas_forno_dia is None else horas_forno_dia,
        "dias_mes": USO_PADRAO["dias_mes"] if dias_mes is None else dias_mes,
    }
    if not 0 <= usados["horas_bocas_dia"] <= 24 or not 0 <= usados["horas_forno_dia"] <= 24:
        raise ValueError("o tempo de uso por dia precisa estar entre 0 e 24 horas")
    if not 0 <= usados["dias_mes"] <= 31:
        raise ValueError("dias de uso por mes precisa estar entre 0 e 31")

    rendimento = (fogao or {}).get("rendimento_pct")
    forno_kg_h = (fogao or {}).get("consumo_forno_kg_h") or CONSUMO_FORNO_PADRAO_KG_H
    boca_kg_h = kg_por_hora_da_boca(rendimento)
    kg_bocas = boca_kg_h * usados["horas_bocas_dia"] * usados["dias_mes"]
    kg_forno = forno_kg_h * usados["horas_forno_dia"] * usados["dias_mes"]

    avisos = [AVISO_BOCAS]
    if not fogao:
        avisos.append(AVISO_SEM_MODELO)
    if None in (horas_bocas_dia, horas_forno_dia, dias_mes):
        avisos.append(AVISO_USO_PADRAO)
    metodo = (f"bocas: {boca_kg_h:.3f} kg/h (rendimento {rendimento or RENDIMENTO_REFERENCIA_PCT:g}%) x "
              f"{_tempo(usados['horas_bocas_dia'])}/dia; forno: {forno_kg_h:g} kg/h x "
              f"{_tempo(usados['horas_forno_dia'])}/dia; x {usados['dias_mes']:g} dias")
    return {"kg_mes": kg_bocas + kg_forno, "kg_bocas": kg_bocas, "kg_forno": kg_forno,
            "metodo": metodo, "avisos": avisos, **usados}


def resultado_gas(consumo, preco_kg, origem_preco, fogao=None, uf=None):
    if preco_kg <= 0:
        raise ValueError("o preco do gas precisa ser maior que zero")
    custo_mes = consumo["kg_mes"] * preco_kg
    botijoes = consumo["kg_mes"] / KG_POR_BOTIJAO
    return {
        "marca": (fogao or {}).get("marca") or "Fogão a gás",
        "modelo": (fogao or {}).get("modelo") or "(estimativa)",
        "detalhe": (fogao or {}).get("detalhe") or "",
        "uf": uf or "-",
        "kg_mes": round(consumo["kg_mes"], 2),
        "kg_bocas": round(consumo["kg_bocas"], 2),
        "kg_forno": round(consumo["kg_forno"], 2),
        "botijoes_mes": round(botijoes, 2),
        "dias_por_botijao": round(30 / botijoes) if botijoes > 0 else None,
        "preco_kg": round(float(preco_kg), 4),
        "preco_botijao": round(float(preco_kg) * KG_POR_BOTIJAO, 2),
        "origem_preco": origem_preco,
        "custo_mes": round(custo_mes, 2),
        "custo_ano": round(custo_mes * 12, 2),
        "metodo": consumo["metodo"],
        "avisos": consumo["avisos"],
        "fonte_dados": FONTE_FOGAO if fogao else "valores medianos do catalogo do Inmetro",
    }
