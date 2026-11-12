---
name: estrutura-projeto-iamp
description: Siga a arquitetura do iamp: limpeza com Pandas (raw -> processed), PostgreSQL 15 com pgvector, API FastAPI documentada no Swagger, app Flutter, Eco-Coach com RAG e Gemini, modelos de ML em pkl, Docker Compose e Terraform. Use ao criar rotas, tabelas, scripts, telas ou infraestrutura.
---

# Estrutura do projeto iamp

Copiloto de eficiência energética residencial (bootcamp TCS 2026). Ao implementar ou alterar algo, preserve a arquitetura e as responsabilidades abaixo. Leia o código existente antes de mudar e integre à estrutura atual, sem criar módulos ou apps paralelos. O `CLAUDE.md` da raiz é a referência detalhada; esta skill resume o que não pode ser quebrado.

## Fluxo dos dados

```
datasets/raw/ (Inmetro, ANEEL, documentos do RAG)
  -> scripts/tratar_dados_*.py            limpeza com Pandas, um script por dataset
  -> datasets/processed/*.csv             dados limpos, versionados no git
  -> src/criar_banco.py                   recria as tabelas e carrega (também na 1ª subida da API)
  -> PostgreSQL 15 + pgvector (Docker)    tabelas aparelhos, distribuidoras, tarifas, cargas, consultas...
  -> src/calculadora_residencial.py       regras de cálculo e de equivalência (puras, sem banco)
  -> src/servico.py                       funções com banco usadas por qualquer interface
  -> src/main.py (FastAPI)  |  src/app_terminal.py (teste no terminal)
  -> app_gerenciamento_energetico/        app Flutter, só fala com a API
RAG: datasets/raw/rag + fontes.csv -> scripts/carregar_rag.py -> trechos_rag -> src/rag.py -> src/rag_agent.py -> POST /eco-coach
ML:  scripts/gerar_seed.py -> treinar_ctgan.py -> treinar_kmeans.py -> models/*.pkl -> src/ml_pipeline.py -> POST /classificar
```

## Camadas e onde cada coisa mora

| Camada | Pasta ou arquivo | Responsabilidade |
|---|---|---|
| Limpeza | `scripts/tratar_dados_*.py`, `scripts/config.py` | Ler `raw`, limpar, salvar em `processed` em snake_case |
| Treino | `scripts/gerar_seed.py`, `treinar_*.py`, `carregar_rag.py` | Gerar modelos (`models/*.pkl`) e a base vetorial; rodam fora da API |
| Banco | `src/banco.py`, `src/criar_banco.py` | Esquema (`SCHEMA`), conexão, consultas parametrizadas, carga |
| Regras | `src/calculadora_residencial.py`, `estimativa.py`, `ml_pipeline.py`, `rag.py`, `rag_agent.py` | Cálculo, equivalência, estimativa, perfil, RAG. Sem HTTP |
| Serviço | `src/servico.py` | Junta banco + regras em funções reutilizáveis pelas interfaces |
| API | `src/main.py`, `src/idioma.py`, `src/traducoes.py` | Modelos Pydantic, rotas, erros HTTP, CORS, idioma da resposta, carga automática no `lifespan` |
| App | `app_gerenciamento_energetico/lib/` | `api.dart` (chamadas), `casa.dart` (estado), `tema.dart`, `telas/` |
| Infra | `Dockerfile`, `docker-compose.yml`, `render.yaml`, `infra/local/`, `infra/oracle/` | Imagem da API, banco, nuvem gratuita (Render + Neon), Terraform local (em uso) e Oracle (alternativa pronta) |
| Docs | `README.md`, `CLAUDE.md`, `CHANGELOG.md`, `docs/`, `prompts/` | Instruções, BPMN, gráficos da EDA, documento de processo, registro de prompts |

## Regras de arquitetura

- Regra de negócio não entra em `main.py` nem no app Flutter: vai para `calculadora_residencial.py`/`estimativa.py` (puro) ou `servico.py` (com banco). O app só exibe o que a API devolve, incluindo `metodo` e `avisos`.
- Rota nova: função em `servico.py` + modelos Pydantic + rota com `tags` e `response_model` + teste em `tests/test_api.py` + linha na tabela da API do `README.md` e do `CLAUDE.md`. Se mudar o fluxo de negócio, atualizar o BPMN (`docs/bpmn_processo.bpmn` e `.png`).
- Tabela ou coluna nova: `banco.SCHEMA` + função de carga em `criar_banco.py` + registro em `cargas` + coluna de fonte. Coluna nova em `aparelhos` também entra em `APPLIANCE_COLUMNS`.
- Categoria nova de aparelho: script `tratar_dados_<categoria>.py`, entrada em `SPECS`, e decidir `ASSUMPTIONS`, `EQUIVALENCE` ou `NO_SUGGESTION` (ver skills de regra de negócio).
- Modelos de ML na API são só números em pkl (`kmeans.pkl`, `refrigerador.pkl`): a imagem da API **não** tem scikit-learn, torch ou sdv. Dependência pesada vai para `requirements-ml.txt`.
- A imagem Docker leva só `src/`, `datasets/processed/`, os dois pkl, `datasets/raw/rag/` e `scripts/carregar_rag.py` (com a base vazia a API carrega o RAG sozinha; os embeddings vêm da API do Gemini, sem modelo local). `.dockerignore` exclui o resto. Mudou código em `src/`, refaça `docker compose up -d --build`.
- Configuração vem do `.env` via `config.py` (`POSTGRES_*` ou `DATABASE_URL`, `GEMINI_API_KEY`, `GEMINI_MODELOS`, `GEMINI_EMBEDDING_MODEL`, `RECARREGAR_BANCO`, `PORT`). Segredos só em `.env`, `terraform.tfvars`, `terraform.tfstate` (todos no `.gitignore`) e no painel do Render.
- Compose e Terraform convivem: compose usa portas 8000 (API) e 5434 (banco); `infra/local` usa 8080 e 5435 com prefixo `iamp_tf`. No Windows o provider Docker exige `docker_host = "npipe:////./pipe/dockerDesktopLinuxEngine"`.
- Documentação da API é o Swagger gerado pelo FastAPI em `/docs`; mantenha descrições nos modelos em vez de documentar à parte.

## Versionamento

- Versão do app em `pubspec.yaml` (`nome+build`, o build sobe a cada APK) e da API em `main.py`; histórico em `CHANGELOG.md`. Commit "Adiciona a versão X.Y.Z", tag `vX.Y.Z` e Release no GitHub com o APK (o APK nunca entra no git).
- Publicar a API antes do APK; mudanças na API só acrescentam campos.
- APK sempre com `flutter build apk --release --split-per-abi --dart-define=API_URL=...` e assinado com a chave do projeto (`android/key.properties`, fora do git).

## Antes de implementar

Confira `SCHEMA`, `SPECS`, `servico.py`, `main.py`, `api.dart` e os testes existentes. Não presuma endpoints, campos ou políticas que não estejam no projeto; quando a regra for uma premissa do grupo (sem fonte), deixe isso explícito no código, no aviso ao usuário e na documentação.
