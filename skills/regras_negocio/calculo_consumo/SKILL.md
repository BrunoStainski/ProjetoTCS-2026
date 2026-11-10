---
name: regra-negocio-calculo-consumo
description: Regras de negócio do cálculo de consumo (kWh/mês) e custo (R$/mês) de um aparelho no iamp, com dados do Inmetro e tarifas da ANEEL, incluindo premissas de uso, avisos obrigatórios e estimativa fora do catálogo. Use ao alterar calculadora_residencial.py, estimativa.py, gas.py, servico.calcular ou as rotas /calcular.
---

# Regra de negócio: cálculo de consumo e custo

Use esta skill ao implementar, alterar ou revisar o cálculo do iamp. A regra vive em `src/calculadora_residencial.py` (`consumo_mensal_kwh`, `montar_resultado`) e é usada por `servico.calcular`, pelo app de terminal, pela seed do ML e por todas as rotas `/calcular*`. Mudar aqui muda tudo; confira os testes de `tests/test_calculadora.py` e `tests/test_api.py`.

## Entrada

- Um aparelho do catálogo (`aparelho_id`, tabela `aparelhos`) e a tarifa: `distribuidora_id` (tarifa B1 vigente em `vw_tarifa_vigente`) **ou** `tarifa_manual` em R$/kWh digitada da conta de luz. Nunca os dois; nenhum dos dois é erro `422`.
- Uso conforme `GET /aparelhos/{id}/uso`: `horas_dia` (0 a 24), `ciclos_mes` (não negativo) ou `velocidade` (`baixa`, `media`, `alta`). Fora do intervalo é `ValueError` com mensagem em português, que vira `422`.

## Ordem das regras de cálculo (`consumo_mensal_kwh`)

1. **Velocidade informada** e o Inmetro tem kWh/mês por velocidade (ventiladores): usa a coluna `kwh_mes_<velocidade>`.
2. **Horas opcionais** (`HORAS_OPCIONAIS`: ar-condicionado e TV) com horas informadas: ar usa `potencia_w × horas × dias / 1000` (potência a 35 °C em carga total, é um teto e o `metodo` diz isso); TV reescala o kWh/mês do Inmetro por regra de três com 6,59 h/dia (`HORAS_REFERENCIA_INMETRO`, premissa do grupo sem documento oficial).
3. **kWh/mês do Inmetro** (geladeira, TV, ar sem horas): usa o valor da tabela.
4. **kWh por ciclo** (máquina de lavar): `kwh_ciclo × ciclos_mes`; sem ciclos, usa `PREMISSAS` (12 ciclos).
5. **Só potência** (lâmpadas, micro-ondas, chuveiro, bomba): `potencia_w × horas_dia × 30 / 1000 + standby_kwh_mes`; sem horas, usa `PREMISSAS`. **Chuveiro não tem premissa**: o usuário é obrigado a informar o tempo de banho.
6. Aparelho sem nenhum dado de consumo é erro.

`DIAS_MES = 30`. Toda saída traz `kwh_mes`, `metodo` (texto que explica a conta, em português, com horas em "h e min") e `premissa` (`True` quando usou valor padrão do grupo).

## Custo e resultado (`montar_resultado`)

- `custo_mes = kwh_mes × tarifa_kwh`; `custo_ano = custo_mes × 12`, arredondados em duas casas.
- Com tarifa da distribuidora: `AVISO_PADRAO` ("sem impostos ICMS, PIS/COFINS, bandeira tarifária e iluminação pública"). Com tarifa do usuário: `AVISO_TARIFA_USUARIO`.
- `premissa = True` gera aviso de estimativa do grupo; `origem_dado` diferente de `informado` (imputado na limpeza ou `convertido da metodologia antiga do Inmetro`) gera o aviso correspondente. O app mostra todos.
- `registrar = True` (padrão só no `/calcular`) grava em `consultas`: aparelho, uso, tarifa e resultado, **sem dados pessoais**. Testes mandam `registrar=False`.
- Exemplo de referência que não pode mudar sem decisão do grupo: chuveiro 5500 W, 15 min/dia, Copel = 41,25 kWh = R$ 31,68/mês.

## Premissas do grupo (declarar sempre)

`PREMISSAS` (LED e fluorescente 5 h/dia, vapor de sódio 12 h, micro-ondas 0,33 h, bomba 1 h, máquina de lavar 12 ciclos/mês), as 6,59 h da TV, o fator de idade da geladeira (`FAIXAS_FI`) e os tempos padrão do gás (`USO_PADRAO`) são escolhas do grupo sem fonte oficial. Qualquer valor desse tipo:

- fica numa constante nomeada com comentário dizendo que é premissa;
- aparece como estimativa no `metodo`/`avisos`;
- entra na seção de limitações do `README.md` e do documento de processo.

## Estimativa fora do catálogo (`src/estimativa.py`, `servico.estimar_por_equivalentes`)

- Geladeira, nesta ordem: modelo no catálogo -> consumo do Inmetro; etiqueta informada -> kWh da etiqueta (antes de 2023 convertido para a metodologia atual) × Fi; sem etiqueta e compra antes de 2023 -> regra da Portaria Inmetro 20/2006 com faixa; compra a partir de 2023 -> grade do Random Forest (`refrigerador.pkl`). Resultado marcado como `aproximado` com faixa.
- Outros eletros pesados: com valor da etiqueta (kWh/mês, kWh/ciclo ou W) o cálculo é exato; sem ele, mediana dos modelos do catálogo com medida parecida (±10%, ampliando até ±40% para ter pelo menos 5), faixa do 1º ao 3º quartil, e `AVISO_EQUIVALENTES`.
- Eletroportáteis (tabela `portateis`): `W/1000 × tempo/dia × dias`; potência e uso típicos são premissas com fonte por linha. Sem sugestão de troca: o app oferece as dicas do Eco-Coach.
- Gás de cozinha (`src/gas.py`) é outra conta: kg/mês de GLP com rendimento do fogão (Inmetro) e preço por UF (ANP). Não entra em "Minha casa".

## Limites desta regra

Esta skill fixa a ordem das regras, a obrigatoriedade dos avisos, o exemplo de referência e a proibição de esconder premissas. Ela não define tarifa branca, baixa renda, impostos nem aparelhos fora do escopo (gás para aquecimento, fornos comerciais, aquecedor solar). Não invente essas políticas; se o grupo decidir incluí-las, registre a fonte e atualize testes, `README.md` (seções 9 e 12), `CLAUDE.md` e o BPMN.
