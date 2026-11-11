---
name: boas-praticas-python-fastapi
description: Aplique boas práticas de legibilidade, organização e segurança ao escrever ou revisar código Python do iamp (Pandas, SQLAlchemy Core, FastAPI, pytest). Nomes de código em inglês e snake_case, SQL sempre parametrizado, toda fonte de dado registrada e toda estimativa avisada.
---

# Boas práticas de Python e FastAPI no iamp

Ao criar, alterar ou revisar código Python neste repositório, siga estas convenções. Preserve os padrões já existentes em `src/`, `scripts/` e `tests/` e prefira soluções simples, explícitas e idiomáticas. O projeto é didático: o código precisa ser lido e explicado por todo o grupo e pela banca.

## Nomes e estilo

- Nomes de código (classes, funções, variáveis, parâmetros) em **inglês**; comentários, docstrings e mensagens em **português**.
- Contrato em português, sem traduzir: chaves do JSON da API (modelos herdam de `ApiModel`, que usa `JSON_NAMES` como alias),
  parâmetros de URL (`Query(alias="busca")`), colunas do banco/CSV e nomes de arquivo/módulo.
- Identificadores **sem acento**: `monthly_consumption_kwh`, `tariff_by_id`, `calculate_old_refrigerator`. Textos mostrados ao usuário podem ter acento; siga o padrão do módulo em que estiver.
- Use `snake_case` para variáveis, funções, módulos, colunas de DataFrame e colunas do banco (`scripts/config.py: to_snake_case` já padroniza as colunas ao salvar).
- Use `PascalCase` para classes, em especial os modelos Pydantic da API: `CalculationInput`, `Result`, `Classification`.
- Use `UPPER_SNAKE_CASE` para constantes de regra de negócio: `ASSUMPTIONS`, `EQUIVALENCE`, `MIN_SAVINGS`, `DEFAULT_NOTICE`.
- Quatro espaços de indentação; funções curtas com uma responsabilidade; linhas até cerca de 110 caracteres, como o código atual.
- Todo módulo começa com uma docstring dizendo o que ele faz e como rodar quando for um script.

## Boas práticas de Python

- Prefira código simples e legível; evite duplicação e abstrações sem necessidade. Não introduza bibliotecas novas sem conferir `requirements.txt`, `requirements-ml.txt` e `requirements-dev.txt`.
- Use type hints quando esclarecerem o contrato (como em `scripts/config.py`); não é obrigatório em todo lugar.
- Trate erros específicos com mensagem em português para o usuário (`ValueError("informe quantas horas por dia o aparelho fica ligado")`, `ConnectionError` em `banco.connect`). Nunca `except` genérico silencioso.
- Use `with` para conexões e arquivos; feche conexões abertas com `connect()`.
- Separe regra de negócio (`calculadora_residencial.py`, `estimativa.py`, `gas.py`: funções puras, sem banco) de acesso a dados (`banco.py`, `servico.py`) e de HTTP (`main.py`).
- Nunca coloque segredos no código, em logs ou em mensagens de erro. Credenciais vêm do `.env` por `config.py`; a chave do Gemini e a senha do banco não aparecem em saída de terminal (mascare antes de exibir).

## Dados e Pandas

- Um script de limpeza por dataset em `scripts/tratar_dados_*.py`, lendo com `read_csv_inmetro` e gravando com `save_processed`. `scripts/executar_pipeline.py` roda todos; o script novo precisa rodar sozinho, de qualquer pasta.
- Limpe textos com `.str.strip()` só nas colunas de texto, sem transformar nulos na string `"nan"`.
- Converta números com `pd.to_numeric(..., errors="coerce")` depois de trocar vírgula por ponto; use `Int64` para inteiros com nulos.
- Imprima quantas linhas entraram e quantas saíram. Corrija erro de digitação da fonte de forma explícita e documentada (coluna de motivo, como `correcao_consumo`).
- Toda fonte de dado é registrada: coluna de fonte na tabela (`fonte`, `origem_dado`, `arquivo_origem`) ou linha na tabela `cargas`. Valor imputado ou estimado na limpeza recebe `origem_dado = 'derivado ou estimado na limpeza'`, nunca passa por dado informado.

## Banco de dados

- Acesso só por SQLAlchemy **Core** com SQL parametrizado: `banco.query(con, sql, params)` e `banco.run(con, sql, params)` com `?`. Não há ORM e não se deve criar um.
- **Nunca** monte SQL concatenando ou interpolando texto do usuário.
- O esquema vive em `banco.SCHEMA`; coluna nova no catálogo exige atualizar `SCHEMA` e `APPLIANCE_COLUMNS` (`criar_banco.py`), e a API recarrega o banco sozinha. A tabela `trechos_rag` é criada por `scripts/carregar_rag.py`.
- Tabelas de dados são recriadas a cada carga; `consultas` e `consultas_gas` são histórico e não guardam dados pessoais.

## FastAPI

- Rotas finas em `main.py`: validam a entrada com Pydantic, chamam `servico.py` e devolvem o modelo de resposta (`response_model`). Regra de negócio não entra em `main.py`.
- Todo corpo e toda resposta têm modelo Pydantic com `Field(description=...)` onde ajudar: o Swagger em `/docs` é a documentação oficial da API para a banca e para o app.
- Erros padronizados por `service_error`: `404` não existe, `422` dado faltando ou inválido, `503` banco, modelo ou LLM indisponível. Não exponha detalhes internos nem segredos na mensagem.
- Mudanças na API só **acrescentam** campos ou rotas: o APK já instalado precisa continuar funcionando. Mudou a API, suba `version` em `main.py` e anote no `CHANGELOG.md`.
- Toda estimativa, premissa ou conversão aparece em `avisos` e em `metodo` na resposta; o app mostra isso ao usuário.

## Idioma das respostas

- A API responde em português por padrão e em inglês com `Accept-Language: en` (`src/idioma.py`; o middleware `RequestLanguage` em `main.py` guarda o idioma numa ContextVar).
- Texto para o usuário montado com números (`metodo`, mensagens de erro, payback): `tr("pt", "en")` no próprio lugar, com o português idêntico ao de antes.
- Texto fixo (constante `AVISO_*`, `ESTIMAVEIS`, `TYPE_NAMES`, `NO_SUGGESTION`, nomes de eletroportáteis): continua em português no código e passa por `t(texto)` quando entra na resposta; a tradução vai em `src/traducoes.py` (chave = texto em português). `tests/test_idioma.py` falha se faltar tradução ou sobrar chave antiga.
- Chaves e números não se traduzem (categoria, perfil, velocidade, `kwh_mes`); o app traduz os nomes.
- Mensagem de erro que decide 404 em `service_error` precisa do trecho nas duas línguas ("nao existe"/"does not exist").

## Testes

- `pytest` na raiz. Testes de regra pura não precisam de banco; os que precisam usam os fixtures `con` ou `api` e a marca `@pytest.mark.banco` (são pulados sem o PostgreSQL).
- Testes da API mandam `registrar=False` no `POST /calcular` para não poluir o histórico.
- O LLM é sempre substituído por resposta fixa (`monkeypatch` em `rag_agent.call_llm`): nenhum teste chama o Gemini.
- Regra nova ou corrigida = teste novo com o caso concreto (ex.: Consul CRM45, HISENSE RS3P428NEDA1) e, se mudar o cálculo de referência, conferir o chuveiro 5500 W, 15 min/dia, Copel = 41,25 kWh = R$ 31,68.

## Git

- Branch por pessoa ou tarefa; merge na `main` por Pull Request.
- Commits em português, no imperativo, descrevendo o efeito ("Adiciona a versão 1.2.0"). Sem linha `Co-Authored-By` nem rodapé de atribuição à IA.
- Nunca versionar `.env`, `terraform.tfvars`, `*.tfstate`, `models/fastembed/`, `key.properties`, `.jks` ou APK.

## Ambiente

Para rodar Python, pip, pytest e scripts, siga a skill `usar-venv`: Python 3.12 do `.venv` da raiz, nunca o Python global.
