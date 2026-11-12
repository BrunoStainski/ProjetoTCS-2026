# Iamp — contexto do projeto para o Claude Code

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
  -> src/calculadora_residencial.py (catálogo + regras de cálculo + EQUIVALENCE para sugestões)
  -> src/servico.py (funções usadas por qualquer interface)
  -> src/main.py (API FastAPI)  |  src/app_terminal.py (teste no terminal)
  -> app_gerenciamento_energetico/ (app Flutter ligado à API; ver seção "App Flutter")

RAG: datasets/raw/rag/ (+ fontes.csv) -> scripts/carregar_rag.py -> trechos_rag (pgvector)
     -> src/rag.py (busca) -> src/rag_agent.py (Gemini escreve) -> POST /eco-coach
ML: scripts/gerar_seed.py -> seed_residencias.csv -> scripts/treinar_ctgan.py -> models/ctgan.pkl
    + residencias_sinteticas.csv -> scripts/treinar_kmeans.py -> models/kmeans.pkl -> src/ml_pipeline.py
```

## Stack

Python 3.12 (o mesmo do Dockerfile; não usar 3.14), Pandas, SQLAlchemy **Core** com SQL
parametrizado (não há ORM; `banco.py` troca `?` por parâmetros nomeados), psycopg2,
FastAPI + Uvicorn, PostgreSQL 15 com pgvector (imagem `pgvector/pgvector:pg15`), Docker Compose, Flutter (Dart, só o pacote `http`
+ `flutter_localizations`, que vem com o SDK).

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
# Eco-Coach (GEMINI_API_KEY no .env; PostgreSQL no ar): carrega os documentos na base vetorial
python scripts/carregar_rag.py
# Testes (pip install -r requirements-dev.txt; sem o PostgreSQL, os de banco são pulados):
pytest                               # tudo;   pytest -m "not banco"  # só os rápidos
```

## Banco (definido em `src/banco.py`, constante SCHEMA)

DER: fonte Mermaid em `docs/der.mmd` e imagem em `docs/der.png` (comando para gerar no topo do .mmd). Só há uma
FK (`tarifas -> distribuidoras`); as demais ligações são lógicas (tracejadas). Ao mudar o SCHEMA, atualizar o DER.

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

1. Inmetro informa kWh/mês -> usa a tabela (ventilador: por velocidade). Ventilador: o kWh/mês do Inmetro é de
   **1 h por dia** (conferido nos CSVs brutos), então as horas são obrigatórias e multiplicam o valor
   (`INMETRO_REFERENCE_HOURS`; TV: 6,59 h). Sem horas, o `metodo` diz que é o valor do ensaio.
2. Informa kWh/ciclo -> kWh/ciclo x ciclos/mês (máquina de lavar)
3. Só potência -> W x horas/dia x 30 / 1000 (+ stand-by). Chuveiro exige horas do usuário.
Premissas de uso padrão (`ASSUMPTIONS`) são do grupo, sem fonte — o app avisa que são estimativa.
Tarifa: escolhida pela distribuidora (ANEEL) ou digitada pelo usuário (conta de luz).
Valores **sem** ICMS, PIS/COFINS, bandeira e iluminação pública (aviso `AVISO_PADRAO`).
Exemplo de referência: chuveiro 5500 W, 15 min/dia, Copel = 41,25 kWh = R$ 31,68/mês.

## API (`src/main.py`)

`GET /aparelhos?busca=` (`limite` vale **por tipo** de aparelho, padrão 15, + `total_categoria`; antes era
no total e uma marca com vários tipos só mostrava o 1º em ordem alfabética), `GET /marcas?categoria=`
(marcas do tipo + nº de modelos, agrupa por `UPPER(TRIM(marca))`), `GET /modelos?categoria=&marca=&limite=`
(modelos da marca, padrão 50 = `BRAND_MODEL_LIMIT`), `GET /aparelhos/{id}/uso`, `GET /distribuidoras?uf=|busca=`,
`POST /calcular` (distribuidora_id **ou** tarifa_manual), `GET /categorias`, `GET /ufs`, `GET /saude`,
`POST /classificar` ({moradores, itens:[{categoria, kwh_mes}]} -> perfil do K-Means; não usa o banco),
`POST /sugestoes` (mesmo corpo do /calcular + limite -> modelos equivalentes mais econômicos),
`POST /eco-coach` ({moradores, itens:[{categoria, kwh_mes, custo_mes}], trocas?} -> plano com fontes [n]),
`POST /comparar` (+ alternativa_id e preco_novo opcional -> economia e payback em meses),
`POST /calcular/refrigerador-antigo` (geladeira fora do catálogo), `POST /calcular/estimado` (eletro pesado fora do
catálogo), `GET /estimativa/categorias`, `POST /sugestoes/estimado`, `POST /comparar/estimado`,
`POST /calcular/resistivo` + `GET /resistivos` (eletroportáteis, tabela `portateis`), `POST /eco-coach/aparelho`
(dicas para um aparelho).
Os corpos de /calcular, /sugestoes e /comparar herdam de `UsageAndTariff` (main.py); os de estimativa, de `Tariff`.
Erros: 404 (não existe), 422 (dado faltando), 503 (banco ou modelo indisponível). Ids mudam ao recriar o banco.
A imagem da API leva só `models/kmeans.pkl` e `models/refrigerador.pkl` (`.dockerignore` exclui o resto de `models/`).

## Estimativa fora do catálogo (`src/estimativa.py`, `scripts/treinar_refrigerador.py`)

- Geladeira, em ordem: modelo no catálogo -> consumo do Inmetro; **etiqueta** informada -> kWh da etiqueta
  (antes de 2023 convertido para a metodologia atual) × Fi; sem etiqueta -> estimativa com faixa (`aproximado`).
- Sem etiqueta, compra antes de 2023: `Ie × Cp(AV)` da **Portaria Inmetro 20/2006** (Anexo VI: AV = Vr + f×Vc,
  f = 1,41/1,63/1,85 por estrelas, ×1,2 se frost-free; Cp = a×AV + b por categoria). O Cp foi feito com a tabela
  Inmetro de 2001 (`datasets/raw/refrigeradores_inmetro_2001.csv`, Queiroz et al. ACEEE 2003): Ie médio = 1,000.
  Até 2005: Ie da tabela 2001 (p25–p75). 2006–2022: faixa entre a mediana do Ie dos modelos atuais e o limite da
  classe A (0,846 combinado frost-free; 0,855 demais), ponto = meio. Compra a partir de 2023: Random Forest.
- Random Forest (tipo, frost-free, volume total; `monotonic_cst` no volume; GroupKFold por marca): MAE 3,88 kWh/mês
  (escala 2025) e 6,46 (escala antiga). O pkl guarda só a grade de previsões (a API não precisa de scikit-learn).
- Conversão antiga -> 2025: mediana de `consumo médio / consumo antigo` nos modelos com as duas medições no arquivo
  bruto, sem os 31 pares com valor copiado (razão 1,000); duplex frost-free 0,67 (18 pares), demais 0,70 (geral).
- Fi (desgaste): 1,00 até 5 anos, 1,10 até 10, 1,30 acima (premissa do grupo; fonte ainda não anexada).
  Vida útil de 16 anos (Queiroz 2003) gera aviso. O Ft (1,13 a 1,31) foi medido e descartado: só 17 geladeiras
  de 1 porta manuais no treino e extrapolação para 16 das 27 de 2001.
- Caso de validação: Consul CRM45 (duplex frost-free 407 L, freezer 90 L, 2014, etiqueta 52,5 kWh/mês):
  Ie = 0,762 (classe A); sem etiqueta a faixa contém a etiqueta (`tests/test_estimativa.py`).
- Catálogo: geladeira sem o consumo do padrão 2025 usa o consumo antigo × essa conversão
  (`origem_dado = 'convertido da metodologia antiga do Inmetro'`, 610 modelos): o app avisa e elas não entram
  como sugestão. Antes o catálogo misturava as duas escalas e exagerava a economia.
- Limpeza das geladeiras: o consumo antigo não é mais imputado nas linhas que têm o consumo do padrão 2025 (antes
  recebiam a média do grupo, ex.: 41,831608 nas Consul CRM); volume total menor que o do refrigerador é refeito
  pela soma dos compartimentos (`volume_corrigido`; caso real: Consul CRM44 com 94 L -> 377 L).
- Eletro pesado fora do catálogo, antigo ou sem modelo (`servico.estimate_from_equivalents`, config `ESTIMABLE`):
  tipo e tamanho (sempre, para comparar com modelos novos) e depois o número escrito no próprio aparelho
  (`formas`, enviado em `valor_etiqueta` + `campo_etiqueta`):
  etiqueta do Inmetro (kWh/ciclo da lavadora, kWh/mês da TV) ou **potência da plaqueta** (W) × horas, que vale
  para aparelho antigo (TV de tubo, ar de janela velho...). Ar e ventilador não pedem etiqueta: a do ar mudou de
  kWh/mês para kWh/ano em 2023 e a do ventilador é de 1 h/dia. Com potência, as horas são obrigatórias.
  Sem número: tipo com nome conhecido (`TYPE_NAMES`, ex.: "Automática que abre por cima") e tamanho em
  opções prontas (`tamanhos`) ou digitado -> "aparelho de referência" com a mediana (e os quartis) das colunas de
  consumo dos modelos com a mesma medida (±10%, ampliando até ±40% para ter 5) e o mesmo tipo onde o tipo é
  padronizado: o mesmo kWh/ciclo (ou W) entra no cálculo e no texto. Faixa = 1º a 3º quartil; com menos de 4
  modelos, menor e maior. Ventilador de teto não pede tamanho (diâmetro do catálogo com erros): usa todos.
  Fora a geladeira, não há dado de época: sem o número do aparelho, usa modelos atuais e o app avisa.
  Nesse caso o resultado vem com `pelos_parecidos: true`; o app repassa em `POST /sugestoes/estimado` e, sem
  sugestão, a mensagem explica que a comparação é circular (não diz que o aparelho "já é dos mais econômicos").
- Eletroportáteis: tabela `portateis` (carga de `datasets/processed/eletroportateis.csv`, com fonte por linha;
  potência e uso típicos são premissas do grupo). kWh = W/1000 × tempo/dia × dias. Sem sugestão de modelos (não têm
  etiqueta do Inmetro): o app mostra as dicas do Eco-Coach (`POST /eco-coach/aparelho`).
- Tempo de uso no app em horas e minutos (`TimeControl`/`TimeField`); o `metodo` da API também ("15 min/dia").

## Idioma: português (nativo) e inglês

Para apresentar a estrangeiros, o app inteiro troca para o inglês no menu (☰), seção "Idioma · Language".
Sempre abre em português; a escolha não é gravada.
- App: `lib/idioma.dart` (`idioma` = ValueNotifier, `tr('pt', 'en')`, `changeLanguage`). Todo texto de tela é
  `tr('...', '...')`, com as duas versões lado a lado. `changeLanguage` marca todas as telas para reconstruir; o
  menu também volta as abas para a 1ª tela (`restartTab`) e apaga perfil e plano (`casa.forgetApiTexts`),
  porque eles vieram da API no outro idioma. `MaterialApp.locale` + `GlobalMaterialLocalizations`: textos do
  Flutter ("Voltar"/"Back") seguem o idioma. Nos testes, `pageBack()` só acha "Back": no `IampApp` em português,
  tocar em `find.byTooltip('Voltar')`. `reais`/`number`/`readNumber` seguem o idioma (inglês: "R$ 1,234.50"; quem
  digita "0,85" continua certo). O `setUp` dos testes volta o idioma para `Idioma.pt`.
- API: `Accept-Language` (o app manda `pt-BR` ou `en`) -> middleware `RequestLanguage` (main.py) guarda o
  idioma numa ContextVar (`src/idioma.py`). Texto montado com números: `tr(pt, en)` no lugar. Texto fixo
  (constantes, ESTIMAVEIS, NOMES_DOS_TIPOS, nomes dos eletroportáteis, rag_agent.NOMES): `t(texto)` com o
  dicionário `src/traducoes.py` (chave = texto em português). `tests/test_idioma.py` falha se faltar tradução ou
  sobrar chave antiga. Sem cabeçalho = português (APK antigo e testes antigos iguais). Chaves (categoria,
  perfil "Consciente", velocidade) não mudam: o app traduz o nome. `unidades()`/`medida()` trocam pol/cv/litros
  e os separadores ("7.500 BTU/h" -> "7,500 BTU/h").
- Eco-Coach em inglês: a busca vetorial continua em português (documentos brasileiros); o prompt ganha
  `LANGUAGE_EN` (escrever em inglês, traduzir as dicas, manter [n]) e os números vão no formato americano.
  As fontes citadas continuam com o título em português (o app avisa).
- O histórico (`consultas`) guarda `metodo` no idioma em que a pessoa viu.

## Gás de cozinha: removido

O grupo decidiu focar só em energia elétrica: o cálculo de gás de cozinha (fogões do Inmetro, preço do
GLP da ANP, `src/gas.py`, tela do app, endpoints e tabelas) saiu do projeto. `banco.SCHEMA` ainda apaga
`fogoes`, `precos_glp` e `consultas_gas` de bancos antigos, e `database_loaded()` recarrega o banco se a
tabela `fogoes` ainda existir.

`database_loaded()` compara as colunas de `aparelhos` com `APPLIANCE_COLUMNS` (criar_banco.py): ao
adicionar coluna no catálogo, atualize SCHEMA + COLUNAS_APARELHOS e o banco recarrega sozinho.

## Sugestão de troca (`servico.sugerir_alternativas` e `servico.comparar`)

- Equivalência em `EQUIVALENCE` (calculadora_residencial.py): mesma categoria (fluorescente pode
  virar LED), medida parecida (`capacidade` ou `fluxo_lm`) dentro da tolerância e mesmo tipo só onde
  o tipo do Inmetro é padronizado (geladeira, ar, máquina de lavar). Mesmo uso e mesma tarifa do atual.
- Filtros: só `origem_dado = 'informado'`; economia mínima 5% (`MIN_SAVINGS`); consumo abaixo de
  40% da mediana dos equivalentes é descartado como erro de dado (`SUSPECT_FRACTION`; caso real:
  HISENSE RS3P428NEDA1 com 2,8 kWh); variações do mesmo modelo (marca+detalhe+kWh) aparecem uma vez.
- Sem sugestão (`NO_SUGGESTION`, com o motivo para o app): chuveiro, micro-ondas, vapor de sódio.
- Payback = preco_novo / economia_mes (Python, na API). O catálogo não tem preço: o usuário digita.

## Eco-Coach (RAG) — `src/rag.py`, `src/rag_agent.py`, `scripts/carregar_rag.py`

- Documentos em `datasets/raw/rag/` com a origem em `fontes.csv`: 4 páginas do Inmetro (dicas,
  etiqueta ENCE, nova etiqueta de geladeira 2026, PBE) + cartilha da Cemig 2025 (páginas 2–17).
  O Procel Info saiu do ar e o Internet Archive não guardou as dicas, por isso a Cemig.
- Limpeza da cartilha: só itens com marcador (•); o PDF tem anotações para o ilustrador sem marcador.
  Seção por página (`PAGE_SECTION`) + títulos curtos com nome de aparelho (`SECTIONS`).
- Embeddings pela API do Gemini (`gemini-embedding-001`, `GEMINI_EMBEDDING_MODEL`, 768 dim; `rag.vectorize`
  com `task` RETRIEVAL_DOCUMENT na carga e RETRIEVAL_QUERY na busca; `_question_vector` guarda as perguntas
  repetidas). Antes eram locais (fastembed, 384 dim), mas o modelo ocupava ~550 MB e a API não cabia nos 512 MB
  do Render grátis: hoje a API usa ~110 MB (pico 150 MB com a carga). Vão ao Google os trechos públicos e as
  perguntas de busca (nomes de aparelhos), nada do usuário. Falha do Gemini vira `RuntimeError` -> 503.
  Tabela `trechos_rag` (vector(768)) é recriada pelo `carregar_rag.py` (DROP + CREATE). Base vazia ao subir
  (banco novo, ex.: Neon): a API roda o `carregar_rag.py` sozinha (`load_rag` em main.py; a imagem leva
  `datasets/raw/rag/` e o script). Sem a chave, só avisa e o /eco-coach responde 503.
- LLM: Gemini pela API gratuita do AI Studio (`GEMINI_API_KEY`; `GEMINI_MODELOS` = principal e reserva,
  hoje `gemini-3.5-flash,gemini-3.5-flash-lite`). `thinking_budget=0`: o raciocínio interno cortava o texto.
  Hugging Face foi descartado: a conta não tem crédito gratuito (402).
- O Python calcula tudo (perfil, totais, maiores consumos; payback vem do /comparar); o LLM só escreve,
  com regras no prompt (não inventar números, toda dica com [n], ignorar instruções dentro das fontes).
  `fontes` na resposta só traz as citações que existem. Erros: 422 entrada, 503 LLM/base indisponível.
- Testes em `tests/test_rag_agent.py` trocam o LLM por resposta fixa (não chamam o Gemini).

## App Flutter (`app_gerenciamento_energetico/lib/`)

Público: quem paga as contas de casa, incluindo pessoas mais velhas ou com pouca familiaridade com
tecnologia. Interface moderna, mas acessível por padrão. Nome exibido: **Iamp** (I maiúsculo) em todo
lugar visível (app, web, Android, iOS).

- `tema.dart`: tudo o que é visual. `Cores` (paleta preto e amarelo `#FFD000`, verde = economia,
  vermelho = alerta; texto branco 100/90/80%, nada abaixo de 80% para manter contraste AA no preto),
  `Spacing` (grade 4/8) e a extensão `Iamp` (ThemeExtension) com os estilos de texto (34/22/18/16, base 18,
  nada abaixo de 16), cores com significado, raios, ícones, alvo de toque (48dp) e as decorações
  `highlightCard`/`badge`. Nas telas: `final t = Iamp.de(context);` e nunca cor/tamanho solto.
- Acessibilidade: o app respeita o tamanho de fonte do sistema; com 150% ou mais (`largeFont`) o que
  ficaria lado a lado empilha (`SideBySide`, `TimeField`, `TypeGrid`). Nenhuma informação só por cor
  (payback tem frase "Se paga rápido/Demora/Não se paga"; perfil tem nome e ícone). Cartões clicáveis com
  `MergeSemantics`, botões de ícone com tooltip que diz o aparelho, `AnimatedValue` lido só com o valor final.
- Navegação (`navegacao.dart` + `telas/inicio.dart`): barra inferior com 3 abas (Calcular, Minha casa,
  Economizar), ícone + texto; cada aba tem a própria pilha (`Navigator` + `ScaffoldMessenger`), então a
  barra fica visível durante o cálculo. `goTo(AppTab, restart:, closeCurrent:)` troca de aba.
- Boas-vindas (`telas/boas_vindas.dart`): abre por cima das abas (`initialRoute: '/boas-vindas'` monta
  '/' embaixo); só a `IampBrand(size: 120, nameSize: 56)` e o botão (sem texto, pedido do grupo);
  "Comece a economizar" fecha e vai para Calcular etapa 1; voltar do Android nela fecha o app.
  `IampApp(showWelcome: false)` nos testes das abas.
- Etapa 2 com tipo escolhido (`ModelScreen`): lista de todas as marcas do tipo (`_BrandList`, GET /marcas)
  filtrada pelo texto digitado; cada marca é um `ExpansionTile` que só busca os modelos ao abrir (GET /modelos).
  "Buscar" continua a busca por texto (o resultado substitui a lista). Sem tipo, não há lista de marcas.
- Menu de acesso rápido (`telas/menu.dart`, `drawer` da casca): botão ☰ (tooltip "Menu") só na 1ª tela de
  cada aba (`AppPage` usa `Scaffold.maybeOf` + `isFirst`); itens Início, Calcular, Estimar, Minha casa,
  Economizar. Itens são `ListTile` (texto quebra com fonte 2x; `NavigationDrawerDestination` estourava).
- Marca (`IampBrand`, comum.dart): `assets/icone/icone.png` com contorno amarelo esmaecido e o nome ao lado.
  Usa `cacheWidth` (nos testes a imagem vem como `ResizeImage`). O código dos colegas não passa pelo
  `dart format`: formatar só os arquivos que você mudou.
- Uma decisão por tela. Cálculo do catálogo em 6 etapas ("Etapa n de 6", `calculationStep`): tipo
  (`SearchScreen`, botões grandes) -> marca/modelo (`ModelScreen`) -> uso (`UsageScreen`) -> estado (`StateScreen`,
  oferece a última tarifa) -> distribuidora (`DistributorScreen`; ou `BillTariffScreen`) -> resultado.
  Estimativa (`estimar.dart`): uma pergunta por tela, com "Não sei"/"Não tenho" nas opcionais; voltar
  volta uma pergunta (`PopScope`).
- R$ é a informação principal; kWh, tarifa e fórmula ficam como texto secundário ou em "Como calculamos".
- Padrões (`telas/comum.dart`): `AppPage` (ação principal no `footer`), `QuestionHeader`, `OptionCard`,
  `HighlightCard`, `InfoCard`, `PartBar` (barra + % escrito), `ErrorMessage`, `Loading`.
- Ícone: `assets/icone/*.png` -> `dart run flutter_launcher_icons` (config no pubspec.yaml).
- `api.dart`: modelos e chamadas da API. `casa.dart`: estado (Consulta, EscolhaTarifa, Casa com
  ChangeNotifier global `casa`; só em memória, sem persistência). Remover item tem "Desfazer" (`reinsert`).
- Minha casa: total por mês, cada item com R$, % da conta, quantidade (−/+) e botões visíveis ("Ver modelos
  que gastam menos", "Remover"); perfil K-Means mostrado em R$ por pessoa (tarifa média da casa).
- Economizar (`eco_coach.dart`): só chama o /eco-coach quando a pessoa toca em "Montar meu plano"; o plano
  fica em `casa.plano` até a casa mudar (poupa o limite gratuito do Gemini). `texto_plano.dart` mostra o
  markdown do Gemini sem pacote extra (títulos em letras normais, listas, **negrito**, citações [n] em
  amarelo). Trocas com payback de `comparar.dart` entram em `casa.trocas` (máx. 5). Timeout: 90 s.
- `uso.dart` respeita `opcional` do `GET /uso`: nas horas da TV e do ar, "Não sei" = valor do Inmetro.
- Nunca passar arrow que devolve Future para `setState` (`setState(() => _f = futuro())` quebra).
- Busca: resultados agrupados por tipo (`ResultsPerType`, `categoryTitle`); um tipo só já vem aberto;
  acima de 30 por tipo (`searchLimitPerType`) avisa para digitar parte do modelo; só a resposta mais
  recente vale (`_request`). Teste com API falsa: `http.runWithClient` + `MockClient`.
- Aviso "foi para a sua casa": `notifyAdded` some em 5 s (`noticeDuration`, `persist: false`).
- Testes em `test/widget_test.dart`: fluxo completo com API falsa, abas, estimativa pergunta a pergunta,
  fonte 2x sem estouro (tela de 360dp), guidelines de toque 48dp, rótulos e contraste
  (`meetsGuideline`), Eco-Coach, somas e formatação.

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

## Terraform (`infra/`; passo a passo em `infra/README.md`)

**Em uso: `infra/local/`** (provider `kreuzwerker/docker`, Docker Desktop). Recria o compose como IaC,
com prefixo `iamp_tf` e portas 8080 (API) / 5435 (banco, só 127.0.0.1) para conviver com o compose:
rede + volume + postgres (`wait` até healthy) + imagem da API via `terraform_data` + `local-exec`
`docker build` (tag = hash de src/, datasets/processed, requirements, Dockerfile, kmeans.pkl; o bloco
`build` do provider trava no Docker Desktop em "load remote build context") + API (`wait` no /saude) +
`docker_container.carga_rag` (`attach`, `must_run=false`) que roda `carregar_rag.py` com o script e os
documentos copiados por `upload` (não estão na imagem). Senha via `random_password`; `cd infra/local;
terraform init; terraform apply`.
Testado em 09/11/2026 (Terraform 1.17, winget; o `terraform.exe` não entra no PATH até abrir outro terminal):
apply ok, `plan` sem mudanças, /saude, /calcular (chuveiro Copel = R$ 31,68) e /eco-coach na 8080.
- Windows: o provider só acha o Docker Desktop com
  `docker_host = "npipe:////./pipe/dockerDesktopLinuxEngine"` (no tfvars ou `-var`); o padrão
  `docker_engine` falha. O Docker Desktop precisa estar aberto.
- `gemini_api_key` no tfvars: idêntica à do `.env`, numa linha só. Chave quebrada em duas linhas ou com
  caracteres a mais = /eco-coach 503 (`ClientError` nos dois modelos). Saída do terraform pode mostrar a
  chave em erros: mascarar antes de exibir.

**Pronto para depois: `infra/oracle/`** (sem conta ainda):
- Oracle Cloud Always Free: 1 VM ARM `VM.Standard.A1.Flex` (Ubuntu 24.04) rodando o próprio
  `docker-compose.yml`. O PostgreSQL gerenciado da Oracle não é gratuito, então o banco é container.
- Rede própria (VCN, sub-rede pública); firewall libera só 22 (`ssh_origem_permitida`) e 8000.
- Repo privado: a VM não faz `git clone`. O `archive_file` zipa o projeto (excludes ~ `.dockerignore`,
  mas mantém `scripts/` e `datasets/raw/rag/`) e o `terraform_data.deploy` envia por SSH, grava o
  `.env` (senha do banco via `random_password`), roda `docker compose up --build --wait` e o
  `carregar_rag.py` dentro da imagem da API. `terraform apply` de novo = publicar código novo.
- Segredos só no state/tfvars (no `.gitignore`), nunca nos metadados da VM. State local, API em HTTP.
- Credenciais da Oracle: `~/.oci/config` (perfil `oci_perfil`). App: `--dart-define=API_URL=<api_url>`.

## Modo claro, transições e cadastro (app)

- Modo claro: `Palette.dark`/`Palette.light` (tema.dart) com os mesmos papéis de cor; `iampTheme(light:)` e
  `Iamp.forPalette`. `lightMode` (ValueNotifier) é escutado pelo MaterialApp; menu, seção "Aparência"
  (Escuro/Claro). Abre no escuro e não grava a escolha. No claro o amarelo `#FFD000` não tem contraste no branco:
  fica só em preenchimento (`t.highlightFill` + `t.onFill` preto) e `t.highlight` vira âmbar `#7A5A00`. Nas telas,
  preenchimento amarelo = `highlightFill`; ícone/texto de destaque = `highlight`. Nunca `AppColors.*` direto
  (são as cores do escuro). Teste de contraste AA no claro em `widget_test.dart` (grupo "Modo claro").
- Transições: `StepTransition` (tema.dart) no `pageTransitionsTheme` de todas as plataformas (280 ms, desliza
  + apaga); barra de etapa com `TweenAnimationBuilder` na `AppPage`; perguntas da estimativa com
  `AnimatedSwitcher` (`_forward` dá o lado). Tudo respeita `MediaQuery.disableAnimationsOf`.
- Cadastro: `conta.dart` (`account` = ValueNotifier<Account?>, nome + e-mail) e `telas/cadastro.dart`
  (`SignUpScreen`), aberto pelas boas-vindas e pelo menu. Opcional, só em memória, **sem chamada à API**
  (há teste disso). O menu ficou mais comprido: nos testes, rolar com `scrollUntilVisible` até Aparência/Idioma.
- Cadastro e LGPD: nome e e-mail são dados pessoais; a LGPD vale mesmo em projeto de curso gratuito (a exceção
  acadêmica do art. 4º é parcial e não cobre um app distribuído a terceiros). Para ligar o cadastro ao banco
  falta: consentimento registrado e aviso de privacidade, senha com hash (argon2/bcrypt), HTTPS (o Render dá),
  rotas para ver/corrigir/apagar os dados, não mandar dado pessoal ao Gemini e, na tabela `consultas`, decidir
  se o histórico fica ligado à pessoa. Enquanto isso não existir, o cadastro não sai do aparelho.

## Nuvem: Render (API) + Neon (banco)

- Escolhidos porque a Oracle (instituição) só libera o acesso em até 2 semanas e a apresentação é antes; os dois
  são grátis, sem cartão, com login pelo GitHub. `infra/oracle/` continua pronto como alternativa.
- `render.yaml` (Blueprint): serviço web Docker, plano free, região ohio (a mesma do projeto Neon "Iamp", AWS us-east-2),
  `healthCheckPath: /saude`, deploy a cada push na `main`. Segredos no painel: `DATABASE_URL` (Neon) e
  `GEMINI_API_KEY`. `Dockerfile` usa `${PORT:-8000}`; `config.py` troca `postgresql://` por
  `postgresql+psycopg2://` (o SQLAlchemy 2.1 usa o psycopg 3 nesse formato e o projeto usa o psycopg2).
- Simulado em 11/11/2026 no Docker com banco vazio e `--memory=512m`: carga automática do catálogo e do RAG,
  /saude, /calcular, /marcas, /eco-coach ok; pico de 150 MB.
- Render grátis dorme depois de 15 min sem uso (~1 min para acordar): o app chama `Api.wakeUp()` no `main`,
  `requestLimit` = 75 s (Eco-Coach 120 s) e `Loading` avisa depois de 8 s (`Loading.waitBeforeHint`).
- Docker Desktop novo no Windows: `docker compose build` falha com "failed to execute bake" (pede
  `--allow=fs.read=Dockerfile`); usar `BUILDX_BAKE_ENTITLEMENTS_FS=0` antes do comando.

## Versionamento e APK (passo a passo no README, seção 8)

- Versão do app em `pubspec.yaml` (hoje `2.0.0+6`: nome + build; o build sobe a cada APK), da API em
  `main.py` (`0.5.0`); histórico em `CHANGELOG.md`. Tags `v1.1.0` e `v1.1.1` no GitHub. Tag `vX.Y.Z` +
  Release no GitHub com o APK (nunca no git). Commit de versão: "Adiciona a versão X.Y.Z".
- Roteiro: commit + versão + CHANGELOG -> push -> PR/merge (o usuário faz) -> API (se mudou:
  `terraform apply` + `docker compose up -d --build`) -> APK -> tag -> Release (o usuário faz; `gh` sem login).
- O APK de arm64 é copiado como `build/app/outputs/flutter-apk/iamp.apk` (é o arquivo que vai para os celulares).
- Sempre `flutter build apk --release --split-per-abi --dart-define=API_URL=...` (o split soma 1000 × ABI
  ao versionCode; misturar com e sem split parece downgrade). Publicar a API antes do APK; mudanças na
  API só acrescentam campos.
- Assinatura (`android/app/build.gradle.kts`): com `android/key.properties` usa a chave do projeto;
  sem ele, a chave de teste do PC (aviso no build). Chave e senhas fora do git (`.gitignore` do android/).
  Chave criada em 09/11/2026 (`C:\Users\mathe\keys\iamp.jks`, alias `iamp`, `CN=iamp, O=Projeto TCS 2026`;
  senha aleatória só no `key.properties`, não abrir). Conferir: `apksigner verify --print-certs` e
  `aapt dump badging` (build-tools 36.0.0 do SDK). Quem instalou o 1º APK (chave de teste) desinstala uma vez.
- Celular: o `API_URL` fica gravado no APK. Ele aponta para o IP do PC na rede (`ipconfig`/Wi-Fi), que
  muda a cada rede (FIEP-CONV = 10.164.48.89; outra rede = outro IP) -> trocou de rede, gera o APK de novo.
  O firewall do Windows já libera o `com.docker.backend.exe`. Redes de instituição (ex.: FIEP-CONV) podem
  isolar os aparelhos: teste `http://<ip>:8000/saude` no navegador do celular; se não abre, usar o roteador
  do celular, um túnel (ngrok com domínio fixo, não configurado) ou a API publicada por `infra/oracle/`.
- iOS: o APK não serve; gerar IPA exige Mac com Xcode (+ conta Apple para instalar) e liberar HTTP no
  `ios/Runner/Info.plist` (hoje sem exceção do ATS). Sem Mac, a alternativa é a versão web (`flutter build web`,
  a API já libera CORS) aberta no Safari.

## Próximas etapas

Documento do projeto: `docs/documento_processo.md` escrito (11 seções, segue o guia da banca); o PDF
entregável sai de `python scripts/gerar_pdf_documento.py` (Chrome/Edge headless, `markdown` no
requirements-dev). Seção 2 usa os BPMN em níveis de `docs/bpmn/` (0_visao_geral com subprocessos [+] e
servidor/Gemini como caixa-preta; 1_calculo, 2_troca_payback, 3_perfil, 4_eco_coach, 5_treino_offline),
gerados por `scripts/gerar_bpmn_visoes.py` (.bpmn editável + .svg vetorial + .png 2x para o deck; cores:
amarelo usuário, azul Python, verde ML, roxo IA generativa; sem bpmn-js, o SVG é desenhado pelo script).
Mudou o processo? ajuste o script, rode-o e gere o PDF de novo. O diagrama completo do grupo fica no
Anexo A (inteiro + 3 partes cortadas no marcador `<!-- BPMN_PARTES -->`). Registro de prompts
(`prompts/registros_vibecoding.md` vazio), deck e vídeo.
No app: salvar "Minha casa" entre sessões; endereço fixo da API para o celular (ngrok ou `infra/oracle/`),
para não gerar APK a cada rede; versão web para iPhone. (APK Android já funciona: Android SDK 36 ok.)
BPMN: fonte editável em `docs/bpmn_processo.bpmn` (Camunda Modeler ou demo.bpmn.io) e imagem exportada em
`docs/bpmn_processo.png`. Atualizado em 10/11/2026: pools app / backend (lanes cálculo, troca e payback, K-Means,
Eco-Coach) / offline (limpeza, carga e 4 ramos paralelos: seed→CTGAN→K-Means, Random Forest, RAG, EDA). Dicas
de eletroportátil entram como anotação. Em 12/11/2026 saiu a anotação do gás (e ANP/fastembed dos nomes).
Ao mudar a API, atualizar o .bpmn e exportar o PNG de novo.
PENDENTE: tirar o gás do `docs/documento_processo`.

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
  reescala por regra de três com 6,59 h/dia de ensaio (`INMETRO_REFERENCE_HOURS`): número
  levantado pelo grupo, sem o documento oficial e sem saber se o kWh/mês inclui o stand-by.
- Eco-Coach: no plano gratuito da API do Gemini o Google pode usar o conteúdo enviado para melhorar
  os produtos (confirmar nos termos atuais). Enviamos só números de consumo e trechos públicos, nada
  pessoal. O plano gratuito tem limite de uso e os modelos disponíveis mudam (o 2.5 já saiu do ar).
- O texto do Eco-Coach é gerado por IA: pode errar mesmo com as regras; por isso cita as fontes.
- A busca do Eco-Coach usa os embeddings do Gemini: os trechos dos documentos públicos e as perguntas de busca
  (nomes de aparelhos) vão para o Google. Nada pessoal; antes os vetores eram gerados no próprio servidor.
- Residências do ML são sintéticas: os perfis servem para demonstração.
- O CTGAN ainda distorce a distribuição de moradores (ex.: 3 moradores 25% na seed -> ~37%).

## Convenções

- Nomes no código (classes, métodos, funções, variáveis) em **inglês** (padronizado em 11/11/2026); textos para
  o usuário, mensagens, comentários e docstrings em português. O que é contrato continua em português: chaves do
  JSON da API (`JSON_NAMES` + `ApiModel` em main.py ligam o campo em inglês ao nome do JSON), parâmetros de URL
  (`Query(alias="busca")`), colunas do banco/CSV e nomes de arquivo (`servico.py`, `telas/busca.dart`).
  Repassar `**kwargs`: as chaves do dicionário são nomes de parâmetro (em inglês). Colunas em snake_case
  (`config.save_processed`).
- Nunca montar SQL com texto do usuário; usar `banco.query`/`banco.run` com `?`.
- Toda fonte de dado precisa ser registrada (coluna de fonte ou tabela `cargas`).
- Branches por pessoa/tarefa, merge na `main` por Pull Request.
- Commits e PRs sem linha "Co-Authored-By" nem rodapé de atribuição ao Claude.
