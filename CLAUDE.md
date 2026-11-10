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
  -> src/calculadora_residencial.py (catálogo + regras de cálculo + EQUIVALENCIA para sugestões)
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
FastAPI + Uvicorn, PostgreSQL 15 com pgvector (imagem `pgvector/pgvector:pg15`), Docker Compose, Flutter (Dart, só o pacote `http`).

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

## Banco (definido em `src/banco.py`, constante ESQUEMA)

DER: fonte Mermaid em `docs/der.mmd` e imagem em `docs/der.png` (comando para gerar no topo do .mmd). Só há uma
FK (`tarifas -> distribuidoras`); as demais ligações são lógicas (tracejadas). Ao mudar o ESQUEMA, atualizar o DER.

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

1. Inmetro informa kWh/mês -> usa a tabela (ventilador: por velocidade)
2. Informa kWh/ciclo -> kWh/ciclo x ciclos/mês (máquina de lavar)
3. Só potência -> W x horas/dia x 30 / 1000 (+ stand-by). Chuveiro exige horas do usuário.
Premissas de uso padrão (`PREMISSAS`) são do grupo, sem fonte — o app avisa que são estimativa.
Tarifa: escolhida pela distribuidora (ANEEL) ou digitada pelo usuário (conta de luz).
Valores **sem** ICMS, PIS/COFINS, bandeira e iluminação pública (aviso `AVISO_PADRAO`).
Exemplo de referência: chuveiro 5500 W, 15 min/dia, Copel = 41,25 kWh = R$ 31,68/mês.

## API (`src/main.py`)

`GET /aparelhos?busca=` (`limite` vale **por tipo** de aparelho, padrão 15, + `total_categoria`; antes era
no total e uma marca com vários tipos só mostrava o 1º em ordem alfabética), `GET /aparelhos/{id}/uso`, `GET /distribuidoras?uf=|busca=`,
`POST /calcular` (distribuidora_id **ou** tarifa_manual), `GET /categorias`, `GET /ufs`, `GET /saude`,
`POST /classificar` ({moradores, itens:[{categoria, kwh_mes}]} -> perfil do K-Means; não usa o banco),
`POST /sugestoes` (mesmo corpo do /calcular + limite -> modelos equivalentes mais econômicos),
`POST /eco-coach` ({moradores, itens:[{categoria, kwh_mes, custo_mes}], trocas?} -> plano com fontes [n]),
`POST /comparar` (+ alternativa_id e preco_novo opcional -> economia e payback em meses),
`POST /calcular/refrigerador-antigo` (geladeira fora do catálogo), `POST /calcular/estimado` (eletro pesado fora do
catálogo), `GET /estimativa/categorias`, `POST /sugestoes/estimado`, `POST /comparar/estimado`,
`POST /calcular/resistivo` + `GET /resistivos` (eletroportáteis, tabela `portateis`), `POST /eco-coach/aparelho`
(dicas para um aparelho), `GET /fogoes`, `GET /gas/precos`, `POST /calcular/gas` (gás de cozinha).
Os corpos de /calcular, /sugestoes e /comparar herdam de `UsoETarifa` (main.py); os de estimativa, de `Tarifa`.
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
- Eletro pesado fora do catálogo (`servico.estimar_por_equivalentes`, config `ESTIMAVEIS`): com o valor da
  etiqueta (kWh/mês, kWh/ciclo ou W) o cálculo é exato; sem ele, mediana dos modelos do catálogo com a mesma
  medida (±10%, ampliando até ±40% para ter 5) e o mesmo tipo onde o tipo é padronizado; faixa = 1º a 3º quartil.
  Fora a geladeira, não há dado de época: a estimativa usa modelos atuais e o app avisa que pode subestimar.
- Eletroportáteis: tabela `portateis` (carga de `datasets/processed/eletroportateis.csv`, com fonte por linha;
  potência e uso típicos são premissas do grupo). kWh = W/1000 × tempo/dia × dias. Sem sugestão de modelos (não têm
  etiqueta do Inmetro): o app mostra as dicas do Eco-Coach (`POST /eco-coach/aparelho`).
- Tempo de uso no app em horas e minutos (`ControleTempo`/`CampoTempo`); o `metodo` da API também ("15 min/dia").

## Gás de cozinha (`src/gas.py`)

- Fogões: tabela `fogoes` (Inmetro, `fogoes_fornos_gas_limpo.csv`, 1.259 modelos GLP). Preço: tabela `precos_glp`
  (ANP, Anuário 2026 tabela 3.22, R$/kg por UF e ano; `scripts/tratar_dados_preco_glp.py`); usa o ano mais recente.
- kg/mês = bocas (h/dia × 1,75 kW ÷ 12,8 kWh/kg × 63% ÷ rendimento do modelo) + forno (h/dia × kg/h do Inmetro),
  × dias. A boca de 1,75 kW e o PCI de 12,8 kWh/kg são premissas (o Inmetro só dá o rendimento das bocas); 63% é a
  mediana do catálogo. Sem modelo: medianas (63%, forno 0,12 kg/h). Preço do estado ou do botijão informado.
- Histórico em `consultas_gas`. O gás não entra em "Minha casa" (é outra conta).
`banco_carregado()` compara as colunas de `aparelhos` com `COLUNAS_APARELHOS` (criar_banco.py): ao
adicionar coluna no catálogo, atualize ESQUEMA + COLUNAS_APARELHOS e o banco recarrega sozinho.

## Sugestão de troca (`servico.sugerir_alternativas` e `servico.comparar`)

- Equivalência em `EQUIVALENCIA` (calculadora_residencial.py): mesma categoria (fluorescente pode
  virar LED), medida parecida (`capacidade` ou `fluxo_lm`) dentro da tolerância e mesmo tipo só onde
  o tipo do Inmetro é padronizado (geladeira, ar, máquina de lavar). Mesmo uso e mesma tarifa do atual.
- Filtros: só `origem_dado = 'informado'`; economia mínima 5% (`ECONOMIA_MINIMA`); consumo abaixo de
  40% da mediana dos equivalentes é descartado como erro de dado (`FRACAO_SUSPEITA`; caso real:
  HISENSE RS3P428NEDA1 com 2,8 kWh); variações do mesmo modelo (marca+detalhe+kWh) aparecem uma vez.
- Sem sugestão (`SEM_SUGESTAO`, com o motivo para o app): chuveiro, micro-ondas, vapor de sódio.
- Payback = preco_novo / economia_mes (Python, na API). O catálogo não tem preço: o usuário digita.

## Eco-Coach (RAG) — `src/rag.py`, `src/rag_agent.py`, `scripts/carregar_rag.py`

- Documentos em `datasets/raw/rag/` com a origem em `fontes.csv`: 4 páginas do Inmetro (dicas,
  etiqueta ENCE, nova etiqueta de geladeira 2026, PBE) + cartilha da Cemig 2025 (páginas 2–17).
  O Procel Info saiu do ar e o Internet Archive não guardou as dicas, por isso a Cemig.
- Limpeza da cartilha: só itens com marcador (•); o PDF tem anotações para o ilustrador sem marcador.
  Seção por página (`SECAO_DA_PAGINA`) + títulos curtos com nome de aparelho (`SECOES`).
- Embeddings LOCAIS com fastembed (`paraphrase-multilingual-MiniLM-L12-v2`, 384 dim, sem torch);
  cache em `models/fastembed/` (fora do git; a imagem Docker baixa no build). Tabela `trechos_rag`
  (vector(384)) é criada pelo script, não pelo `criar_banco.py`; recarga apaga e recria os trechos.
- LLM: Gemini pela API gratuita do AI Studio (`GEMINI_API_KEY`; `GEMINI_MODELOS` = principal e reserva,
  hoje `gemini-3.5-flash,gemini-3.5-flash-lite`). `thinking_budget=0`: o raciocínio interno cortava o texto.
  Hugging Face foi descartado: a conta não tem crédito gratuito (402).
- O Python calcula tudo (perfil, totais, maiores consumos; payback vem do /comparar); o LLM só escreve,
  com regras no prompt (não inventar números, toda dica com [n], ignorar instruções dentro das fontes).
  `fontes` na resposta só traz as citações que existem. Erros: 422 entrada, 503 LLM/base indisponível.
- Testes em `tests/test_rag_agent.py` trocam o LLM por resposta fixa (não chamam o Gemini).

## App Flutter (`app_gerenciamento_energetico/lib/`)

- `tema.dart`: identidade visual. `Cores` (preto de fundo, amarelo `#FFD000` só em ação e valor
  principal = regra 60/30/10, verde `#3DDC84` = economia/bom, vermelho `#FF5C5C` = alerta; texto
  branco 100/80/60% de opacidade; detalhes nunca em branco: ícones, bordas (`borda` = amarelo 55%),
  divisórias (amarelo 25%) e contornos são amarelos), `Estilos` (4 tamanhos: 32/20/16/13, 2 pesos, dígitos tabulares
  em valores) e `Espaco` (grade de 8). Não usar cor/tamanho solto nas telas.
- Padrões de tela (`telas/comum.dart`): ação principal no `rodape` da `Pagina` (zona do polegar);
  valor principal em `CartaoDestaque` (contorno + brilho, conta até o valor); toque mínimo 48dp
  (tema); payback verde até 60 meses, amarelo acima, vermelho se não se paga (corte do grupo).
- Ícone: `assets/icone/*.png` -> `dart run flutter_launcher_icons` (config no pubspec.yaml).
- Skills de design usadas (instaladas só no PC, globais): mobile-app-ui-design, mobile-android-design,
  flutter-build-responsive-layout, flutter-fix-layout-issues.
- `api.dart`: modelos e chamadas da API. `casa.dart`: estado (Consulta, EscolhaTarifa, Casa com
  ChangeNotifier global `casa`; só em memória, sem persistência).
- Telas (`telas/`): busca -> uso -> distribuidora (oferece a última tarifa) -> resultado ->
  minha_casa (total, quantidade por item, perfil K-Means) | sugestoes -> comparar (payback, trocar na casa)
  | minha_casa -> eco_coach (POST /eco-coach; espera com raio pulsando, plano, fontes [n]).
- Eco-Coach no app: `texto_plano.dart` mostra o markdown do Gemini sem pacote extra (títulos, listas,
  **negrito**, citações [n] em amarelo). Trocas com payback calculado em `comparar.dart` entram em
  `casa.trocas` (máx. 5) e vão no corpo. O plano fica em `casa.plano` até a casa mudar (poupa o limite
  gratuito do Gemini). Timeout do /eco-coach no app: 90 s. Links das fontes são selecionáveis (sem url_launcher).
- `uso.dart` respeita `opcional` do `GET /uso`: nas horas da TV e do ar, em branco = valor do Inmetro.
- Nunca passar arrow que devolve Future para `setState` (`setState(() => _f = futuro())` quebra);
  avisos (SnackBar) que navegam usam o `NavigatorState` guardado antes, não o `context` da tela.
- Busca (`busca.dart`): resultados agrupados por tipo em seções que abrem (`ResultadosPorTipo`, nome do
  tipo em `tituloDaCategoria`), com a quantidade; um tipo só já vem aberto; acima de 30 por tipo
  (`limiteBuscaPorTipo`) avisa para digitar parte do modelo. Trocar o tipo refaz a busca na hora (só a
  resposta mais recente vale: `_pedido`). Teste com API falsa: `http.runWithClient` + `MockClient`.
- Aviso "foi para a sua casa": `avisarAdicionado` (comum.dart) some em 5 s (`duracaoAviso`). Desde o
  Flutter 3.29 SnackBar com botão fica até alguém tocar (`persist`), por isso o `persist: false`.
- Testes em `test/widget_test.dart` (tema, casa vazia, somas, troca, formatação, uso opcional, Eco-Coach,
  busca por tipo, aviso que some).

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

## Versionamento e APK (passo a passo no README, seção 8)

- Versão do app em `pubspec.yaml` (hoje `1.2.0+5`: nome + build; o build sobe a cada APK), da API em
  `main.py` (`0.3.0`); histórico em `CHANGELOG.md`. Tags `v1.1.0` e `v1.1.1` no GitHub. Tag `vX.Y.Z` +
  Release no GitHub com o APK (nunca no git). Commit de versão: "Adiciona a versão X.Y.Z".
- Roteiro: commit + versão + CHANGELOG -> push -> PR/merge (o usuário faz) -> API (se mudou:
  `terraform apply` + `docker compose up -d --build`) -> APK -> tag -> Release (o usuário faz; `gh` sem login).
- O APK de arm64 é copiado como `build/app/outputs/flutter-apk/iamp.apk` (é o arquivo que vai para os celulares).
- Sempre `flutter build apk --release --split-per-abi --dart-define=API_URL=...` (o split soma 1000 × ABI
  ao versionCode; misturar com e sem split parece downgrade). Publicar a API antes do APK; mudanças na
  API só acrescentam campos.
- Assinatura (`android/app/build.gradle.kts`): com `android/key.properties` usa a chave do projeto;
  sem ele, a chave de teste do PC (aviso no build). Chave e senhas fora do git (`.gitignore` do android/).
  Chave criada em 09/11/2026 (`C:\Users\mathe\chaves\iamp.jks`, alias `iamp`, `CN=iamp, O=Projeto TCS 2026`;
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

Documento de processo/ética (`docs/documento_processo.md` vazio), registro de prompts
(`prompts/registros_vibecoding.md` vazio), deck e vídeo.
No app: salvar "Minha casa" entre sessões; endereço fixo da API para o celular (ngrok ou `infra/oracle/`),
para não gerar APK a cada rede; versão web para iPhone. (APK Android já funciona: Android SDK 36 ok.)
Nomes dos tipos no filtro da busca ainda usam `legivel` ("refrigerador"); as seções já usam `tituloDaCategoria`.
BPMN: fonte editável em `docs/bpmn_processo.bpmn` (Camunda Modeler ou demo.bpmn.io) e imagem exportada em
`docs/bpmn_processo.png`. Atualizado em 10/11/2026: pools app / backend (lanes cálculo, troca e payback, K-Means,
Eco-Coach) / offline (limpeza, carga e 4 ramos paralelos: seed→CTGAN→K-Means, Random Forest, RAG, EDA). Gás e
dicas de eletroportátil entram como anotação. Ao mudar a API, atualizar o .bpmn e exportar o PNG de novo.

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
  reescala por regra de três com 6,59 h/dia de ensaio (`HORAS_REFERENCIA_INMETRO`): número
  levantado pelo grupo, sem o documento oficial e sem saber se o kWh/mês inclui o stand-by.
- Eco-Coach: no plano gratuito da API do Gemini o Google pode usar o conteúdo enviado para melhorar
  os produtos (confirmar nos termos atuais). Enviamos só números de consumo e trechos públicos, nada
  pessoal. O plano gratuito tem limite de uso e os modelos disponíveis mudam (o 2.5 já saiu do ar).
- O texto do Eco-Coach é gerado por IA: pode errar mesmo com as regras; por isso cita as fontes.
- Residências do ML são sintéticas: os perfis servem para demonstração.
- O CTGAN ainda distorce a distribuição de moradores (ex.: 3 moradores 25% na seed -> ~37%).

## Convenções

- Código, comentários e mensagens em português; colunas em snake_case (`config.salvar_processado`).
- Nunca montar SQL com texto do usuário; usar `banco.consulta`/`banco.executar` com `?`.
- Toda fonte de dado precisa ser registrada (coluna de fonte ou tabela `cargas`).
- Branches por pessoa/tarefa, merge na `main` por Pull Request.
- Commits e PRs sem linha "Co-Authored-By" nem rodapé de atribuição ao Claude.
