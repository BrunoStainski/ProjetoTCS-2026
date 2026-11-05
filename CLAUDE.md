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
  -> src/calculadora_residencial.py (catálogo + regras de cálculo)
  -> src/servico.py (funções usadas por qualquer interface)
  -> src/main.py (API FastAPI)  |  src/app_terminal.py (teste no terminal)
  -> app_gerenciamento_energetico/ (Flutter — ainda é o template inicial)
```

## Stack

Python 3.12 (o mesmo do Dockerfile; não usar 3.14), Pandas, SQLAlchemy **Core** com SQL
parametrizado (não há ORM; `banco.py` troca `?` por parâmetros nomeados), psycopg2,
FastAPI + Uvicorn, PostgreSQL 15, Docker Compose, Flutter.

## Como rodar

```bash
cp .env.example .env                 # credenciais do banco (o .env não vai para o git)
docker compose up -d --build         # postgres_iamp (porta 5434) + api_iamp (porta 8000)
# a API carrega os CSVs no banco sozinha na 1ª subida (RECARREGAR_BANCO=1 força recarga)
# http://localhost:8000/docs
cd src && python criar_banco.py      # recarga manual;   python app_terminal.py  # teste
python scripts/executar_pipeline.py  # refaz a limpeza (raw -> processed)
```

## Banco (definido em `src/banco.py`, constante ESQUEMA)

| Tabela | Conteúdo |
|---|---|
| `aparelhos` | Catálogo: categoria, marca, modelo, tipo, capacidade, kwh_mes (e por velocidade), kwh_ciclo, potencia_w, standby, `origem_dado` |
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
`POST /calcular` (distribuidora_id **ou** tarifa_manual), `GET /categorias`, `GET /ufs`, `GET /saude`.
Erros: 404 (não existe), 422 (dado faltando). Ids mudam ao recriar o banco.

## Machine Learning (planejado — Dupla 2)

- Seed de residências geradas por regras com aparelhos e tarifas reais (`scripts/gerar_seed.py`).
- **CTGAN** (SDV) aprende a seed e gera milhares de residências sintéticas -> `models/ctgan.pkl`.
- **K-Means** agrupa residências em Consciente / Moderado / Ineficiente usando variáveis por
  morador (kWh/morador, fração de chuveiro/ar/geladeira) -> `models/kmeans.pkl`.
- `src/ml_pipeline.py` expõe `classificar_residencia(inventario) -> {perfil, kwh_por_morador, comparacao_media}`
  para a API. Dependências pesadas (sdv/torch) ficam em `requirements-ml.txt`, fora da imagem da API.
- Extra opcional: regressão do consumo de geladeiras (sem a classe de eficiência como variável: vazamento).

## Próximas etapas

EDA com gráficos, ML acima, RAG "Eco-Coach" com LangChain (payback calculado em Python, o LLM
só explica; pgvector é candidato a banco vetorial), app Flutter ligado à API, Terraform
(`infra/main.tf` vazio), documento de processo/ética, BPMN (`docs/bpmn_processo.png`), deck e vídeo.

## Limitações conhecidas (usar na parte de ética)

- Consumo do Inmetro é de laboratório, não de uso real.
- Alguns consumos foram imputados pela média na limpeza (geladeira, máquina, micro-ondas,
  ventilador de mesa) e ainda aparecem como "informado" — só o ar-condicionado é marcado.
- Ar-condicionado e TV usam o kWh/mês fixo do Inmetro, sem perguntar as horas de uso.
- Residências do ML são sintéticas: os perfis servem para demonstração.

## Convenções

- Código, comentários e mensagens em português; colunas em snake_case (`config.salvar_processado`).
- Nunca montar SQL com texto do usuário; usar `banco.consulta`/`banco.executar` com `?`.
- Toda fonte de dado precisa ser registrada (coluna de fonte ou tabela `cargas`).
- Branches por pessoa/tarefa, merge na `main` por Pull Request.
