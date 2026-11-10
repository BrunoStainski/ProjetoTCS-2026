---
name: regra-negocio-sugestao-troca
description: Regras de negócio para sugerir modelos mais econômicos equivalentes ao aparelho do usuário e calcular economia e payback da troca no iamp. Use ao alterar EQUIVALENCIA, SEM_SUGESTAO, servico.sugerir_alternativas, servico.comparar ou as rotas /sugestoes e /comparar.
---

# Regra de negócio: sugestão de troca e payback

Use esta skill ao implementar, alterar ou revisar as rotas `POST /sugestoes`, `POST /comparar` e suas versões `/estimado`. A lógica está em `servico.sugerir_alternativas`, `servico._sugerir`, `servico.comparar` e nas constantes de `calculadora_residencial.py`. O objetivo é recomendar só trocas honestas: mesmo serviço, mesmo uso, mesma tarifa, dado confiável.

## Equivalência (`EQUIVALENCIA`)

Um modelo só é candidato se fizer o mesmo serviço que o atual:

| Categoria do atual | Onde procurar | Medida parecida | Mesmo tipo do Inmetro |
|---|---|---|---|
| refrigerador | refrigerador | volume (`capacidade`) ±15% | sim |
| televisor | televisor | polegadas ±5% | não |
| ar_condicionado | ar_condicionado | BTU/h ±5% | sim |
| ventilador_de_mesa / de_teto | mesma categoria | diâmetro ±10% | não |
| maquina_de_lavar | maquina_de_lavar | kg ±15% | sim |
| lampada_led | lampada_led | lumens (`fluxo_lm`) ±10% | não |
| lampada_fluorescente | lampada_led **e** fluorescente | lumens ±10% | não |
| bomba | bomba | mesma potência em cv (tolerância 0) | não |

`mesmo_tipo` só é exigido onde o Inmetro padroniza o tipo. Cada entrada tem um `texto` que o app mostra explicando o critério; mantenha o texto coerente ao mudar a tolerância.

## Filtros obrigatórios

- Só modelos com `origem_dado = 'informado'`: nada imputado na limpeza nem `convertido da metodologia antiga do Inmetro` (a conversão exagerava a economia).
- Economia mínima de 5% (`ECONOMIA_MINIMA`) em relação ao consumo do atual, calculado com o **mesmo uso** (horas, ciclos, velocidade) e a **mesma tarifa** do atual.
- Consumo abaixo de 40% da mediana dos equivalentes (`FRACAO_SUSPEITA`) é descartado como erro de digitação do Inmetro. Caso real que motivou a regra: HISENSE RS3P428NEDA, versão 127 V com 2,8 kWh contra 28,0 kWh da outra versão.
- Variações do mesmo modelo (marca + detalhe + kWh iguais, ex.: cor ou voltagem) aparecem uma vez.
- Ordenar da maior para a menor economia; `limite` padrão 5.

## Sem sugestão (`SEM_SUGESTAO`)

Chuveiro, micro-ondas e lâmpada de vapor de sódio não recebem sugestão e a resposta traz o **motivo** para o app mostrar (eficiência parecida, só potência informada, sem lumens no dataset). Eletroportáteis também não têm sugestão (não têm etiqueta do Inmetro); o app oferece as dicas do Eco-Coach (`POST /eco-coach/aparelho`). Ao incluir uma categoria nova, decidir explicitamente entre `EQUIVALENCIA` e `SEM_SUGESTAO`.

## Comparação e payback (`servico.comparar`, `_comparacao`)

- Entrada: aparelho atual, `alternativa_id`, mesmo uso e tarifa, e `preco_novo` opcional em reais (o catálogo do Inmetro não tem preço; o usuário digita o que encontrou).
- `economia_mes = custo_atual − custo_novo`; `economia_ano = × 12`.
- `payback_meses = preco_novo / economia_mes`, calculado em Python na API, nunca pelo LLM nem pelo app. Sem economia positiva, a troca "não se paga" e a resposta diz isso.
- Payback simples: sem juros, sem revenda do antigo, sem reajuste de tarifa. Esse limite está na documentação e deve continuar visível ao usuário.
- No app: payback verde até 60 meses, amarelo acima, vermelho se não se paga (corte do grupo). Trocas avaliadas podem entrar em `casa.trocas` (máximo 5) e vão no corpo do `/eco-coach` com exatamente a economia e o payback calculados.

## Limites desta regra

Esta skill fixa os critérios de equivalência, os filtros de confiabilidade e a fórmula do payback. Não define preços de referência, financiamento, descarte do aparelho antigo nem ranking por marca. Mudança de tolerância ou de filtro exige teste em `tests/test_api.py` com caso concreto, atualização da tabela da seção 10 do `README.md` e do `CLAUDE.md`, e menção no `CHANGELOG.md`.
