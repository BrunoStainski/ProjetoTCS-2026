"""
Traducao para o ingles dos textos FIXOS que a API mostra (constantes e configuracoes).

A chave e o texto em portugues exatamente como esta no codigo ou nos dados; o valor, o texto em ingles.
idioma.t(texto) usa este dicionario quando a requisicao pede ingles. Texto montado na hora (com
numeros) nao entra aqui: fica com idioma.tr(pt, en) no proprio lugar.

Mudou um texto em portugues? Mude a chave aqui tambem: tests/test_idioma.py falha se algum texto
fixo ficar sem traducao.
"""

EN = {
    # --- calculadora_residencial.EQUIVALENCE (criterio da sugestao de troca) ---
    "mesmo tipo e volume parecido (até 15% de diferença)": "same type and similar volume (up to 15% difference)",
    "tela do mesmo tamanho (até 5% de diferença)": "screen of the same size (up to 5% difference)",
    "mesmo tipo e mesma capacidade em BTU/h (até 5% de diferença)":
        "same type and same capacity in BTU/h (up to 5% difference)",
    "hélice de diâmetro parecido (até 10% de diferença)": "blades of similar diameter (up to 10% difference)",
    "diâmetro parecido (até 10% de diferença)": "similar diameter (up to 10% difference)",
    "mesmo tipo e capacidade parecida em kg (até 15% de diferença)":
        "same type and similar capacity in kg (up to 15% difference)",
    "mesma luminosidade em lumens (até 10% de diferença)": "same brightness in lumens (up to 10% difference)",
    "mesma luminosidade em lumens (até 10% de diferença), incluindo lâmpadas LED":
        "same brightness in lumens (up to 10% difference), including LED bulbs",
    "motor de mesma potência (cv); confira vazão e altura com o fabricante":
        "motor of the same power (hp); check the flow rate and head with the manufacturer",

    # --- calculadora_residencial.ESTIMAVEIS: nomes ---
    "Geladeira ou freezer": "Fridge or freezer",
    "Máquina de lavar": "Washing machine",
    "Ar-condicionado": "Air conditioner",
    "Televisor": "TV",
    "Ventilador de mesa, coluna ou parede": "Desk, pedestal or wall fan",
    "Ventilador de teto": "Ceiling fan",
    "Micro-ondas": "Microwave",
    "Bomba d'água": "Water pump",
    "Chuveiro elétrico": "Electric shower",
    "Lâmpada LED": "LED bulb",
    "Lâmpada fluorescente": "Fluorescent bulb",
    "Lâmpada de vapor de sódio": "Sodium vapor lamp",
    # medidas (a unidade entre parenteses vira a unidade do campo)
    "Capacidade de lavagem (kg)": "Washing capacity (kg)",
    "Capacidade (BTU/h)": "Capacity (BTU/h)",
    "Tamanho da tela (polegadas)": "Screen size (inches)",
    "Diâmetro da hélice (cm)": "Blade diameter (cm)",
    "Capacidade (litros)": "Capacity (liters)",
    "Potência do motor (cv)": "Motor power (hp)",
    # numero escrito no aparelho (formas)
    "Etiqueta amarela do Inmetro": "Inmetro yellow energy label",
    "Consumo de energia": "Energy consumption",
    "Potência escrita no aparelho": "Power written on the appliance",
    "Potência": "Power",
    "kWh/ciclo": "kWh/cycle",
    "kWh/mês": "kWh/month",
    "Adesivo amarelo colado na máquina, na linha \"Consumo de energia\".":
        "Yellow sticker on the machine, on the \"Consumo de energia\" (energy consumption) line.",
    "Etiqueta branca com o modelo, na lateral do aparelho (no split, na parte de dentro).":
        "White label with the model, on the side of the unit (on a split, on the indoor unit).",
    "Etiqueta atrás da TV, com o modelo e a voltagem. Toda TV tem, até as antigas.":
        "Label on the back of the TV, with the model and voltage. Every TV has one, even old ones.",
    "Adesivo amarelo, só nas TVs mais novas.": "Yellow sticker, only on newer TVs.",
    "Etiqueta embaixo da base ou atrás do motor, com a voltagem e a potência.":
        "Label under the base or behind the motor, with the voltage and power.",
    "Etiqueta em cima do motor ou na caixa, com a voltagem e a potência.":
        "Label on top of the motor or on the box, with the voltage and power.",
    "Etiqueta atrás do aparelho ou na parte de dentro da porta.":
        "Label on the back of the appliance or inside the door.",
    "Placa de metal presa no motor.": "Metal plate attached to the motor.",
    "Na embalagem ou gravada no próprio chuveiro.": "On the box or engraved on the shower itself.",
    "Escrita na própria lâmpada ou na caixa.": "Written on the bulb itself or on the box.",
    "Use a potência elétrica (consumida). Não use a capacidade de refrigeração, que é um número bem maior.":
        "Use the electrical (input) power. Do not use the cooling capacity, which is a much larger number.",
    "Use a potência consumida (de entrada), que é a maior. A potência de saída, de cozimento, é menor.":
        "Use the input power, which is the larger one. The output (cooking) power is smaller.",
    "Se estiver em kW, multiplique por 1.000 (0,75 kW = 750 W).":
        "If it is in kW, multiply by 1,000 (0.75 kW = 750 W).",
    "Use a potência da posição que você mais usa. A de inverno é a maior.":
        "Use the power of the setting you use most. The winter setting is the highest.",

    # --- calculadora_residencial.TYPE_NAMES (nome e descricao) ---
    "Automática que abre por cima": "Automatic, top-loading",
    "Tampa em cima. Lava, enxágua e centrifuga sozinha.": "Lid on top. It washes, rinses and spins on its own.",
    "Tanquinho ou semiautomática": "Twin tub or semi-automatic",
    "Lava, mas você tira a água ou muda a roupa de lugar.":
        "It washes, but you drain the water or move the clothes yourself.",
    "Automática que abre na frente": "Automatic, front-loading",
    "Porta redonda na frente.": "Round door on the front.",
    "Lava e seca": "Washer-dryer",
    "Porta na frente. Também seca a roupa.": "Door on the front. It also dries the clothes.",
    "Split de parede": "Wall-mounted split",
    "Aparelho comprido no alto da parede e uma caixa do lado de fora.":
        "A long unit high on the wall and a box outside.",
    "De janela": "Window unit",
    "Uma caixa só, encaixada na parede ou na janela.": "A single box, fitted into the wall or the window.",
    "Split de piso-teto": "Floor-ceiling split",
    "Aparelho grande preso no teto ou embaixo, na parede.": "A large unit fixed to the ceiling or low on the wall.",
    "Split cassete": "Cassette split",
    "Embutido no forro do teto, solta ar para os quatro lados.":
        "Built into the ceiling, it blows air in all four directions.",

    # --- tipos do Inmetro onde sao padronizados (aparecem nas sugestoes de troca) ---
    "Top Load (automatica)": "Top load (automatic)",
    "Semiautomaticas": "Semi-automatic",
    "Front Load (automatica)": "Front load (automatic)",
    "Front Load (lava e seca)": "Front load (washer-dryer)",
    "Split Hi-Wall": "Split (wall-mounted)",
    "Janela": "Window",
    "Split Piso-teto": "Split (floor-ceiling)",
    "Split Cassete": "Split (cassette)",
    "Refrigerador-Congelador": "Fridge-freezer",
    "Refrigerador": "Refrigerator",
    "Frigobar": "Mini fridge",
    "Congelador Vertical": "Upright freezer",
    "Congelador Horizontal": "Chest freezer",
    # categorias da Portaria Inmetro 20/2006 (estimativa.LINES_2006, aparecem no "Como calculamos")
    "Combinado": "Fridge-freezer",
    "Combinado frost free": "Frost-free fridge-freezer",
    "Congelador vertical": "Upright freezer",
    "Congelador vertical frost free": "Frost-free upright freezer",
    "Congelador horizontal": "Chest freezer",

    # --- avisos e mensagens fixas ---
    "Gasto aproximado pelos modelos atuais parecidos do catálogo do Inmetro. Aparelhos antigos "
    "costumam gastar mais que os atuais; com o valor da etiqueta o cálculo fica exato.":
        "Approximate cost based on similar current models in Inmetro's catalog. Old appliances "
        "usually use more than current ones; with the value on the label the calculation is exact.",
    "Chuveiros elétricos têm eficiência parecida: um modelo de menor potência só esquenta "
    "menos a água. Para economizar, reduza o tempo de banho ou use a posição verão.":
        "Electric showers have similar efficiency: a lower-power model just heats the water less. "
        "To save, take shorter showers or use the summer setting.",
    "O Inmetro informa só a potência do micro-ondas. Um modelo de menor potência demora mais "
    "para aquecer, então a economia não pode ser estimada só com esses dados.":
        "Inmetro only reports the microwave's power. A lower-power model takes longer to heat, "
        "so the savings cannot be estimated from this data alone.",
    "O catálogo de vapor de sódio não traz a luminosidade (lumens), então não dá "
    "para achar uma lâmpada equivalente.":
        "The sodium vapor catalog does not include brightness (lumens), so an equivalent lamp cannot be found.",
    "Ainda não sugerimos trocas para este tipo de aparelho.":
        "We do not suggest replacements for this type of appliance yet.",
    "Este modelo só tem o consumo medido pela regra antiga do Inmetro (anterior a 2021); o valor foi "
    "convertido para a regra atual para comparar com os modelos novos, então é aproximado.":
        "This model only has its consumption measured under Inmetro's old rule (before 2021); the value was "
        "converted to the current rule to compare with new models, so it is approximate.",
    "Estimativa sem impostos (ICMS, PIS/COFINS), bandeira tarifária e iluminação "
    "pública. O uso real muda o resultado.":
        "Estimate without taxes (ICMS, PIS/COFINS), tariff flag surcharges and the public lighting fee. "
        "Real use changes the result.",
    "Calculado com a tarifa que você informou. O uso real muda o resultado.":
        "Calculated with the rate you entered. Real use changes the result.",
    # estimativa.py
    "Gasto aproximado: o modelo não está no catálogo do Inmetro, então o consumo foi estimado "
    "pelo tipo, volume e ano de compra. O valor real pode estar em qualquer ponto da faixa.":
        "Approximate cost: the model is not in Inmetro's catalog, so the consumption was estimated "
        "from the type, volume and year of purchase. The real value can be anywhere in the range.",
    "Consumo da etiqueta do aparelho, convertido para a metodologia de ensaio atual e ajustado "
    "pelo desgaste da idade.":
        "Consumption from the appliance's label, converted to the current test method and adjusted "
        "for wear with age.",
    "A potência usada é a típica da categoria (estimativa do grupo). Informe a da etiqueta "
    "do aparelho para um valor mais preciso.":
        "The power used is the typical one for this category (our team's estimate). Enter the one on "
        "the appliance's label for a more accurate value.",
    "geladeira 1 porta": "one-door fridge",
    "frigobar": "mini fridge",
    "geladeira duplex": "two-door fridge",
    "freezer vertical": "upright freezer",
    "freezer horizontal": "chest freezer",
    # ml_pipeline.py
    "Perfil estimado por um modelo treinado com residências sintéticas; "
    "serve como referência, não como avaliação oficial.":
        "Profile estimated by a model trained on synthetic homes; it is a reference, not an official assessment.",
    # rag_agent.py
    "Dicas do Inmetro e da Cemig; valores do iamp, sem impostos e bandeira.":
        "Tips from Inmetro and Cemig; values from Iamp, without taxes and tariff flags.",
    "Dicas escritas por IA com base no Inmetro e na Cemig; valores do iamp. Confira as fontes.":
        "Tips written by AI based on Inmetro and Cemig; values from Iamp. Check the sources.",

    # --- rag_agent.NAMES ("O que mais pesa" no Eco-Coach); a busca continua com o nome em portugues ---
    "geladeira": "fridge",
    "televisão": "TV",
    "ar-condicionado": "air conditioner",
    "ventilador": "fan",
    "ventilador de teto": "ceiling fan",
    "chuveiro elétrico": "electric shower",
    "lâmpadas LED": "LED bulbs",
    "lâmpadas fluorescentes": "fluorescent bulbs",
    "lâmpadas de vapor de sódio": "sodium vapor lamps",
    "micro-ondas": "microwave",
    "máquina de lavar roupa": "washing machine",
    "bomba d'água": "water pump",
    "air fryer (fritadeira elétrica)": "air fryer",
    "secador de cabelo": "hair dryer",
    "ferro de passar roupa": "clothes iron",
    "sanduicheira": "sandwich maker",
    # eletroportateis sem nome em NAMES (o nome sai da categoria, sem o "_")
    "liquidificador": "blender",
    "cafeteira eletrica": "coffee maker",
    "chaleira eletrica": "electric kettle",
    "forno eletrico": "countertop electric oven",
    "aspirador po": "vacuum cleaner",
    "torradeira": "toaster",

    # --- eletroportateis (datasets/processed/eletroportateis.csv, tabela portateis) ---
    "Air fryer": "Air fryer",
    "Secador de cabelo": "Hair dryer",
    "Ferro de passar": "Clothes iron",
    "Sanduicheira": "Sandwich maker",
    "Liquidificador": "Blender",
    "Cafeteira elétrica": "Coffee maker",
    "Chaleira elétrica": "Electric kettle",
    "Forno elétrico de bancada": "Countertop electric oven",
    "Aspirador de pó": "Vacuum cleaner",
    "Torradeira": "Toaster",

    # --- fonte da tarifa (tarifas_aneel.py) ---
    "ANEEL – tarifas homologadas, B1 residencial": "ANEEL – approved tariffs, B1 residential",
}
