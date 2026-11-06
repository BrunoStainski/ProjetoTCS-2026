# iamp — contexto do projeto para o Claude Code

Copiloto de eficiência energética residencial (bootcamp TCS 2026). O usuário escolhe um
aparelho (marca/modelo) e a distribuidora de energia; o iamp calcula o consumo (kWh/mês) e o
custo (R$/mês) cruzando dados oficiais do **Inmetro** (PBE) e as tarifas da **ANEEL**.
Repositório: github.com/BrunoStainski/ProjetoTCS-2026. Projeto didático: o objetivo é mostrar
domínio das técnicas, com honestidade sobre as limitações.

## Arquitetura (fluxo dos dados)

```
datasets/raw/ (Inmetro + ANEEL)
  -> scripts/tratar_dados_*.py (Pandas, um por dataset; scripts/executar_pipeline.py roda todos)
  -> datasets/processed/*_limpo.csv  (+ distribuidoras_uf.csv: UF de cada distribuidora via CNPJ)
  -> src/criar_banco.py (recria as tabelas e carrega)       -> PostgreSQL 15 (Docker)
  -> src/calculadora_residencial.py (catálogo + regras de cálculo + EQUIVALENCIA para sugestões)
  -> src/servico.py (funções usadas por qualquer interface)
  -> src/main.py (API FastAPI)  |  src/app_terminal.py (teste no terminal)
  -> app_gerenciamento_energetico/ (app Flutter ligado à API; ver seção "App Flutter")

ML: scripts/gerar_seed.py -> seed_residencias.csv -> scripts/treinar_ctgan.py -> models/ctgan.pkl
    + residencias_sinteticas.csv -> scripts/treinar_kmeans.py -> models/kmeans.pkl -> src/ml_pipeline.py
```

## Stack

Python 3.12 (o mesmo do Dockerfile; não usar 3.14), Pandas, SQLAlchemy **Core** com SQL
parametrizado (não há ORM; `banco.py` troca `?` por parâmetros nomeados), psycopg2,
FastAPI + Uvicorn, PostgreSQL 15, Docker Compose, Flutter (Dart, só o pacote `http`).

## Como rodar

```bash
cp .env.example .env                 # credenciais do banco (o .env não vai para o git)
docker compose up -d --build         # postgres_iamp (porta 5434) + api_iamp (porta 8000)
# a API carrega os CSVs no banco sozinha na 1ª subida e quando falta coluna nova no banco
# (RECARREGAR_BANCO=1 força recarga). Mudou código em src/? rode o --build de novo.
# http://localhost:8000/docs
cd app_gerenciamento_energetico && flutter run -d chrome   # app (Windows desktop exige VS C++)
flutter analyze; flutter test                               # checagens do app
cd src && python criar_banco.py      # recarga manual;   python app_terminal.py  # teste
python scripts/executar_pipeline.py  # refaz a limpeza (raw -> processed)
# ML (pip install -r requirements-ml.txt; nesta ordem, ~5 min no CPU):
python scripts/gerar_seed.py; python scripts/treinar_ctgan.py; python scripts/treinar_kmeans.py
# EDA (gera docs/graficos/*.png):
jupyter nbconvert --to notebook --execute --inplace notebooks/eda.ipynb
# Testes (pip install -r requirements-dev.txt; sem o PostgreSQL, os de banco são pulados):
pytest                               # tudo;   pytest -m "not banco"  # só os rápidos
```

## Banco (definido em `src/banco.py`, constante ESQUEMA)

| Tabela | Conteúdo |
|---|---|
| `aparelhos` | Catálogo: categoria, marca, modelo, tipo, capacidade, kwh_mes (e por velocidade), kwh_ciclo, potencia_w, standby, `fluxo_lm` (lâmpadas), `origem_dado` |
| `distribuidoras` | 99 distribuidoras com UF (`fonte_uf` = de onde veio) |
| `tarifas` | Tarifa B1 residencial convencional (TUSD+TE, R$/kWh) com vigência |
| `vw_tarifa_vigente` | Tarifa válida hoje por distribuidora |
| `cargas` | Rastreabilidade: arquivo e linhas de cada carga |
| `consultas` | Histórico de cálculos (preservado entre cargas, sem dados pessoais) |

Números atuais: 24.155 aparelhos em 12 categorias (geladeira, TV, ar-condicionado,
ventilador de mesa/teto, chuveiro, lâmpadas LED/fluorescente/vapor de sódio, micro-ondas,
máquina de lavar, bomba). Fora do escopo: aparelhos a gás, fornos comerciais, aquecedor solar.

## Regras de cálculo (`consumo_mensal_kwh`)

1. Inmetro informa kWh/mês -> usa a tabela (ventilador: por velocidade)
2. Informa kWh/ciclo -> kWh/ciclo x ciclos/mês (máquina de lavar)
3. Só potência -> W x horas/dia x 30 / 1000 (+ stand-by). Chuveiro exige horas do usuário.
Premissas de uso padrão (`PREMISSAS`) são do grupo, sem fonte — o app avisa que são estimativa.
Tarifa: escolhida pela distribuidora (ANEEL) ou digitada pelo usuário (conta de luz).
Valores **sem** ICMS, PIS/COFINS, bandeira e iluminação pública (aviso `AVISO_PADRAO`).
Exemplo de referência: chuveiro 5500 W, 15 min/dia, Copel = 41,25 kWh = R$ 31,68/mês.

## API (`src/main.py`)

`GET /aparelhos?busca=`, `GET /aparelhos/{id}/uso`, `GET /distribuidoras?uf=|busca=`,
`POST /calcular` (distribuidora_id **ou** tarifa_manual), `GET /categorias`, `GET /ufs`, `GET /saude`,
`POST /classificar` ({moradores, itens:[{categoria, kwh_mes}]} -> perfil do K-Means; não usa o banco),
`POST /sugestoes` (mesmo corpo do /calcular + limite -> modelos equivalentes mais econômicos),
`POST /comparar` (+ alternativa_id e preco_novo opcional -> economia e payback em meses).
Os corpos de /calcular, /sugestoes e /comparar herdam de `UsoETarifa` (main.py).
Erros: 404 (não existe), 422 (dado faltando), 503 (banco ou modelo indisponível). Ids mudam ao recriar o banco.
A imagem da API leva só `models/kmeans.pkl` (`.dockerignore` exclui o resto de `models/`).
`banco_carregado()` compara as colunas de `aparelhos` com `COLUNAS_APARELHOS` (criar_banco.py): ao
adicionar coluna no catálogo, atualize ESQUEMA + COLUNAS_APARELHOS e o banco recarrega sozinho.

## Sugestão de troca (`servico.sugerir_alternativas` e `servico.comparar`)

- Equivalência em `EQUIVALENCIA` (calculadora_residencial.py): mesma categoria (fluorescente pode
  virar LED), medida parecida (`capacidade` ou `fluxo_lm`) dentro da tolerância e mesmo tipo só onde
  o tipo do Inmetro é padronizado (geladeira, ar, máquina de lavar). Mesmo uso e mesma tarifa do atual.
- Filtros: só `origem_dado = 'informado'`; economia mínima 5% (`ECONOMIA_MINIMA`); consumo abaixo de
  40% da mediana dos equivalentes é descartado como erro de dado (`FRACAO_SUSPEITA`; caso real:
  HISENSE RS3P428NEDA1 com 2,8 kWh); variações do mesmo modelo (marca+detalhe+kWh) aparecem uma vez.
- Sem sugestão (`SEM_SUGESTAO`, com o motivo para o app): chuveiro, micro-ondas, vapor de sódio.
- Payback = preco_novo / economia_mes (Python, na API). O catálogo não tem preço: o usuário digita.

## App Flutter (`app_gerenciamento_energetico/lib/`)

- `tema.dart`: identidade visual (fundo preto, amarelo `#FFD000` nos destaques, texto branco).
- `api.dart`: modelos e chamadas da API. `casa.dart`: estado (Consulta, EscolhaTarifa, Casa com
  ChangeNotifier global `casa`; só em memória, sem persistência).
- Telas (`telas/`): busca -> uso -> distribuidora (oferece a última tarifa) -> resultado ->
  minha_casa (total, quantidade por item, perfil K-Means) | sugestoes -> comparar (payback, trocar na casa).
- Testes em `test/widget_test.dart` (tema, casa vazia, somas, troca, formatação).

## Machine Learning (Dupla 2)

- **Seed** (`scripts/gerar_seed.py`): 3.000 residências por regras, com aparelhos reais do
  catálogo e tarifas vigentes da ANEEL; consumo via `consumo_mensal_kwh` (mesmas regras do app).
  Perfis econômico/moderado/ineficiente e probabilidades em `PERFIS` são premissas do grupo.
  Ar-condicionado limitado a 3.500 W e fator de compressor 0,6. `perfil_regra` é o rótulo da
  geração: **nunca** entra no treino (vazamento), só na conferência do K-Means.
- **CTGAN** (SDV 2.1, `scripts/treinar_ctgan.py`): aprende UF, moradores (categórico), cômodos,
  `tem_*` e kWh por aparelho (chuveiro por morador). Total, custo e frações são recalculados;
  distribuidora/tarifa sorteadas entre as reais da UF. Gera 5.000 casas; `validar()` imprime a
  comparação seed × sintética. SDV 2.x: `fit`/`sample` usam `{"residencias": df}`.
- **K-Means** (`scripts/treinar_kmeans.py`, k=3): variáveis `kwh_por_morador` (log, peso 2) e
  `frac_chuveiro/ar/refrigerador` (peso 0,5); nome do grupo pela média de kWh/morador.
  O `kmeans.pkl` guarda só números, então a API não precisa de scikit-learn.
- **`src/ml_pipeline.py`**: `classificar_residencia({"moradores", "itens": [{categoria, kwh_mes}]})`
  -> perfil, kWh/morador e comparação com a mediana das sintéticas (+ aviso de dado sintético).
- Resultados atuais: qualidade SDV ~85%; K-Means bate com o perfil da geração em ~73% da seed.
- Dependências pesadas (sdv/torch) ficam em `requirements-ml.txt`, fora da imagem da API.
- Extra opcional: regressão do consumo de geladeiras (sem a classe de eficiência como variável: vazamento).

## Próximas etapas

RAG "Eco-Coach" com LangChain (`src/rag_agent.py` vazio; o payback já existe em
`/comparar`, o LLM só explica; pgvector é candidato a banco vetorial), Terraform (`infra/main.tf`
vazio), documento de processo/ética (`docs/documento_processo.md` vazio), registro de prompts
(`prompts/registros_vibecoding.md` vazio), deck e vídeo.
No app: salvar "Minha casa" entre sessões e a tela do Eco-Coach.
BPMN: fonte editável em `docs/bpmn_processo.bpmn` (abrir em demo.bpmn.io) e imagem exportada em
`docs/bpmn_processo.png`. Mostra `/calcular` + `/classificar` e o treino de ML offline; ao mudar a API
(ex.: um futuro `POST /simulacao`), atualizar os dois. PENDENTE: incluir `/sugestoes` e `/comparar`.

## Limitações conhecidas (usar na parte de ética)

- Consumo do Inmetro é de laboratório, não de uso real.
- Alguns consumos foram imputados na limpeza (ar-condicionado, geladeira, micro-ondas, ventilador
  de mesa, TV): ficam com `origem_dado = 'derivado ou estimado na limpeza'`, o app avisa e eles não
  entram nas sugestões de troca.
- O Inmetro tem erros de digitação no consumo (ex.: 28,0 vs 2,8 kWh). Nas TVs, 77 consumos com a
  vírgula deslocada (10x acima/abaixo do esperado pelo tamanho da tela) são corrigidos na limpeza
  (`consumo_imputado`, motivo em `correcao_consumo`) e o stand-by > 10 W é apagado
  (`standby_suspeito`). Nas outras categorias, as sugestões filtram os casos extremos, mas o
  cálculo do aparelho escolhido usa o valor como veio.
- Payback simples (sem juros, sem revenda do antigo, sem reajuste de tarifa) e com preço digitado.
- Ar-condicionado e TV perguntam as horas (opcional; em branco = kWh/mês do Inmetro). O ar usa a
  potência a 35 °C em carga total, que é um teto (o compressor não fica ligado o tempo todo). A TV
  reescala por regra de três com 6,59 h/dia de ensaio (`HORAS_REFERENCIA_INMETRO`): número
  levantado pelo grupo, sem o documento oficial e sem saber se o kWh/mês inclui o stand-by.
- Residências do ML são sintéticas: os perfis servem para demonstração.
- O CTGAN ainda distorce a distribuição de moradores (ex.: 3 moradores 25% na seed -> ~37%).

## Convenções

- Código, comentários e mensagens em português; colunas em snake_case (`config.salvar_processado`).
- Nunca montar SQL com texto do usuário; usar `banco.consulta`/`banco.executar` com `?`.
- Toda fonte de dado precisa ser registrada (coluna de fonte ou tabela `cargas`).
- Branches por pessoa/tarefa, merge na `main` por Pull Request.
- Commits e PRs sem linha "Co-Authored-By" nem rodapé de atribuição ao Claude.
