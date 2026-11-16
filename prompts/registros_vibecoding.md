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
O agente lê esse arquivo em toda sessão, então os prompts podem ser curtos e informais. As instruções que valem
sempre ficam nas skills de `skills/` (estrutura do projeto, boas práticas de Python/FastAPI e de Flutter, regras
de negócio do cálculo, da troca, do perfil e do Eco-Coach, ambiente virtual e requisitos do projeto final). Cada
mudança passa por branch, testes e Pull Request revisado pelo grupo.

Os registros abaixo são das sessões do João (Claude Code no VS Code, de 06/11 a 16/11/2026). As sessões dos
outros membros podem ser acrescentadas no mesmo formato.

### 2.1 Regras de trabalho com o agente

Combinados que apareceram nos próprios prompts e viraram padrão:

- **Ler e aprovar antes de subir:** "não de o commit no github, espere eu ler e aprovar para subir". O agente
  trabalha numa branch, explica o que fez e só faz commit/push quando pedido ("sobe ai chefe", "pode dar um push").
- **Sincronizar antes de mexer:** muitos pedidos começam com "da um pull no projeto ai" ou "confira se precisa da
  pull". O agente traz a `main`, resume o que os colegas mudaram e atualiza a própria branch antes de continuar.
- **Perguntar ao agente o que falta:** "meu amigo, o que falta para finalizar o projeto?" virou o jeito de
  revisar o projeto contra o guia do professor (a skill `requisitos-projeto-final`).
- **Sem atribuição ao Claude nos commits:** regra do `CLAUDE.md`. Os commits saem em nome de quem pediu.

### 2.2 Banco e ambiente

**Prompt: erro ao carregar o banco** (06/11)
> "quando eu dei python criar_banco.py deu erro, consegue concertar?"

- **Resultado:** não era bug no código. O Docker Desktop estava fechado, então o PostgreSQL não respondia. O
  agente abriu o Docker, subiu os containers e carregou o banco (24.155 aparelhos, 99 distribuidoras).
- **Depois:** o agente avisou que o `.env.example` estava preparado para commit com a senha real do banco. A senha
  voltou a ser um texto de exemplo. Ver também 2.8.

**Prompt: instalar o Flutter** (09/11)
> "procura o flutter e instala pra mim pfvr"

- **Resultado:** o Flutter já estava baixado na pasta Downloads. O agente moveu para `C:\Users\joaol\flutter`,
  pôs no PATH e abriu o app no Chrome ligado à API.

### 2.3 Infraestrutura com Terraform

**Prompt: quando fazer o Terraform** (06/11)
> "voce acha que compensa ja fazer o terraform agora?"

- **Resultado:** o agente recomendou esperar o RAG, porque ele mudava a infraestrutura (imagem do Postgres com
  pgvector e a chave do LLM como segredo). O grupo seguiu essa ordem.

**Prompt: Oracle Cloud** (06/11)
> "vamos fazer o terraform ent? vamos usar o oracle gratuito para a nuvem"

- **Resultado:** `infra/oracle/`: uma VM ARM gratuita rodando o próprio `docker-compose.yml`, rede própria e
  firewall só com SSH e a porta da API. Passou no `terraform validate`, mas não foi aplicado: a conta da Oracle
  pela instituição demora até duas semanas.

**Prompt: Terraform local** (09/11)
> "preciso fazer o terraform em um docker local, não vamos conseguir a conta oracle no momento, consegue fazer
> tudo e depois me explicar brevemente o que foi feito? não de o commit no github, espere eu ler e aprovar para
> subir"

- **Resultado:** `infra/local/` com o provider Docker: rede, volume, PostgreSQL, imagem e container da API e a
  carga do RAG, nas portas 8080 e 5435 para não brigar com o compose. Testado com `apply`, `/saude`, `/calcular`
  e `/eco-coach`.
- **Depois:** no Windows o build pelo provider travava; o agente trocou por um `docker build` chamado pelo
  Terraform. Para a apresentação, a nuvem escolhida foi o Render + Neon (gratuitos), e a Oracle ficou pronta como
  alternativa.

### 2.4 Documentação e BPMN

**Prompt: onde documentar** (10/11)
> "com base em todos os contextos, tudo que foi produzido, precisamos fazer a documentação, é melhor fazer em um
> documento separado?"

- **Resultado:** o README ficou para quem roda o código e o `docs/documento_processo.md` para a banca (processo,
  justificativas técnicas, ética e segurança), com o PDF gerado por `scripts/gerar_pdf_documento.py`.

**Prompt: BPMN mais legível** (10/11)
> "não tem como arrumar de alguma maneira o bpmn, para ele ficar visivelmente melhor para a banca da tcs?"

- **Resultado:** o BPMN foi dividido em níveis: uma visão geral com subprocessos [+] e 5 diagramas de detalhe
  (cálculo, troca e payback, perfil, Eco-Coach e treino offline), gerados por `scripts/gerar_bpmn_visoes.py` com
  cores por tipo de tarefa. O diagrama completo do grupo foi para o Anexo A.

**Prompt: revisar os documentos** (12/11)
> "preciso que vc corrija os mds que estiverem inclompletos ou errados"

- **Resultado:** README, documento do processo, `CLAUDE.md`, skills e o README do app (que ainda era o modelo
  padrão do Flutter) foram conferidos contra o código: versões, rotas da API, embeddings do Gemini, Render + Neon,
  modo claro, inglês, LGPD e número de testes.

**Prompt: tirar o gás e as próximas etapas** (12/11)
> "retire as proximas etapas de ambos os documentos, e retire o gas também, não vamos usar mais no projeto"

- **Resultado:** saíram as seções de próximos passos do README e do documento do processo, e todas as menções ao
  gás de cozinha (ANP, fogões), que o grupo tirou do escopo para focar em energia elétrica.

### 2.5 Ouvir o professor: Eco-Coach mais curto

**Prompt** (11/11)
> "no nosso advisor, de como economizar e onde mostra aparelhos recomendados, o professor falou que tem muito
> texto, tem como encurtar um pouco o texto?"

- **Resultado:** o prompt do Gemini passou a pedir no máximo ~120 palavras no plano (1 frase de diagnóstico e
  3 ações) e ~80 nas dicas por aparelho (antes ~250 e ~180). Avisos e mensagens de espera do app também ficaram
  mais curtos. Os testes do RAG conferem o novo formato sem chamar o Gemini.

### 2.6 Várias casas na mesma conta

**Prompt** (12/11)
> "seguinte preciso nesse momento, que no aplicativo o usuario consiga registrar uma ou mais casas na mesma
> conta, como podemos fazer isso?"

- **Resultado:** antes de escrever código, o agente mostrou como o estado da casa funcionava e perguntou onde as
  casas seriam guardadas: só na memória, no celular ou no servidor.

**Prompt de continuação**
> "vai ficar salvo na nuvem, meu amigo ja adicionou essas questões da nuvem"

- **Resultado:** o agente procurou no GitHub (a `main` e todas as branches) e não achou código de login ou de
  contas. A "nuvem" pronta era a hospedagem (Render + Neon). Ele pediu para confirmar com o colega, para não fazerem
  o mesmo trabalho duas vezes.
- **Depois:** o colega confirmou que não tinha esse código ("ele disse que não tem"), e o agente fez a conta na
  nuvem com várias casas:
  - **API:** tabelas `usuarios`, `sessoes`, `casas` e `itens_casa`, senha guardada só como hash (scrypt), token de
    sessão guardado só como hash, aceite do aviso de privacidade obrigatório e rotas para ver, corrigir e apagar
    os dados (LGPD).
  - **App:** criar, trocar, renomear e apagar casas; tela de conta; gravação automática na nuvem.
  - **Testes:** 9 na API e 10 no app, mais o teste de ponta a ponta no Docker.
- **Depois (colegas):** login mantido no celular (`flutter_secure_storage`), termo de consentimento e limite de
  tentativas de senha.

### 2.7 Apresentação

**Prompt** (13/11)
> "lembra do arquivo que te mandei da apresentação? consegue mandar um textinho para os dois primeiros topicos,
> para eu utilizar na apresentação"

- **Resultado:** o arquivo não estava na sessão (o agente não guarda conversas antigas). Ele avisou isso e usou o
  roteiro do guia do professor (skill `requisitos-projeto-final`): textos para falar em "Contexto e problema" e
  "Mapeamento e arquitetura", com os números do próprio documento (24 mil aparelhos, 99 distribuidoras, payback da
  geladeira).
- **Lição:** o agente não lembra arquivos de outras conversas; o que precisa durar vai para o repositório.

### 2.8 O que aprendemos usando o agente

- **Contexto escrito vale mais que prompt longo.** Com o `CLAUDE.md` e as skills atualizados, prompts de uma
  linha ("da um pull", "sobe ai") bastam.
- **Segredo não vai no prompt nem no git.** Numa sessão, uma chave de API foi colada no chat e depois colocada no
  `.env.example`. A revisão antes do push barrou o arquivo, e a regra ficou: o `.env.example` só tem campos vazios
  e chave exposta deve ser trocada. A chave não aparece neste registro.
- **O agente confere antes de afirmar.** Ele roda os testes e chamadas reais à API e diz o que não conseguiu
  verificar (por exemplo, o Terraform da Oracle sem conta).
- **A decisão continua do grupo.** O agente propõe e explica as opções; quem decide é o grupo (ordem
  RAG → Terraform, nuvem gratuita, onde guardar as casas).
