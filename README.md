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
            v
 App de terminal (para testes)         src/app_terminal.py
```

### Tecnologias

| Parte | Tecnologia |
|---|---|
| Linguagem | Python 3.12 |
| Limpeza e análise | Pandas |
| Banco de dados | PostgreSQL 15 |
| Acesso ao banco | SQLAlchemy + psycopg2 |
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
├── docker-compose.yml    # sobe o PostgreSQL
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

### Passo 5: subir o banco de dados

Abra o Docker Desktop e depois rode:

```bash
docker compose up -d
```

Para conferir se o container `postgres_iamp` está rodando:

```bash
docker ps
```

### Passo 6 (opcional): refazer a limpeza dos dados

Os dados limpos já estão em `datasets/processed/`. Só rode este passo se mudar algum dado bruto ou script de limpeza.

```bash
python scripts/executar_pipeline.py
```

### Passo 7: carregar os dados no banco

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

## 7. Como o cálculo funciona

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

## 8. Limitações

- O valor é uma estimativa: não inclui impostos (ICMS, PIS/COFINS), bandeira tarifária nem iluminação pública.
- O consumo do Inmetro é medido em laboratório. O uso real pode ser diferente.
- As horas de uso padrão foram definidas pelo grupo e ainda precisam de uma fonte oficial.
- A tarifa usada é a residencial comum (B1). Não vale para baixa renda, tarifa branca ou indústria.

---

## 9. Fontes dos dados

| Dado | Fonte |
|---|---|
| Consumo dos aparelhos | Inmetro, Programa Brasileiro de Etiquetagem (PBE) |
| Tarifas de energia | ANEEL, tarifas homologadas das distribuidoras |

---

## 10. O que já foi feito

- Dados do Inmetro e da ANEEL baixados e limpos com Pandas
- Banco PostgreSQL no Docker com as tabelas do projeto
- Cálculo de consumo e custo para 12 tipos de aparelho
- App de terminal funcionando de ponta a ponta
- Diagrama BPMN inicial em `docs/`

## 11. Próximas etapas

- Análise exploratória com gráficos (Matplotlib/Seaborn)
- Modelo de Machine Learning para estimar o consumo de aparelhos fora do catálogo
- API com FastAPI
- Assistente com IA generativa (RAG com LangChain)
- App Flutter ligado à API
- Dockerfile da API e Terraform
- Documentação de ética e governança
- Completar o estado de cada distribuidora (`distribuidoras_uf.csv`)
