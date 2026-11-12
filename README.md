# Iamp

Copiloto de eficiência energética residencial.

O usuário escolhe um aparelho (marca e modelo) e a distribuidora de energia da casa. O Iamp mostra quanto esse aparelho gasta por mês, em kWh e em reais, soma os aparelhos da casa, classifica o perfil de consumo e sugere modelos mais econômicos, com o tempo que a troca leva para se pagar.

---

## 1. O problema

- A conta de luz é alta, mas as pessoas não sabem quais aparelhos gastam mais.
- Pouca gente entende kWh ou sabe calcular o custo de um aparelho.
- Os dados oficiais existem (Inmetro e ANEEL), mas estão espalhados e são difíceis de ler.

## 2. A solução

- Junta as tabelas de consumo do **Inmetro** e as tarifas da **ANEEL** num banco de dados.
- O usuário busca o aparelho e escolhe a distribuidora.
- O app calcula: `consumo (kWh/mês) x tarifa (R$/kWh) = custo por mês`.
- Soma vários aparelhos em "Minha casa" e mostra o que mais pesa na conta.
- Classifica o perfil de consumo da casa com Machine Learning (K-Means).
- Sugere modelos equivalentes que gastam menos e calcula o payback da troca.
- Estima aparelhos antigos ou fora do catálogo (geladeiras, eletros grandes e eletroportáteis).
- Monta um plano de economia com IA (Eco-Coach: RAG + Gemini), com dicas de documentos oficiais e as fontes citadas.
- Mostra também como o valor foi calculado e de onde veio cada dado.
- Funciona em português e em inglês, no modo escuro ou claro.

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
 Regras de cálculo e de equivalência   src/calculadora_residencial.py, src/estimativa.py
            |
            v
 Funções para as telas                 src/servico.py      Perfil (K-Means)  src/ml_pipeline.py
            |                                              Eco-Coach (RAG)   src/rag.py, src/rag_agent.py -> API do Gemini
            +--------------------------------------+---------------+
            v                                      v
 API FastAPI (Docker)  src/main.py      App de terminal (testes)  src/app_terminal.py
            |
            v
 App Flutter                           app_gerenciamento_energetico/

 Base do Eco-Coach: datasets/raw/rag/ -> scripts/carregar_rag.py -> tabela trechos_rag (pgvector)
```

### Tecnologias

| Parte | Tecnologia |
|---|---|
| Linguagem | Python 3.12 |
| Limpeza e análise | Pandas |
| Banco de dados | PostgreSQL 15 com pgvector |
| Acesso ao banco | SQLAlchemy Core + psycopg2 (SQL parametrizado, sem ORM) |
| API | FastAPI + Uvicorn |
| Machine Learning | SDV (CTGAN), scikit-learn (K-Means e Random Forest) |
| IA generativa | Gemini (`google-genai`): embeddings e texto do Eco-Coach |
| App | Flutter (Dart) |
| Containers | Docker e Docker Compose |
| Infraestrutura como código | Terraform |
| Nuvem | Render (API) + Neon (banco) |

### Tabelas do banco

| Tabela | O que guarda |
|---|---|
| `aparelhos` | Catálogo com marca, modelo, consumo e medidas de cada aparelho (litros, polegadas, BTU/h, kg, lumens...) |
| `distribuidoras` | Distribuidoras de energia e o estado de cada uma |
| `tarifas` | Tarifa residencial (B1) de cada distribuidora e quando ela vale |
| `vw_tarifa_vigente` | Visão com a tarifa que vale hoje para cada distribuidora |
| `cargas` | De qual arquivo veio cada dado e quando foi carregado |
| `consultas` | Histórico dos cálculos feitos no app (sem dados pessoais) |
| `usuarios`, `sessoes`, `casas`, `itens_casa` | Contas (opcionais) e as casas de cada pessoa, salvas na nuvem; a senha só como hash |
| `portateis` | Eletroportáteis (air fryer, secador...) com potência e uso típicos e a fonte de cada um |
| `trechos_rag` | Trechos dos documentos oficiais e seus vetores, para a busca do Eco-Coach |

O diagrama do banco (DER) está em [docs/der.png](docs/der.png).

### Aparelhos incluídos

Geladeira, TV, ar-condicionado, ventilador de mesa, ventilador de teto, chuveiro, lâmpada LED, lâmpada fluorescente, lâmpada de vapor de sódio, micro-ondas, máquina de lavar e bomba d'água.

Fora do catálogo, o Iamp também estima eletroportáteis (air fryer, secador de cabelo, ferro de passar...) e aparelhos antigos.

Ficaram de fora: fornos elétricos comerciais (não são de uso residencial) e aquecedores solares (geram economia, não consomem).

---

## 4. Estrutura das pastas

```
iamp/
├── datasets/
│   ├── raw/              # dados originais do Inmetro e da ANEEL
│   └── processed/        # dados limpos, prontos para o banco (+ residências da seed e sintéticas)
├── scripts/              # limpeza dos dados (um script por dataset), treino dos modelos e carga do RAG
├── src/                  # aplicação: banco, cálculo, estimativa, ML, Eco-Coach, API e app de terminal
├── tests/                # testes da API e das regras (pytest)
├── notebooks/            # análise exploratória (eda.ipynb)
├── app_gerenciamento_energetico/   # app Flutter
├── docs/                 # documento do processo (md e PDF), BPMN, DER e gráficos da EDA
├── infra/                # Terraform: local/ (Docker, em uso) e oracle/ (nuvem, pronto)
├── models/               # modelos treinados (ctgan.pkl, kmeans.pkl e refrigerador.pkl)
├── prompts/              # registro dos prompts usados com IA
├── skills/               # instruções permanentes para o agente de código (Claude Code)
├── Dockerfile            # imagem da API
├── docker-compose.yml    # sobe o PostgreSQL e a API
├── render.yaml           # publicação da API no Render
├── requirements.txt      # bibliotecas Python da API
├── requirements-dev.txt  # bibliotecas para os testes (pytest)
├── requirements-ml.txt   # bibliotecas para treinar os modelos (sdv, torch)
└── .env.example          # modelo das credenciais do banco e da chave do Gemini
```

---

## 5. Pré-requisitos

Instale nesta ordem:

1. **Git**: https://git-scm.com/downloads
2. **Python 3.12**: https://www.python.org/downloads/ (no Windows, marque "Add Python to PATH")
3. **Docker Desktop**: https://www.docker.com/products/docker-desktop/
4. **Flutter** (só para rodar o app): https://docs.flutter.dev/get-started/install

Para conferir se deu certo:

```bash
git --version
python --version
docker --version
flutter --version
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

Abra o `.env` e troque a senha em `POSTGRES_PASSWORD`. Para o Eco-Coach funcionar, coloque também a
`GEMINI_API_KEY` (gerada de graça no Google AI Studio). Esse arquivo não vai para o GitHub.

### Passo 5: subir o banco e a API

Abra o Docker Desktop e depois rode:

```bash
docker compose up -d --build
```

Isso sobe dois containers:

- `postgres_iamp`: o banco PostgreSQL (porta 5434)
- `api_iamp`: a API FastAPI (porta 8000)

Na primeira vez, a API carrega os dados de `datasets/processed/` no banco sozinha (leva cerca de 1 minuto)
e, se a `GEMINI_API_KEY` estiver no `.env`, também a base do Eco-Coach.
Ela também recarrega sozinha quando o banco foi criado por uma versão antiga do código (falta alguma coluna nova).
Depois de um `git pull`, rode o mesmo comando de novo para a API usar o código novo.

Se o build falhar com `failed to execute bake` (Docker Desktop novo no Windows pede uma permissão
`--allow=fs.read=Dockerfile`), rode assim no PowerShell:
`$env:BUILDX_BAKE_ENTITLEMENTS_FS="0"; docker compose up -d --build`.

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
  aparelhos:      24148
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

### Passo 9: abrir o app Flutter

Com a API rodando (Passo 5):

```bash
cd app_gerenciamento_energetico
flutter pub get
flutter run -d chrome
```

- `-d chrome` abre no navegador e é o jeito mais simples.
- `-d windows` abre como programa do Windows, mas precisa do Visual Studio com "Desenvolvimento para desktop com C++".
- No emulador Android, o app já usa `http://10.0.2.2:8000` (o computador visto pelo emulador).
- Em outro endereço: `flutter run -d chrome --dart-define=API_URL=http://192.168.0.10:8000`.

Testes do app: `flutter test`. Testes da API e das regras (na raiz do projeto):

```bash
pip install -r requirements-dev.txt
pytest                 # tudo (os testes de banco são pulados se o PostgreSQL não estiver no ar)
pytest -m "not banco"  # só os rápidos
```

### Passo 10 (opcional): subir tudo com Terraform

A mesma aplicação, criada como Infraestrutura como Código (passo a passo em [infra/README.md](infra/README.md)).
Ela usa as portas 8080 (API) e 5435 (banco), então roda junto com o `docker compose`.

```bash
cd infra/local
terraform init
terraform apply     # ~5 min na 1ª vez
```

- No Windows, com o Docker Desktop aberto, coloque no `terraform.tfvars`:
  `docker_host = "npipe:////./pipe/dockerDesktopLinuxEngine"`.
- A `gemini_api_key` do `terraform.tfvars` precisa ser igual à do `.env`, numa linha só. Senão o
  `/eco-coach` responde 503.

### Passo 11: publicar na nuvem (Render + Neon)

Para o app funcionar no celular em qualquer rede, com o computador desligado:

| Serviço | O que faz no Iamp | Plano |
|---|---|---|
| [Neon](https://neon.com) | PostgreSQL com pgvector (o banco) | grátis, sem cartão, 1 GB (o banco usa ~20 MB) |
| [Render](https://render.com) | Roda a API a partir do `Dockerfile` do GitHub, com endereço HTTPS fixo | grátis, 512 MB (a API usa ~150 MB) |

1. **Neon:** crie a conta (login pelo GitHub) e um projeto na região **AWS US East 2 (Ohio)**, a mesma do `render.yaml`.
   Copie o endereço de conexão (`postgresql://...?sslmode=require`).
2. **Render:** crie a conta (login pelo GitHub), **New > Blueprint** e escolha este repositório. O Render lê o
   [render.yaml](render.yaml) e pede dois segredos: `DATABASE_URL` (o endereço do Neon) e `GEMINI_API_KEY`.
   O dono do repositório (ou quem tem acesso de administrador) precisa autorizar o Render no GitHub.
3. Na primeira subida, com o banco vazio, a API carrega sozinha o catálogo e a base do Eco-Coach (~1 a 2 min).
   Teste em `https://<nome-do-servico>.onrender.com/saude`.
4. Gere o APK com esse endereço: `flutter build apk --release --split-per-abi --dart-define=API_URL=https://<nome-do-servico>.onrender.com`.

A cada merge na `main`, o Render publica a API de novo sozinho. No plano grátis o servidor **dorme depois de
15 min sem uso** e leva até ~1 min para acordar: o app chama a API assim que abre e, se a espera passar de
8 s, avisa que o servidor está acordando. Na apresentação, abra o app uns minutos antes.

---

## 7. API

Documentação interativa: **http://localhost:8000/docs** (dá para testar cada endereço em "Try it out").

| Endereço | Para que serve |
|---|---|
| `GET /aparelhos?busca=brastemp` | Busca aparelhos por marca e/ou modelo (opcional: `categoria`, `limite` por tipo de aparelho; cada item traz `total_categoria`) |
| `GET /marcas?categoria=refrigerador` | Marcas de um tipo de aparelho, com a quantidade de modelos |
| `GET /modelos?categoria=refrigerador&marca=consul` | Modelos de uma marca (até 50 por padrão) |
| `GET /aparelhos/{id}/uso` | Diz o que o app precisa perguntar: `horas`, `ciclos`, `velocidade` ou nada (`null`) |
| `GET /distribuidoras?uf=PR` | Lista as distribuidoras com tarifa vigente (opcional: `busca=copel`) |
| `POST /calcular` | Devolve o consumo (kWh/mês) e o custo (R$/mês e R$/ano) |
| `POST /sugestoes` | Modelos equivalentes que gastam menos, com a economia por mês e por ano |
| `POST /comparar` | Aparelho atual x modelo novo: economia e, com o preço, o payback em meses |
| `POST /classificar` | Perfil de consumo da casa (K-Means): Consciente, Moderado ou Ineficiente |
| `POST /eco-coach` | Plano de economia da casa escrito por IA, com as fontes citadas `[n]` |
| `POST /eco-coach/aparelho` | Dicas de economia para um aparelho (usado nos eletroportáteis) |
| `POST /calcular/refrigerador-antigo` | Geladeira fora do catálogo: pela etiqueta ou estimada pelo tipo, volume e ano de compra |
| `GET /estimativa/categorias`, `POST /calcular/estimado` | Eletro grande fora do catálogo: pelo número da etiqueta ou da plaqueta, ou pelos modelos parecidos |
| `POST /sugestoes/estimado`, `POST /comparar/estimado` | Sugestão de troca e payback para um aparelho estimado |
| `GET /resistivos`, `POST /calcular/resistivo` | Eletroportáteis (air fryer, secador, ferro...) por potência e tempo de uso |
| `GET /categorias`, `GET /ufs` | Listas para preencher filtros no app |
| `GET /saude` | Diz se a API e o banco estão no ar |
| `POST /contas`, `POST /login`, `POST /logout` | Criar conta (com o aceite do aviso de privacidade), entrar e sair. Devolvem um token |
| `GET`/`PATCH`/`DELETE /conta`, `GET /conta/dados` | Ver, corrigir e apagar a conta; baixar tudo o que ela guarda |
| `GET`/`POST /casas`, `PUT`/`DELETE /casas/{id}` | As casas da pessoa (uma ou mais) com os aparelhos de cada uma |

Com o cabeçalho `Accept-Language: en`, os textos das respostas (método, avisos, mensagens e o plano do Eco-Coach) vêm em inglês; sem ele, em português. As chaves do JSON e os números não mudam.

Fluxo do app: escolher o tipo, a marca e o modelo → perguntar o uso → escolher o estado e a distribuidora → calcular → adicionar à casa ou ver modelos mais econômicos.

Exemplo de `POST /calcular` (chuveiro Bosch EWI 5.5, 15 min por dia, Copel):

```json
{
  "aparelho_id": 9844,
  "distribuidora_id": 60,
  "horas_dia": 0.25
}
```

Resposta (resumida): `"kwh_mes": 41.25`, `"custo_mes": 31.68`, `"custo_ano": 380.17`, além de `metodo` e `avisos`.

`POST /sugestoes` recebe o mesmo corpo (mais `limite`, padrão 5). `POST /comparar` recebe também `alternativa_id` e, se quiser o payback, `preco_novo` em reais (os ids dos exemplos são ilustrativos):

```json
{
  "aparelho_id": 9844,
  "alternativa_id": 10233,
  "distribuidora_id": 60,
  "preco_novo": 2499.90
}
```

`POST /classificar` recebe os aparelhos da casa com o consumo de cada um:

```json
{
  "moradores": 3,
  "itens": [
    {"categoria": "chuveiro", "kwh_mes": 82.5},
    {"categoria": "refrigerador", "kwh_mes": 30},
    {"categoria": "televisor", "kwh_mes": 10}
  ]
}
```

Regras do corpo:

- Envie `distribuidora_id` **ou** `tarifa_manual` (R$/kWh da conta de luz), nunca os dois.
- `horas_dia` (0 a 24), `ciclos_mes` ou `velocidade` (`baixa`, `media`, `alta`) conforme o `GET /uso`. Se faltar, usa o valor padrão quando existe.
- `registrar` (padrão `true`, só no `/calcular`) grava o cálculo na tabela `consultas`.
- Erros: `404` quando o aparelho ou a distribuidora não existe, `422` quando falta ou sobra algum dado, `503` quando o banco, o modelo ou o Gemini não está disponível.

Os ids mudam se o banco for recriado: o app deve sempre pegar o id pela busca.

---

## 8. O app Flutter

O **Iamp** é para quem paga as contas de casa e quer economizar, incluindo pessoas mais velhas ou com pouca familiaridade com tecnologia. A interface é moderna, mas acessível por padrão.

Identidade visual: fundo preto, amarelo nos destaques (a cor da energia) e texto branco, pensada primeiro para celular Android. Cores, tamanhos de texto, espaçamentos e medidas ficam todos no tema (`lib/tema.dart`); as telas não usam valores soltos.

No menu (☰) a pessoa também escolhe:

- **Aparência:** escuro (padrão) ou claro. No modo claro o amarelo fica só nos preenchimentos e os detalhes usam um âmbar escuro, para manter o contraste.
- **Idioma:** português (padrão) ou inglês, para apresentar a quem não fala português. Os textos da API vêm no mesmo idioma.
- **Conta (opcional):** nome, e-mail e senha. Com ela, as casas ficam salvas na nuvem e aparecem em qualquer celular. Antes de criar, o app mostra o aviso de privacidade (o que fica guardado, para quê e onde) e só cria a conta com o aceite. Em "Minha conta" dá para corrigir os dados, sair ou apagar a conta com tudo o que ela guarda.

Aparência e idioma não ficam gravados: o app sempre abre escuro e em português. A conta também não fica aberta: ao fechar o app, é preciso entrar de novo.

**Várias casas:** no topo de "Minha casa" fica a casa aberta. Tocando nela, a pessoa troca de casa, cria outra (ex.: "Casa da praia"), renomeia ou apaga. Cada casa tem os próprios aparelhos, moradores, perfil e plano. Sem conta, as casas ficam só no celular até fechar o app.

| Regra | Como aparece no app |
|---|---|
| 60/30/10 | 60% preto, 30% branco e superfícies escuras, 10% amarelo (botões e o valor principal) |
| Detalhes amarelos | Ícones, bordas, divisórias e contornos são amarelos; o branco fica só para o texto |
| Cores com significado | Verde = economia ou resultado bom; vermelho = alerta ou erro. A cor sempre vem com um texto ou ícone |
| Texto legível | Texto base de 18, nada abaixo de 16; texto secundário em branco 80% (contraste AA no preto) |
| Fonte do sistema | O app respeita o tamanho de fonte do celular; até 2x nada quebra (o que ficaria lado a lado vai um embaixo do outro) |
| Reais primeiro | O valor em R$ é a informação principal; kWh e a fórmula aparecem como detalhe |
| Uma decisão por tela | O cálculo vai em etapas ("Etapa 2 de 6"), com botões grandes |
| Toque | Áreas de toque de no mínimo 48dp; o botão principal fica fixo embaixo (zona do polegar) |
| Leitor de tela | Cartões e botões têm descrição para TalkBack e VoiceOver (ex.: "Remover Chuveiro Lorenzetti da casa") |

Ícone do app: raio amarelo em fundo preto (`assets/icone/`). Depois de mudar a imagem, rode `dart run flutter_launcher_icons`.

A barra de baixo tem 3 abas, com ícone e texto: **Calcular**, **Minha casa** e **Economizar**.

| Tela | O que faz |
|---|---|
| 1. Qual aparelho? | Botões grandes com os tipos (geladeira, chuveiro, TV...), "Procurar pela marca" e "Não achou? Estime o gasto" |
| 2. Marca e modelo | Busca dentro do tipo escolhido; os resultados vêm separados por tipo em seções que abrem ao tocar |
| 3. Como você usa | Tempo por dia, lavagens por mês ou velocidade, só quando precisa |
| 4. Estado | Lista dos estados pelo nome. Oferece repetir a conta de luz usada antes, ou digitar a tarifa da conta |
| 5. Distribuidora | Empresas do estado, com busca pelo nome |
| 6. Quanto custa | Gasto por mês e por ano; consumo, tarifa e fórmula como detalhe |
| Estimar o gasto | Aparelho fora do catálogo, uma pergunta por tela ("Não sei" e "Não tenho" nas opcionais) |
| Minha casa | Total da conta, o que mais pesa, quantidade de cada aparelho e comparação com casas parecidas |
| Gastar menos | Modelos equivalentes que gastam menos |
| Vale a pena trocar? | Compara os dois modelos e mostra em quanto tempo a troca se paga, com o preço digitado |
| Economizar | Plano de economia escrito por IA com dicas oficiais (Inmetro e Cemig), curto (3 ações) e com as fontes citadas. Os números são calculados pelo Iamp |
| Como gastar menos | Dicas para um eletroportátil (eles não têm etiqueta do Inmetro, então não há sugestão de modelo) |

A lista da casa fica só na memória: ao fechar o app, ela recomeça vazia.

### Gerar o APK e publicar uma versão nova

O histórico das versões fica no [CHANGELOG.md](CHANGELOG.md). A cada versão nova:

1. Merge do Pull Request na `main`.
2. Subir a versão em `pubspec.yaml` (ex.: `1.1.0+2` → `1.2.0+3`; o número depois do `+` sempre sobe)
   e, se a API mudou, em `src/main.py`. Anotar o que mudou no `CHANGELOG.md`.
3. Publicar a API **antes** do APK (o app depende dela). Mudanças na API só acrescentam campos,
   para o app antigo continuar funcionando com a API nova.
4. Gerar o APK, sempre com `--split-per-abi` (o Flutter soma 1000 × arquitetura ao número de build;
   misturar com e sem essa opção faz o celular achar que a versão é mais antiga):
   ```bash
   cd app_gerenciamento_energetico
   flutter build apk --release --split-per-abi --dart-define=API_URL=http://<ip-ou-servidor>:8000
   ```
   O arquivo para quase todo celular: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`.
5. Criar a tag (`git tag v1.2.0` + `git push origin v1.2.0`) e uma Release no GitHub com o APK anexado.
   O APK não vai para dentro do repositório.

**Chave do projeto.** O celular só aceita a atualização se o APK novo for assinado com a mesma chave
do anterior. Sem chave, cada PC assina com a sua chave de teste e o APK de um colega não atualiza o de
outro (é preciso desinstalar). A chave é criada uma vez só:

```bash
keytool -genkey -v -keystore C:/Users/<usuario>/chaves/iamp.jks -keyalg RSA -keysize 2048 -validity 10000 -alias iamp
```

Depois copie `android/key.properties.example` para `android/key.properties` e preencha. O `.jks` e o
`key.properties` ficam fora do git e são passados para a equipe por canal privado. Se a chave se
perder, nenhum celular aceita mais atualizações: guarde uma cópia.

Para conferir um APK: `apksigner verify --print-certs <apk>` deve mostrar `CN=iamp, O=Projeto TCS 2026`.
O arquivo que vai para os celulares é copiado como `build/app/outputs/flutter-apk/iamp.apk`.

### Instalar no celular

1. Mande o `iamp.apk` para o celular (WhatsApp, Google Drive, e-mail). Não precisa de cabo USB.
2. Abra o arquivo e permita "instalar apps desta fonte" na primeira vez.
3. Atualizações instalam por cima. Quem instalou um APK antigo, assinado com a chave de teste
   (antes da versão 1.1.0), precisa desinstalar uma vez. A mensagem é "o pacote tem um conflito
   com um pacote já existente".

Para o app falar com a API:

- O endereço da API fica gravado no APK (`API_URL`). Com a API no Render (Passo 11), o endereço é
  fixo e o app funciona em qualquer rede.
- Com a API no computador, o endereço é o IP dele na rede Wi-Fi, que **muda a cada rede**: trocou de
  rede, gere o APK de novo com o IP novo. O celular precisa estar na mesma rede, com o Docker ligado.
- Algumas redes de instituição bloqueiam a comunicação entre aparelhos. Para testar, abra
  `http://<ip-do-computador>:8000/saude` no navegador do celular. Se não abrir, use o roteador de um
  celular ou a API publicada no Render.

**iPhone:** o APK não funciona no iPhone. A versão de iOS precisa ser gerada num Mac com Xcode, e para
instalar sem App Store é preciso uma conta Apple. Sem Mac, a alternativa é a versão web do app
(`flutter build web`) aberta no Safari.

---

## 9. Como o cálculo funciona

| Caso | Como calcula |
|---|---|
| O Inmetro informa o consumo mensal (geladeira, TV, ar-condicionado) | Usa o número da tabela |
| O ventilador tem consumo por velocidade | Pergunta a velocidade (baixa, média ou alta) e as horas por dia: o consumo do Inmetro é de 1 hora por dia |
| O Inmetro informa o consumo por ciclo (máquina de lavar) | kWh por ciclo x ciclos por mês |
| O Inmetro só informa a potência (lâmpada, micro-ondas, chuveiro, bomba) | Potência x horas por dia x 30 dias |

- Quando o usuário não informa o tempo de uso, o app usa um valor padrão e avisa que é uma estimativa.
- O chuveiro não tem valor padrão: o usuário precisa informar o tempo de banho.
- O usuário pode digitar a tarifa da própria conta de luz em vez de escolher a distribuidora.

---

## 10. Sugestão de troca e payback

O Iamp só compara modelos que fazem o mesmo serviço, com o **mesmo uso** e a **mesma tarifa** do aparelho do usuário:

| Aparelho | É equivalente quando tem |
|---|---|
| Geladeira e freezer | Mesmo tipo e volume parecido (15% para mais ou para menos) |
| TV | Tela do mesmo tamanho (5%) |
| Ar-condicionado | Mesmo tipo e mesma capacidade em BTU/h (5%) |
| Ventilador de mesa e de teto | Diâmetro parecido (10%) |
| Máquina de lavar | Mesmo tipo e capacidade parecida em kg (15%) |
| Lâmpada LED ou fluorescente | Mesma luminosidade em lumens (10%). Fluorescente pode virar LED |
| Bomba d'água | Motor de mesma potência (cv) |

Regras extras:

- Só entra modelo com consumo vindo do Inmetro (não os completados na limpeza dos dados).
- O modelo sugerido precisa gastar pelo menos 5% menos.
- Consumo abaixo de 40% da mediana dos equivalentes é tratado como erro de digitação no dado e fica de fora (exemplo real: HISENSE RS3P428NEDA com 28,0 kWh e a versão 127 V com 2,8 kWh).
- Variações do mesmo modelo (cor, voltagem) aparecem uma vez só.
- Sem sugestão para chuveiro (os modelos têm eficiência parecida, então a dica é reduzir o tempo de banho), micro-ondas (o Inmetro só informa a potência) e lâmpada de vapor de sódio (sem lumens no dataset).

**Payback** (calculado na API, em Python): `preço do modelo novo / economia por mês = meses para a troca se pagar`.
O catálogo do Inmetro não tem preços, então o usuário digita o preço que encontrou.

---

## 11. Perfil de consumo (Machine Learning)

1. `scripts/gerar_seed.py`: cria 3.000 residências por regras, com aparelhos reais do catálogo e tarifas da ANEEL.
2. `scripts/treinar_ctgan.py`: treina um CTGAN (SDV) e gera 5.000 residências sintéticas.
3. `scripts/treinar_kmeans.py`: agrupa as residências em 3 perfis (K-Means) pelo kWh por morador e pela parte do consumo de chuveiro, ar-condicionado e geladeira.
4. `src/ml_pipeline.py`: usa o `models/kmeans.pkl` para classificar uma casa (`POST /classificar`). A API não precisa de scikit-learn.

Para treinar de novo (cerca de 5 minutos no CPU):

```bash
pip install -r requirements-ml.txt
python scripts/gerar_seed.py
python scripts/treinar_ctgan.py
python scripts/treinar_kmeans.py
```

---

## 12. Limitações

- O valor é uma estimativa: não inclui impostos (ICMS, PIS/COFINS), bandeira tarifária nem iluminação pública.
- O consumo do Inmetro é medido em laboratório. O uso real pode ser diferente.
- As horas de uso padrão foram definidas pelo grupo e ainda precisam de uma fonte oficial.
- A tarifa usada é a residencial comum (B1). Não vale para baixa renda, tarifa branca ou indústria.
- O perfil da casa vem de um modelo treinado com residências sintéticas: serve como referência, não como avaliação oficial.
- O payback é simples: não considera juros, a venda do aparelho antigo nem reajustes da tarifa.
- O filtro de consumo suspeito (40% da mediana) é uma regra do grupo para evitar recomendar um modelo por causa de um erro no dado.
- A estimativa de aparelho fora do catálogo é aproximada e vem com uma faixa. Fora a geladeira, não há dado de época: sem o número da etiqueta, ela usa modelos atuais e pode subestimar um aparelho antigo.
- O plano do Eco-Coach é escrito por IA e pode errar mesmo com as regras do prompt; por isso cita as fontes e traz um aviso. Os números do plano são calculados pelo Iamp, não pela IA.
- Para o Google (Gemini) vão só números de consumo, trechos de documentos públicos e nomes de aparelhos, nada pessoal. No plano gratuito, o Google pode usar esse conteúdo para melhorar os produtos.

---

## 13. Fontes dos dados

| Dado | Fonte |
|---|---|
| Consumo dos aparelhos | Inmetro, Programa Brasileiro de Etiquetagem (PBE) |
| Tarifas de energia | ANEEL, tarifas homologadas das distribuidoras |
| Geladeiras antigas | Portaria Inmetro 20/2006 e tabela do Inmetro de 2001 (Queiroz et al., ACEEE 2003) |
| Dicas do Eco-Coach | Páginas do Inmetro (dicas, etiqueta, PBE) e cartilha de eficiência energética da Cemig (2025), listadas em `datasets/raw/rag/fontes.csv` |
| Eletroportáteis | Potência e uso típicos com a fonte de cada linha em `datasets/processed/eletroportateis.csv` (premissas do grupo) |

---

## 14. O que já foi feito

- Dados do Inmetro e da ANEEL baixados e limpos com Pandas
- Banco PostgreSQL no Docker com as tabelas do projeto
- Cálculo de consumo e custo para 12 tipos de aparelho
- App de terminal funcionando de ponta a ponta
- API FastAPI no Docker, subindo junto com o banco (`docker compose up -d`)
- Machine Learning: residências sintéticas (CTGAN) e perfil de consumo (K-Means)
- App Flutter ligado à API: cálculo, "Minha casa", perfil da casa, sugestão de troca e payback
- Conta opcional com várias casas salvas na nuvem (senha com hash, aviso de privacidade, apagar tudo)
- Diagramas BPMN em níveis (`docs/bpmn/`) e o completo (`docs/bpmn_processo.bpmn`), DER do banco (`docs/der.png`)
- Análise exploratória com gráficos (`notebooks/eda.ipynb`, imagens em `docs/graficos/`)
- Eco-Coach: plano de economia com RAG (pgvector + Gemini) e tela no app
- Estimativa de aparelhos fora do catálogo (geladeira com Random Forest e regra do Inmetro, eletros grandes, eletroportáteis)
- Terraform: infraestrutura local no Docker testada (API, banco, RAG) e a da Oracle Cloud pronta
- App redesenhado para o público geral (acessibilidade, uma decisão por tela, 3 abas), com modo claro e versão em inglês
- API pronta para a nuvem gratuita (Render + Neon, `render.yaml`)
- Documento do processo, com ética e governança (`docs/documento_processo.md` e o PDF)
- Versionamento (`CHANGELOG.md`, tags no GitHub) e APK Android assinado com a chave do projeto
