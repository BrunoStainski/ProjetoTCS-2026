---
name: regra-negocio-perfil-ml
description: Regras de negócio do Machine Learning do iamp: seed de residências por regras, CTGAN (SDV) para residências sintéticas, K-Means para o perfil de consumo (POST /classificar) e Random Forest da geladeira fora do catálogo. Use ao alterar scripts/gerar_seed.py, treinar_*.py, src/ml_pipeline.py ou src/estimativa.py.
---

# Regra de negócio: perfil de consumo e modelos de ML

Use esta skill ao implementar, alterar ou revisar a parte de Machine Learning. O ML do iamp é didático e precisa ser explicado com honestidade para a banca: dados sintéticos, métricas atuais e limitações ficam sempre declarados.

## Pipeline (ordem obrigatória, ~5 min na CPU)

1. `scripts/gerar_seed.py`: 3.000 residências geradas por regras, com aparelhos **reais** do catálogo e tarifas **vigentes** da ANEEL. O consumo usa `consumo_mensal_kwh`, as mesmas regras do app. Perfis econômico/moderado/ineficiente e as probabilidades em `PERFIS` são premissas do grupo. Ar-condicionado limitado a 3.500 W com fator de compressor 0,6.
2. `scripts/treinar_ctgan.py`: CTGAN (SDV 2.x, `fit`/`sample` com `{"residencias": df}`) aprende UF, moradores, cômodos, `tem_*` e kWh por aparelho; gera 5.000 casas em `residencias_sinteticas.csv`. Total, custo e frações são **recalculados**; distribuidora e tarifa sorteadas entre as reais da UF. `validar()` imprime seed × sintética.
3. `scripts/treinar_kmeans.py`: K-Means com k = 3 sobre `kwh_por_morador` (log, peso 2) e `frac_chuveiro`, `frac_ar`, `frac_refrigerador` (peso 0,5). Nome do grupo pela média de kWh/morador: Consciente, Moderado, Ineficiente.
4. `src/ml_pipeline.py`: `classificar_residencia({"moradores", "itens": [{categoria, kwh_mes}]})` devolve perfil, kWh/morador, comparação com a mediana das sintéticas e `AVISO_ML`.

Dependências pesadas (sdv, torch, scikit-learn, matplotlib) só em `requirements-ml.txt`; nunca na imagem da API.

## Regras invioláveis

- `perfil_regra` é o rótulo da geração e **nunca entra no treino** (vazamento). Serve só para conferir o K-Means depois.
- Os pkl da API guardam **só números** (centróides, escalas, grade de previsões): `kmeans.pkl` e `refrigerador.pkl` são lidos sem scikit-learn. `ctgan.pkl` fica fora da imagem (`.dockerignore`).
- `POST /classificar` não usa o banco; recebe os itens da casa e devolve o perfil. Toda resposta carrega `AVISO_ML` (perfil estimado com residências sintéticas, serve para demonstração).
- Resultados atuais reportados como estão: qualidade SDV ~85%; K-Means bate com o perfil da geração em ~73% da seed. Ao retreinar, atualizar esses números no `README.md`, `CLAUDE.md` e no documento de processo, mesmo que piorem.
- Limitação conhecida a manter visível: o CTGAN distorce a distribuição de moradores (3 moradores: 25% na seed, ~37% na sintética), ver `docs/graficos/06_*.png`.
- Retreinar exige refazer `notebooks/eda.ipynb` (`jupyter nbconvert --execute --inplace`) para regenerar `docs/graficos/*.png` e conferir o `README.md` da pasta.

## Random Forest da geladeira (`scripts/treinar_refrigerador.py`, `src/estimativa.py`)

- Variáveis: tipo, frost-free, volume total; `monotonic_cst` no volume; validação `GroupKFold` por marca. **Nunca** usar a classe de eficiência como variável (vazamento: ela deriva do consumo).
- Métrica atual: MAE 3,88 kWh/mês na escala 2025 e 6,46 na escala antiga. O pkl guarda só a grade de previsões.
- Conversão metodologia antiga -> 2025 pela mediana da razão nos modelos com as duas medições, sem os pares com valor copiado; fator de idade `FAIXAS_FI` é premissa do grupo (fonte ainda não anexada).
- Caso de validação em `tests/test_estimativa.py`: Consul CRM45 (duplex frost-free 407 L, 2014, etiqueta 52,5 kWh/mês); sem etiqueta a faixa precisa conter a etiqueta.

## Visualização e EDA

Gráficos da EDA em `docs/graficos/` com tabela de números logo abaixo no notebook; paleta categórica acessível a daltonismo (azul, laranja, aqua, amarelo, magenta) e perfis em tons de azul ordenados. Todo gráfico tem legenda e rótulos com valores e a fonte dos dados na tabela do `docs/graficos/README.md`.

## Limites desta regra

Esta skill não define previsão de conta futura, detecção de fraude, recomendação por perfil demográfico nem uso de dados reais de clientes. Se o grupo quiser treinar com dados reais, antes decidir anonimização, consentimento e LGPD, e registrar no documento de processo.
