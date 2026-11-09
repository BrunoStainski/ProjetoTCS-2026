# iamp

Copiloto de eficiência energética residencial.

O usuário escolhe um aparelho (marca e modelo) e a distribuidora de energia da casa. O iamp mostra quanto esse aparelho gasta por mês, em kWh e em reais, soma os aparelhos da casa, classifica o perfil de consumo e sugere modelos mais econômicos, com o tempo que a troca leva para se pagar.

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
 Regras de cálculo e de equivalência   src/calculadora_residencial.py
            |
            v
 Funções para as telas                 src/servico.py      Perfil (K-Means)  src/ml_pipeline.py
            |                                                      |
            +--------------------------------------+---------------+
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
| Machine Learning | SDV (CTGAN) e scikit-learn (K-Means) |
| App | Flutter (Dart) |
| Containers | Docker e Docker Compose |

### Tabelas do banco

| Tabela | O que guarda |
|---|---|
| `aparelhos` | Catálogo com marca, modelo, consumo e medidas de cada aparelho (litros, polegadas, BTU/h, kg, lumens...) |
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
│   └── processed/        # dados limpos, prontos para o banco (+ residências da seed e sintéticas)
├── scripts/              # limpeza dos dados (um script por dataset) e treino dos modelos
├── src/                  # aplicação: banco, cálculo, API e app de terminal
├── app_gerenciamento_energetico/   # app Flutter
├── docs/                 # BPMN e documentação
├── infra/                # Terraform (em construção)
├── models/               # modelos treinados (ctgan.pkl e kmeans.pkl)
├── prompts/              # registro dos prompts usados com IA
├── Dockerfile            # imagem da API
├── docker-compose.yml    # sobe o PostgreSQL e a API
├── requirements.txt      # bibliotecas Python da API
├── requirements-ml.txt   # bibliotecas para treinar os modelos (sdv, torch)
└── .env.example          # modelo das credenciais do banco
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
Ela também recarrega sozinha quando o banco foi criado por uma versão antiga do código (falta alguma coluna nova).
Depois de um `git pull`, rode o mesmo comando de novo para a API usar o código novo.

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

Testes do app: `flutter test`.

---

## 7. API

Documentação interativa: **http://localhost:8000/docs** (dá para testar cada endereço em "Try it out").

| Endereço | Para que serve |
|---|---|
| `GET /aparelhos?busca=brastemp` | Busca aparelhos por marca e/ou modelo (opcional: `categoria`, `limite` por tipo de aparelho; cada item traz `total_categoria`) |
| `GET /aparelhos/{id}/uso` | Diz o que o app precisa perguntar: `horas`, `ciclos`, `velocidade` ou nada (`null`) |
| `GET /distribuidoras?uf=PR` | Lista as distribuidoras com tarifa vigente (opcional: `busca=copel`) |
| `POST /calcular` | Devolve o consumo (kWh/mês) e o custo (R$/mês e R$/ano) |
| `POST /sugestoes` | Modelos equivalentes que gastam menos, com a economia por mês e por ano |
| `POST /comparar` | Aparelho atual x modelo novo: economia e, com o preço, o payback em meses |
| `POST /classificar` | Perfil de consumo da casa (K-Means): Consciente, Moderado ou Ineficiente |
| `GET /categorias`, `GET /ufs` | Listas para preencher filtros no app |
| `GET /saude` | Diz se a API e o banco estão no ar |

Fluxo do app: buscar o aparelho → perguntar o uso → escolher a distribuidora → calcular → adicionar à casa ou ver modelos mais econômicos.

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
- Erros: `404` quando o aparelho ou a distribuidora não existe, `422` quando falta ou sobra algum dado, `503` quando o banco ou o modelo não está disponível.

Os ids mudam se o banco for recriado: o app deve sempre pegar o id pela busca.

---

## 8. O app Flutter

Identidade visual: fundo preto, amarelo nos destaques (a cor da energia) e texto branco, pensada primeiro para celular Android. Cores, tamanhos de texto e espaçamentos ficam todos em `lib/tema.dart`.

| Regra | Como aparece no app |
|---|---|
| 60/30/10 | 60% preto, 30% branco e superfícies escuras, 10% amarelo (botões e o valor principal) |
| Detalhes amarelos | Ícones, bordas, divisórias e contornos são amarelos; o branco fica só para o texto |
| Cores com significado | Verde = economia ou resultado bom; vermelho = alerta ou erro |
| Hierarquia | 4 tamanhos de texto e 2 pesos; o valor é maior que o rótulo; texto secundário em branco 60% |
| Zona do polegar | O botão principal de cada tela fica fixo embaixo |
| Toque | Áreas de toque de no mínimo 48dp (padrão do Android) |
| Momento de pico | Valores "contam" até o resultado; adicionar à casa e o payback têm animação |

Ícone do app: raio amarelo em fundo preto (`assets/icone/`). Depois de mudar a imagem, rode `dart run flutter_launcher_icons`.

| Tela | O que faz |
|---|---|
| Busca | Procura o aparelho por marca e/ou modelo, com filtro por tipo. Os resultados vêm separados por tipo (geladeiras, ar-condicionado...) em seções que abrem ao tocar |
| Uso | Pergunta horas por dia, lavagens por mês ou velocidade, só quando precisa |
| Distribuidora | Estado + distribuidora, ou a tarifa da conta de luz. Oferece repetir a última escolhida |
| Resultado | Gasto por mês e por ano, como foi calculado e os avisos |
| Minha casa | Soma os aparelhos (com quantidade), mostra o que mais pesa e o perfil da casa |
| Modelos mais econômicos | Lista modelos equivalentes que gastam menos |
| Vale a pena trocar? | Compara os dois modelos e calcula o payback com o preço digitado |
| Eco-Coach | Plano de economia escrito por IA com dicas oficiais (Inmetro e Cemig) para os aparelhos que mais pesam, com as fontes citadas. Os números são calculados pelo iamp |

O botão de casa no topo de todas as telas abre "Minha casa" e mostra quantos aparelhos já foram adicionados.
A lista fica só na memória: ao fechar o app, ela recomeça vazia.

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

---

## 9. Como o cálculo funciona

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

## 10. Sugestão de troca e payback

O iamp só compara modelos que fazem o mesmo serviço, com o **mesmo uso** e a **mesma tarifa** do aparelho do usuário:

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

---

## 13. Fontes dos dados

| Dado | Fonte |
|---|---|
| Consumo dos aparelhos | Inmetro, Programa Brasileiro de Etiquetagem (PBE) |
| Tarifas de energia | ANEEL, tarifas homologadas das distribuidoras |

---

## 14. O que já foi feito

- Dados do Inmetro e da ANEEL baixados e limpos com Pandas
- Banco PostgreSQL no Docker com as tabelas do projeto
- Cálculo de consumo e custo para 12 tipos de aparelho
- App de terminal funcionando de ponta a ponta
- API FastAPI no Docker, subindo junto com o banco (`docker compose up -d`)
- Machine Learning: residências sintéticas (CTGAN) e perfil de consumo (K-Means)
- App Flutter ligado à API: cálculo, "Minha casa", perfil da casa, sugestão de troca e payback
- Diagrama BPMN em `docs/`

## 15. Próximas etapas

- Análise exploratória com gráficos (Matplotlib/Seaborn)
- Assistente com IA generativa "Eco-Coach" (RAG com LangChain)
- Terraform
- Documentação de ética e governança
