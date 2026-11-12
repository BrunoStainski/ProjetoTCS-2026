# Registros de vibecoding — Iamp

Histórico dos prompts que guiaram o projeto, organizado por fase e por tema. Cada registro traz o prompt como
foi enviado, o que saiu dele e, quando for o caso, o que mudou depois. A ideia é mostrar como a IA foi usada
e onde o grupo decidiu diferente do que ela sugeriu.

| Fase | Ferramenta | Uso |
|---|---|---|
| 1 · Concepção | Gemini (notebook "Projeto ML") | Ideia, requisitos, primeiro BPMN, primeiras limpezas e esboço do ML |
| 2 · Desenvolvimento | Claude Code (VS Code) | Código, testes, infraestrutura, documentação, guiado pelo `CLAUDE.md` |

---

## Fase 1 · Concepção (Gemini)

O notebook começou com o nome provisório *EcoEnergy AI*. Foram 27 prompts; aqui ficam os que levaram a uma
decisão. Os de continuação ("e depois?", "como termino de ajustar?") e os envios de captura de tela ficaram de
fora.

### 1.1 Requisitos e ideia

**Prompt 1: requisitos do projeto**
> "Requisitos para o desenvolvimento do projeto: Equipe de 4 pessoas, entrega via GitHub/GitLab, README em
> markdown, slides (máx. 20 min), documento do processo (md ou pdf), BPMN da regra de negócio, treinamento de ML
> ou integração com IA de terceiros com base de conhecimento, aplicação Web ou Mobile com backend, frontend, banco
> de dados, infraestrutura automatizada com Terraform e arquivos de prompts para o vibecoding. Esses são os
> requisitos do projeto."

- **Resultado:** proposta de um copiloto de eficiência energética residencial. O usuário informa os aparelhos e
  a cidade, o sistema cruza com o Inmetro e a ANEEL, o ML classifica a casa e um agente com RAG escreve um plano
  de economia com payback.
- **Depois:** a ideia central ficou. Mudou a entrada: em vez de digitar a classe energética (A a E), o usuário
  escolhe a marca e o modelo, e o consumo vem do catálogo do Inmetro.

**Prompt 3: validação da ideia**
> "Certo, vamos com essa ideia."

**Prompt 20: nome oficial**
> "Decidimos que o nome do projeto será Iamp."

- **Resultado:** Iamp = **IA** + **Amp** (ampère).

### 1.2 BPMN

**Prompt 4: início do BPMN**
> "Certo, então quero começar a dar passos no BPMN, estou utilizando o Camunda."

**Prompt 6: passo a passo no Camunda**
> "Pode me dar um passo a passo de como passar isso pro Camunda?"

**Prompt 9: padrão de referência**
> "https://camunda.com/bpmn/reference/ gostaria de deixar mais parecido com essa referência."

- **Resultado:** primeiro diagrama com dois pools (app Flutter e backend) e lanes para API + SQL, ML e GenAI,
  ligados por message flows (requisição e resposta).
- **Depois:** a estrutura de pools e lanes ficou. O conteúdo foi refeito na Fase 2 para o fluxo real (cálculo,
  sugestão de troca e payback, K-Means, Eco-Coach e um pool offline para limpeza e treino). Saiu o gateway de
  "cold-start" (menos de 50 registros → CTGAN), porque o CTGAN passou a rodar offline, não a cada pedido.
  Arquivo atual: `docs/bpmn_processo.bpmn`.

### 1.3 Limpeza dos dados

**Prompt 12: valores nulos**
> "No notebook 4 não seria melhor substituir os valores nulos por valores médios?"

- **Resultado:** imputação pela média de aparelhos parecidos (marca + tipo, depois só o tipo), e não pela
  média geral. Exemplo que motivou a regra: a média geral das geladeiras duplex (32,93 kWh/mês) não serve para
  um frigobar (14,87 kWh/mês).
- **Depois:** a imputação por grupo ficou, mas o valor imputado passou a ser marcado
  (`origem_dado = 'derivado ou estimado na limpeza'`). O app avisa o usuário e esses aparelhos não entram nas
  sugestões de troca.

**Prompt 14: mesmo processo em outra base**
> "Agora o mesmo processo com esse dataset, me avise sobre as alterações feitas."

- **Resultado:** o padrão de 5 etapas aplicado aos sistemas solares acoplados (1.197 → 262 linhas válidas):
  nomes padronizados, colunas inúteis removidas, deduplicação, filtro de valores impossíveis e imputação por
  grupo.
- **Depois:** aquecedor solar e a gás ficaram fora do escopo do app (o foco é energia elétrica). Os scripts
  continuam no pipeline.

**Prompt 15: notebook quebrado por conflito de merge**
> *(Envio do conteúdo do notebook `Aquecedores-de-agua-e-gas.ipynb` com os marcadores de conflito do Git
> `<<<<<<< HEAD` / `>>>>>>> 4ff9aeb…` e uma célula duplicada.)*

- **Resultado:** JSON do notebook reconstruído sem os marcadores. Foi o primeiro sinal de que notebooks
  (`.ipynb`) atrapalham o trabalho em grupo com Git.

**Prompt 17: de notebooks para script**
> "Voltando no notebook dos refrigeradores e semelhantes, gostaria de mudar para um único arquivo .py."

- **Resultado:** os 5 notebooks da geladeira viraram um script com `pathlib`.
- **Depois:** virou o padrão do projeto. Há um `scripts/tratar_dados_*.py` por base e o
  `scripts/executar_pipeline.py` roda todos. Notebook ficou só para a EDA (`notebooks/eda.ipynb`).

**Prompt 22: PDF para CSV**
> "Como faço para transformar esse file PDF em .csv?"

**Prompt 23: tratamento dos chuveiros**
> "Mesmo padrão de antes, tratar dados com um arquivo .py e me fale o que foi removido."

- **Resultado:** a tabela de chuveiros do Inmetro (só em PDF) foi extraída com `pypdf` e tratada em
  `scripts/tratar_dados_chuveiros.py`.

### 1.4 Estrutura e banco

**Prompt 21: estrutura de pastas**
> "Como fica a estruturação das pastas?"

- **Resultado:** `datasets/raw` e `datasets/processed`, `docs/`, `infra/`, `models/`, `prompts/`, `scripts/`
  e `src/`. Continua sendo a estrutura do repositório.

**Prompt 24: recarregar o banco**
> "Ele inseriu os dados já, como faço para tirar todas as tabelas e importar pelo VS Code?"

**Prompt 25: rodar tudo pela pasta scripts**
> "Lembrando que essa é minha estrutura das pastas e que quero rodar todos os scripts na pasta scripts."

- **Resultado:** um script que apagava o esquema e importava cada CSV como uma tabela (`DataFrame.to_sql`).
- **Depois:** trocado pelo `src/criar_banco.py`, com esquema definido à mão (tipos, chaves, `CHECK`), SQL
  parametrizado, a view da tarifa vigente e a tabela `cargas` (de qual arquivo veio cada dado). O banco passou
  a subir no Docker com pgvector, e as credenciais saíram do código para o `.env`.

### 1.5 Machine Learning e Eco-Coach

**Prompt 26: camada de ML**
> "Como seria feita a ML?"

- **Resultado:** quatro ideias: regressão do consumo real (idade + clima), CTGAN para o cold-start, K-Means para
  o perfil da casa e OCR da etiqueta (opcional).

**Prompt 27: o recomendador**
> "E no caso a implementação da ML no modelo A, seria implementado outro modelo na parte de Advisor (para
> mostrar como melhorar o consumo)?"

- **Resultado:** em vez de um segundo modelo, uma arquitetura em 3 etapas. (1) O ML estima o consumo.
  (2) Um motor em Python + SQL acha o modelo equivalente mais econômico e calcula o payback
  (preço ÷ economia por mês). (3) O agente generativo escreve o plano.
- **Depois:** essa divisão ficou e é a base do Eco-Coach: o Python calcula todos os números e o LLM só escreve.
  O que mudou na Fase 2:
  - **K-Means:** treinado com casas sintéticas do **CTGAN** (não existem dados abertos de consumo por casa),
    com kWh por morador e a fração do chuveiro, do ar e da geladeira, em vez da porcentagem de aparelhos classe A.
  - **Regressão:** virou um Random Forest só para geladeiras fora do catálogo, junto com a Portaria Inmetro
    20/2006 para as antigas. Clima e OCR não entraram.
  - **RAG:** sem LangChain (o fluxo é uma busca e uma geração, então o código direto basta). Vetores no próprio
    PostgreSQL (pgvector) em vez de Chroma/FAISS. Documentos do Inmetro e a cartilha da Cemig, já que o Procel
    Info saiu do ar. LLM: Gemini.

---

## Fase 2 · Desenvolvimento (Claude Code)

Na Fase 2 o contexto do projeto fica no `CLAUDE.md`: arquitetura, regras de cálculo, convenções e limitações.
O agente lê esse arquivo em toda sessão, então os prompts podem ser curtos. Cada mudança passa por branch,
testes e Pull Request revisado pelo grupo.

*(Registros a adicionar.)*
