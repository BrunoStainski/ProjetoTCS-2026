# iamp

Copiloto de eficiência energética residencial.

O usuário escolhe um aparelho (marca e modelo) e a distribuidora de energia da casa. O iamp mostra quanto esse aparelho gasta por mês, em kWh e em reais.

---

## 1. O problema

- A conta de luz é alta, mas as pessoas não sabem quais aparelhos gastam mais.
- Pouca gente entende kWh ou sabe calcular o custo de um aparelho.
- Os dados oficiais existem (Inmetro e ANEEL), mas estão espalhados e são difíceis de ler.

## 2. A solução

- Junta as tabelas de consumo do **Inmetro** e as tarifas da **ANEEL** num banco de dados.
- O usuário busca o aparelho e escolhe a distribuidora.
- O app calcula: `consumo (kWh/mês) x tarifa (R$/kWh) = custo por mês`.
- Mostra também como o valor foi calculado e de onde veio cada dado.

---

## 3. Arquitetura

```
 Dados brutos (Inmetro + ANEEL)        datasets/raw/
            |
            v
 Limpeza com Python e Pandas           scripts/tratar_dados_*.py
            |
            v
 Dados limpos (CSV)                    datasets/processed/
            |
            v
 Carga no banco                        src/criar_banco.py
            |
            v
 PostgreSQL (Docker)                   docker-compose.yml
            |
            v
 Regras de cálculo                     src/calculadora_residencial.py
            |
            v
 Funções para as telas                 src/servico.py
            |
            +--------------------------------------+
            v                                      v
 API FastAPI (Docker)  src/main.py      App de terminal (testes)  src/app_terminal.py
            |
            v
 App Flutter                           app_gerenciamento_energetico/
```

### Tecnologias

| Parte | Tecnologia |
|---|---|
| Linguagem | Python 3.12 |
| Limpeza e análise | Pandas |
| Banco de dados | PostgreSQL 15 |
| Acesso ao banco | SQLAlchemy + psycopg2 |
| API | FastAPI + Uvicorn |
| Containers | Docker e Docker Compose |

### Tabelas do banco

| Tabela | O que guarda |
|---|---|
| `aparelhos` | Catálogo com marca, modelo e consumo de cada aparelho |
| `distribuidoras` | Distribuidoras de energia e o estado de cada uma |
| `tarifas` | Tarifa residencial (B1) de cada distribuidora e quando ela vale |
| `vw_tarifa_vigente` | Visão com a tarifa que vale hoje para cada distribuidora |
| `cargas` | De qual arquivo veio cada dado e quando foi carregado |
| `consultas` | Histórico dos cálculos feitos no app (sem dados pessoais) |

### Aparelhos incluídos

Geladeira, TV, ar-condicionado, ventilador de mesa, ventilador de teto, chuveiro, lâmpada LED, lâmpada fluorescente, lâmpada de vapor de sódio, micro-ondas, máquina de lavar e bomba d'água.

Ficaram de fora: aquecedores e fogões a gás (não usam energia elétrica), fornos elétricos comerciais (não são de uso residencial) e aquecedores solares (geram economia, não consomem).

---

## 4. Estrutura das pastas

```
iamp/
├── datasets/
│   ├── raw/              # dados originais do Inmetro e da ANEEL
│   └── processed/        # dados limpos, prontos para o banco
├── scripts/              # limpeza dos dados (um script por dataset)
├── src/                  # aplicação: banco, cálculo e app
├── app_gerenciamento_energetico/   # app Flutter (em construção)
├── docs/                 # BPMN e documentação
├── infra/                # Terraform (em construção)
├── models/               # modelos de Machine Learning (em construção)
├── prompts/              # registro dos prompts usados com IA
├── Dockerfile            # imagem da API
├── docker-compose.yml    # sobe o PostgreSQL e a API
├── requirements.txt      # bibliotecas Python
└── .env.example          # modelo das credenciais do banco
```

---

## 5. Pré-requisitos

Instale nesta ordem:

1. **Git**: https://git-scm.com/downloads
2. **Python 3.12**: https://www.python.org/downloads/ (no Windows, marque "Add Python to PATH")
3. **Docker Desktop**: https://www.docker.com/products/docker-desktop/

Para conferir se deu certo:

```bash
git --version
python --version
docker --version
```

---

## 6. Como rodar o projeto

### Passo 1: baixar o projeto

```bash
git clone https://github.com/BrunoStainski/ProjetoTCS-2026.git
cd ProjetoTCS-2026
```

### Passo 2: criar o ambiente virtual do Python

```bash
python -m venv .venv
```

Ativar o ambiente:

- Windows: `.venv\Scripts\activate`
- Linux ou Mac: `source .venv/bin/activate`

### Passo 3: instalar as bibliotecas

```bash
pip install -r requirements.txt
```

### Passo 4: configurar as credenciais do banco

Copie o arquivo de exemplo:

- Windows: `copy .env.example .env`
- Linux ou Mac: `cp .env.example .env`

Abra o `.env` e troque a senha em `POSTGRES_PASSWORD`. Esse arquivo não vai para o GitHub.

### Passo 5: subir o banco e a API

Abra o Docker Desktop e depois rode:

```bash
docker compose up -d --build
```

Isso sobe dois containers:

- `postgres_iamp`: o banco PostgreSQL (porta 5434)
- `api_iamp`: a API FastAPI (porta 8000)

Na primeira vez, a API carrega os dados de `datasets/processed/` no banco sozinha (leva cerca de 1 minuto).
Para conferir se os dois estão `healthy`:

```bash
docker ps
```

Depois abra **http://localhost:8000/docs** no navegador para ver e testar a API (ver seção 7).

### Passo 6 (opcional): refazer a limpeza dos dados

Os dados limpos já estão em `datasets/processed/`. Só rode este passo se mudar algum dado bruto ou script de limpeza.

```bash
python scripts/executar_pipeline.py
```

### Passo 7 (opcional): recarregar os dados no banco

A API já carrega os dados na primeira subida. Rode este passo só se refez a limpeza (Passo 6) ou quer recriar as tabelas sem reiniciar a API.

```bash
cd src
python criar_banco.py
```

O resultado esperado é parecido com:

```
Banco criado: postgresql+psycopg2://admin:***@localhost:5434/banco_projeto
  aparelhos:      24155
  distribuidoras: 99
```

### Passo 8: usar o app de terminal

Ainda dentro de `src/`:

```bash
python app_terminal.py
```

Exemplo de uso:

1. Digite o aparelho: `bosch ewi 5.5`
2. Escolha a opção `1` na lista
3. Informe o uso: `0,25` (15 minutos por dia)
4. Digite a distribuidora: `copel`

Resultado: cerca de 41 kWh por mês, ou **R$ 31,68 por mês**.

---

## 7. API

Documentação interativa: **http://localhost:8000/docs** (dá para testar cada endereço em "Try it out").

| Endereço | Para que serve |
|---|---|
| `GET /aparelhos?busca=brastemp` | Busca aparelhos por marca e/ou modelo (opcional: `categoria`, `limite`) |
| `GET /aparelhos/{id}/uso` | Diz o que o app precisa perguntar: `horas`, `ciclos`, `velocidade` ou nada (`null`) |
| `GET /distribuidoras?uf=PR` | Lista as distribuidoras com tarifa vigente (opcional: `busca=copel`) |
| `POST /calcular` | Devolve o consumo (kWh/mês) e o custo (R$/mês e R$/ano) |
| `GET /categorias`, `GET /ufs` | Listas para preencher filtros no app |
| `GET /saude` | Diz se a API e o banco estão no ar |

Fluxo do app: buscar o aparelho → perguntar o uso → escolher a distribuidora → calcular.

Exemplo de `POST /calcular` (chuveiro Bosch EWI 5.5, 15 min por dia, Copel):

```json
{
  "aparelho_id": 9844,
  "distribuidora_id": 60,
  "horas_dia": 0.25
}
```

Resposta (resumida): `"kwh_mes": 41.25`, `"custo_mes": 31.68`, `"custo_ano": 380.17`, além de `metodo` e `avisos`.

Regras do corpo:

- Envie `distribuidora_id` **ou** `tarifa_manual` (R$/kWh da conta de luz), nunca os dois.
- `horas_dia` (0 a 24), `ciclos_mes` ou `velocidade` (`baixa`, `media`, `alta`) conforme o `GET /uso`. Se faltar, usa o valor padrão quando existe.
- `registrar` (padrão `true`) grava o cálculo na tabela `consultas`.
- Erros: `404` quando o aparelho ou a distribuidora não existe, `422` quando falta ou sobra algum dado.

Os ids mudam se o banco for recriado: o app deve sempre pegar o id pela busca.

---

## 8. Como o cálculo funciona

| Caso | Como calcula |
|---|---|
| O Inmetro informa o consumo mensal (geladeira, TV, ar-condicionado) | Usa o número da tabela |
| O ventilador tem consumo por velocidade | Pergunta a velocidade (baixa, média ou alta) |
| O Inmetro informa o consumo por ciclo (máquina de lavar) | kWh por ciclo x ciclos por mês |
| O Inmetro só informa a potência (lâmpada, micro-ondas, chuveiro, bomba) | Potência x horas por dia x 30 dias |

- Quando o usuário não informa o tempo de uso, o app usa um valor padrão e avisa que é uma estimativa.
- O chuveiro não tem valor padrão: o usuário precisa informar o tempo de banho.
- O usuário pode digitar a tarifa da própria conta de luz em vez de escolher a distribuidora.

---

## 9. Limitações

- O valor é uma estimativa: não inclui impostos (ICMS, PIS/COFINS), bandeira tarifária nem iluminação pública.
- O consumo do Inmetro é medido em laboratório. O uso real pode ser diferente.
- As horas de uso padrão foram definidas pelo grupo e ainda precisam de uma fonte oficial.
- A tarifa usada é a residencial comum (B1). Não vale para baixa renda, tarifa branca ou indústria.

---

## 10. Fontes dos dados

| Dado | Fonte |
|---|---|
| Consumo dos aparelhos | Inmetro, Programa Brasileiro de Etiquetagem (PBE) |
| Tarifas de energia | ANEEL, tarifas homologadas das distribuidoras |

---

## 11. O que já foi feito

- Dados do Inmetro e da ANEEL baixados e limpos com Pandas
- Banco PostgreSQL no Docker com as tabelas do projeto
- Cálculo de consumo e custo para 12 tipos de aparelho
- App de terminal funcionando de ponta a ponta
- API FastAPI no Docker, subindo junto com o banco (`docker compose up -d`)
- Diagrama BPMN inicial em `docs/`

## 12. Próximas etapas

- Análise exploratória com gráficos (Matplotlib/Seaborn)
- Modelo de Machine Learning para estimar o consumo de aparelhos fora do catálogo
- Assistente com IA generativa (RAG com LangChain)
- App Flutter ligado à API
- Terraform
- Documentação de ética e governança
