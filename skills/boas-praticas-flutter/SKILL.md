---
name: boas-praticas-flutter
description: Boas práticas do app Flutter do iamp (app_gerenciamento_energetico): identidade visual em tema.dart, padrões de tela em telas/comum.dart, chamadas à API só em api.dart, estado em casa.dart e testes de widget. Use ao criar ou alterar telas, widgets ou integração com a API.
---

# Boas práticas do app Flutter do iamp

O app em `app_gerenciamento_energetico/lib/` é a interface do usuário. Ele não calcula nada: mostra o que a API devolve, com os avisos. Ao mexer no app, siga estas regras e os padrões já existentes nas telas.

## Organização

- `api.dart`: modelos (`Aparelho`, `Resultado`...) e todas as chamadas HTTP. Nenhuma tela chama `http` direto. Erros de rede viram `ApiErro` com mensagem em português.
- `casa.dart`: estado da casa (`Casa` com `ChangeNotifier`, instância global `casa`), `Consulta`, `EscolhaTarifa`. Só em memória, sem persistência (limitação conhecida).
- `tema.dart`: `Cores`, `Estilos`, `Espaco` e `temaIamp()`. **Não** use cor, tamanho de fonte ou espaçamento solto nas telas.
- `telas/comum.dart`: `Pagina` (com `rodape` para a ação principal), `CartaoDestaque`, `CartaoInfo`, `ListaAvisos`, `Titulo`, `MensagemErro`, `CampoTempo`/`ControleTempo`, `BotaoCasa`, `avisarAdicionado`. Reutilize antes de criar widget novo.
- Uma tela por arquivo em `telas/`, nomes em português e snake_case no arquivo, PascalCase na classe (`TelaBusca`).
- Só o pacote `http` além do Flutter; não acrescente dependências sem necessidade clara (ex.: o markdown do Eco-Coach é renderizado por `texto_plano.dart`, sem pacote).

## Identidade visual (regra 60/30/10)

- Fundo preto; amarelo `#FFD000` só na ação principal e no valor principal; branco para texto em três opacidades (100/80/60%).
- Detalhes nunca em branco: ícones, bordas (`Cores.borda`), divisórias (`Cores.divisoria`) e contornos são amarelos.
- Verde `#3DDC84` só para economia ou resultado bom; vermelho `#FF5C5C` só para alerta ou erro. Payback: verde até 60 meses, amarelo acima, vermelho se não se paga.
- Quatro tamanhos de texto (32/20/16/13) e dois pesos; valores com dígitos tabulares (`Estilos.valor`, `Estilos.numero`). Grade de 8 (`Espaco`).
- Ação principal fixa no rodapé (zona do polegar); toque mínimo de 48dp; valor principal em `CartaoDestaque`.

## Integração com a API

- Endereço em `apiUrl` (`--dart-define=API_URL=...`; emulador Android usa `10.0.2.2`). Nunca fixe IP no código.
- O app pega ids pela busca a cada uso: os ids mudam quando o banco é recriado.
- Respeite `GET /aparelhos/{id}/uso` (`horas`, `ciclos`, `velocidade`, `opcional`); em branco nas horas opcionais (TV, ar) vale o valor do Inmetro.
- Mostre sempre `metodo` e `avisos` da resposta; o app nunca esconde que um valor é estimativa.
- Campo novo da API deve ser opcional no `fromJson` (o app antigo precisa continuar funcionando e o novo precisa aceitar API antiga quando possível).
- Timeout do `/eco-coach`: 90 s; o plano fica em `casa.plano` até a casa mudar (poupa o limite gratuito do Gemini).

## Armadilhas conhecidas

- Nunca `setState(() => _f = futuro())` com arrow que devolve `Future`: guarde o future antes e chame `setState` em bloco.
- SnackBar que navega usa o `NavigatorState` guardado antes, não o `context` da tela. Avisos somem em 5 s (`duracaoAviso`) com `persist: false`.
- Busca: só a resposta mais recente vale (`_pedido`); acima de 30 por tipo, pedir parte do modelo.
- Teste de widget com API falsa: `http.runWithClient` + `MockClient`.

## Qualidade

- `flutter analyze` sem avisos e `flutter test` verde antes de abrir PR; teste novo em `test/widget_test.dart` para tela ou regra de formatação nova.
- Texto da interface em português do Brasil, simples, para uma família comum; unidades sempre visíveis (kWh/mês, R$/mês).
- Versão em `pubspec.yaml` e `CHANGELOG.md` a cada APK (ver skill `estrutura-projeto-iamp`).
