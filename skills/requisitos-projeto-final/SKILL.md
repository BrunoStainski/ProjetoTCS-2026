---
name: requisitos-projeto-final
description: Checklist dos entregáveis e critérios de avaliação do projeto integrador do bootcamp TCS 2026 (requisitos_projeto.MD e guia_projeto_final.pdf do professor) mapeados para o iamp. Use ao escrever README, documento de processo, registro de prompts, BPMN, slides ou ao decidir o que ainda falta entregar.
---

# Requisitos do projeto final aplicados ao iamp

O iamp é o projeto final do bootcamp. Ao trabalhar em documentação, infraestrutura ou apresentação, confira esta lista, derivada de `requisitos_projeto.MD` e do `guia_projeto_final.pdf` do professor. Entrega até **48 horas antes** da apresentação, em repositório GitHub ou GitLab (o nosso: github.com/BrunoStainski/ProjetoTCS-2026). Equipe de 4 pessoas; apresentação de **no máximo 20 minutos**.

## Entregáveis obrigatórios e onde ficam no iamp

| Exigência do professor | Onde está no iamp | Situação (10/11/2026) |
|---|---|---|
| README com tema, objetivo, tecnologias e instruções de execução | `README.md` (seções 1 a 8) | feito; manter atualizado a cada rota ou passo novo |
| Documento das etapas do processo (markdown ou PDF), com justificativa técnica das escolhas e análise de ética e segurança | `docs/documento_processo.md` | **vazio**: prioridade |
| BPMN 2.0 da regra de negócio | `docs/bpmn_processo.bpmn` + `.png` (editar em demo.bpmn.io) | feito para `/calcular` e `/classificar`; **falta** `/sugestoes`, `/comparar`, `/eco-coach` |
| Slides (PDF ou PPTX) | não existe ainda | **pendente** |
| Machine Learning **ou** integração com IA de terceiros, com base de dados tratada | tem os dois: K-Means/CTGAN/Random Forest (`scripts/`, `models/`) e RAG com Gemini (`src/rag*.py`) | feito |
| Limpeza, análise e transformação dos dados (Pandas), persistência em SQL, visualização explicativa | `scripts/tratar_dados_*.py`, `src/banco.py`, `notebooks/eda.ipynb`, `docs/graficos/` | feito |
| Backend e frontend | FastAPI (`src/main.py`) + Flutter (`app_gerenciamento_energetico/`) + terminal (`src/app_terminal.py`) | feito |
| Banco de dados | PostgreSQL 15 + pgvector (`docker-compose.yml`) | feito |
| Infraestrutura automatizada com Terraform, local ou nuvem | `infra/local/` (Docker, testado) e `infra/oracle/` (pronto, sem conta) | feito; descrever no documento |
| Arquivos de prompts usados no vibecoding | `prompts/registros_vibecoding.md` e `skills/` | **vazio**: registrar os prompts e as skills usadas |
| Código estruturado com boas práticas e agentic coding | `CLAUDE.md`, `skills/`, testes em `tests/` e `test/` | feito; citar na apresentação |
| Governança e ética: viabilidade, limitações, viés, confiabilidade, uso responsável | seção 12 do `README.md`, "Limitações conhecidas" do `CLAUDE.md` | parcial: consolidar no documento de processo |
| Vídeo da demonstração como backup da live demo | não existe ainda | **pendente** |

## O que o documento de processo precisa conter

Ao preencher `docs/documento_processo.md`, cubra, nesta ordem, o que a banca avalia:

1. **Problema e proposta de valor**: conta de luz alta, pouca compreensão de kWh, dados oficiais dispersos; ganho para o usuário (custo por aparelho, payback da troca) e viabilidade (custo zero: dados públicos, Gemini gratuito, Docker local ou Oracle Always Free). A TCS pergunta ROI ou redução de tempo operacional: responder com números do próprio app.
2. **Etapas desenvolvidas**: aquisição dos dados (Inmetro PBE, ANEEL, ANP), limpeza por script, carga no PostgreSQL, regras de cálculo, API, app, ML, RAG, Terraform, versionamento. Referenciar os arquivos.
3. **BPMN 2.0** atualizado com busca -> uso -> tarifa -> cálculo -> casa -> perfil -> sugestões/comparação -> Eco-Coach, mais o treino de ML offline.
4. **Justificativa técnica**: por que SQL parametrizado sem ORM, por que K-Means (não supervisionado, sem rótulo real), por que CTGAN para ampliar a seed, por que RAG em vez de fine-tuning (fontes oficiais mutáveis, citáveis, auditáveis, custo zero), por que embeddings do Gemini (antes locais: não cabiam nos 512 MB do Render grátis), por que Gemini (Hugging Face sem crédito), por que Flutter e FastAPI.
5. **Ética, viés, confiabilidade e segurança**: consumo de laboratório vs real; valores imputados e corrigidos na limpeza (marcados em `origem_dado`); premissas do grupo sem fonte; residências sintéticas; distorção de moradores do CTGAN; alucinação do LLM mitigada por regras, citações e aviso; envio de dados ao Google (só números, nada pessoal, termos do plano gratuito); histórico `consultas` sem dados pessoais; segredos fora do git; LGPD (nenhum dado pessoal coletado).
6. **Métricas de sucesso e lições aprendidas**: SDV ~85%, K-Means ~73%, MAE da geladeira 3,88 kWh/mês, testes automatizados, caso de referência R$ 31,68.

## Roteiro da apresentação (20 min, divisão sugerida pelo guia)

| Tempo | Etapa | No iamp |
|---|---|---|
| 0–3 | Contexto e problema | dor da conta de luz, proposta de valor |
| 3–6 | Mapeamento e arquitetura | BPMN e o fluxo raw -> processed -> banco -> API -> app |
| 6–12 | Live demo | buscar aparelho, calcular, Minha casa com perfil, sugestão e payback, Eco-Coach (ter o vídeo de backup) |
| 12–16 | Detalhamento técnico | Pandas/SQL, K-Means/CTGAN, RAG + prompt, Docker/Terraform |
| 16–18 | Governança, ética e impacto | limitações e mitigação acima |
| 18–20 | Conclusão | lições do trabalho em equipe e abertura para a banca |

Pesos da banca: qualidade técnica e arquitetura 30%; inovação e valor de negócio 20%; protótipo funcional e usabilidade 20%; governança e ética 15%; comunicação, pitch e divisão de fala entre os 4 membros 15%. Treinar cronometrado.

## Regras ao mexer na documentação

- README, documento de processo, CLAUDE.md e CHANGELOG precisam concordar entre si e com o código; ao mudar um, revisar os outros.
- Toda limitação conhecida vira item explícito nas seções de ética; nada de esconder premissa ou erro de dado.
- Registrar em `prompts/registros_vibecoding.md` os prompts relevantes (objetivo, prompt, resultado, ajuste) e apontar para as skills de `skills/` como as instruções permanentes dadas ao agente.
- Entregáveis em PDF (documento e deck) são gerados a partir do markdown ou do deck fonte e versionados em `docs/`; o APK e o vídeo não entram no git (Release do GitHub).
