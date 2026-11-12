# Skills do iamp

Instruções permanentes para o agente de código (Claude Code), no formato de skills ensinado no bootcamp (`parte3_vibe_coding/vibecoding/skills` do repositório do professor). Cada pasta tem um `SKILL.md` com `name`, `description` e as regras.

| Pasta | Equivalente no exemplo do professor | O que cobre |
|---|---|---|
| `boas-praticas-python-fastapi/` | `boas-praticas-python-django` | Nomes no código em inglês e textos em português, Pandas, SQL parametrizado, FastAPI, idioma das respostas, pytest, git |
| `estrutura-projeto-iamp/` | `estrutura-projeto-django` | Camadas, fluxo dos dados, banco, Docker, Terraform, versionamento |
| `ambiente-virtual/` | `venv` | `.venv` com Python 3.12 no Windows e os três `requirements` (a pasta não se chama `venv/` porque o `.gitignore` bloqueia esse nome) |
| `boas-praticas-flutter/` | (não havia: o exemplo não tinha frontend) | Tema (escuro e claro), acessibilidade, padrões de tela, `api.dart`, idioma, armadilhas, testes |
| `regras_negocio/calculo_consumo/` | `regras_negocio/crud_user` e `login` | Ordem das regras de cálculo, premissas, avisos, estimativa fora do catálogo |
| `regras_negocio/sugestao_troca/` | idem | Equivalência, filtros, payback |
| `regras_negocio/eco_coach/` | idem | RAG, prompt, fontes, ética do LLM |
| `regras_negocio/perfil_ml/` | idem | Seed, CTGAN, K-Means, Random Forest, vazamento |
| `requisitos-projeto-final/` | (não havia) | Entregáveis e critérios da banca mapeados para o iamp |

## Como ativar no Claude Code

Esta pasta é material do projeto (entregável de "prompts do vibecoding"). Para o agente carregar uma skill automaticamente, copie a pasta dela para `.claude/skills/` na raiz do projeto, por exemplo:

```powershell
New-Item -ItemType Directory -Force .claude\skills | Out-Null
Copy-Item -Recurse skills\ambiente-virtual .claude\skills\usar-venv
Copy-Item -Recurse skills\regras_negocio\eco_coach .claude\skills\regra-negocio-eco-coach
```

O nome da pasta em `.claude/skills/` deve ser o `name` do frontmatter. Alternativa: referenciar o caminho da skill no `CLAUDE.md`.
