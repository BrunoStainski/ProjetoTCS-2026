---
name: boas-praticas-flutter
description: Boas práticas do app Flutter do iamp (app_gerenciamento_energetico): identidade visual em tema.dart, padrões de tela em telas/comum.dart, chamadas à API só em api.dart, estado em casa.dart e testes de widget. Use ao criar ou alterar telas, widgets ou integração com a API.
---

# Boas práticas do app Flutter do iamp

O app em `app_gerenciamento_energetico/lib/` é a interface do usuário. Ele não calcula nada: mostra o que a API devolve, com os avisos. Ao mexer no app, siga estas regras e os padrões já existentes nas telas.

## Organização

- `api.dart`: modelos (`Appliance`, `Resultado`...) e todas as chamadas HTTP. Nenhuma tela chama `http` direto. Erros de rede viram `ApiError` com mensagem em português.
- `casa.dart`: estado da casa (`Home` com `ChangeNotifier`, instância global `casa`), `Query`, `TariffChoice`. Só em memória, sem persistência (limitação conhecida).
- `tema.dart`: `AppColors` e `Palette` (escuro e claro), `Spacing`, a extensão `Iamp` (estilos de texto, cores com significado, raios, ícones, alvo de toque) e `iampTheme(light:)`. Nas telas: `final t = Iamp.de(context);`. **Não** use cor, tamanho de fonte ou espaçamento solto, nem `AppColors.*` direto (são as cores do modo escuro).
- `telas/comum.dart`: `AppPage` (com `footer` para a ação principal), `QuestionHeader`, `OptionCard`, `HighlightCard`, `InfoCard`, `NoticeList`, `SectionTitle`, `PartBar`, `SideBySide`, `ErrorMessage`, `Loading`, `TimeField`/`TimeControl`, `notifyAdded`. Reutilize antes de criar widget novo.
- Uma tela por arquivo em `telas/` (nome do arquivo em português e snake_case, como já está); classes, métodos e
  variáveis em inglês, PascalCase na classe (`SearchScreen`). Textos da tela continuam com `tr('pt', 'en')`.
- Só o pacote `http` além do Flutter (e o `flutter_localizations`, que vem com o SDK); não acrescente dependências sem necessidade clara (ex.: o markdown do Eco-Coach é renderizado por `texto_plano.dart`, sem pacote).
- `idioma.dart`: idioma do app (português nativo, inglês pelo menu). Ver "Idioma" abaixo.

## Identidade visual e acessibilidade

Público: quem paga as contas de casa, incluindo pessoas mais velhas ou com pouca familiaridade com tecnologia.

- Fundo preto, amarelo `#FFD000` na ação e no valor principal, verde só para economia, vermelho só para alerta. Texto branco em 100/90/80% (nada abaixo de 80%, para o contraste AA no preto).
- Modo claro (`lightMode`, menu "Aparência"): o amarelo não tem contraste no branco, então fica só em preenchimento (`t.highlightFill` + `t.onFill`) e o destaque (`t.highlight`) vira âmbar `#7A5A00`. Preenchimento amarelo = `highlightFill`; ícone ou texto de destaque = `highlight`.
- Texto: estilos da extensão `Iamp` (34/22/18/16, base 18, nada abaixo de 16), valores com dígitos tabulares (`t.number`). Grade de 4/8 (`Spacing`).
- Respeite a fonte do sistema: com 150% ou mais (`largeFont`) o que ficaria lado a lado empilha (`SideBySide`). Nenhuma informação só por cor (payback tem a frase "Se paga rápido/Demora/Não se paga"); cartões clicáveis com `MergeSemantics`; botões de ícone com tooltip.
- Uma decisão por tela; R$ como informação principal (kWh e fórmula como detalhe); ação principal fixa no rodapé (zona do polegar); toque mínimo de 48dp; valor principal em `HighlightCard`.

## Integração com a API

- Endereço em `apiUrl` (`--dart-define=API_URL=...`; emulador Android usa `10.0.2.2`). Nunca fixe IP no código.
- O app pega ids pela busca a cada uso: os ids mudam quando o banco é recriado.
- Respeite `GET /aparelhos/{id}/uso` (`horas`, `ciclos`, `velocidade`, `opcional`); em branco nas horas opcionais (TV, ar) vale o valor do Inmetro.
- Mostre sempre `metodo` e `avisos` da resposta; o app nunca esconde que um valor é estimativa.
- Campo novo da API deve ser opcional no `fromJson` (o app antigo precisa continuar funcionando e o novo precisa aceitar API antiga quando possível).
- Timeout geral de 75 s (`requestLimit`: o servidor grátis do Render pode estar dormindo) e de 120 s no `/eco-coach`; o plano fica em `casa.plan` até a casa mudar (poupa o limite gratuito do Gemini).

## Idioma (português e inglês)

- Todo texto que aparece na tela (título, botão, aviso, tooltip, rótulo do leitor de tela, mensagem de erro) é escrito com as duas versões no lugar: `tr('Gasto por mês', 'Cost per month')`. Nada de texto solto: um teste de widget do grupo "Idioma" troca o app inteiro para o inglês.
- O app sempre abre em português; a troca é no menu (`changeLanguage`), que redesenha todas as telas. Por isso, texto não pode ser calculado só uma vez e guardado (`const` com texto, campo `final` montado no construtor, mapa `static const`): use getter ou função que chame `tr()` no `build`.
- Valores: `reais`, `number` e `readNumber` já seguem o idioma. Hint de exemplo também: `tr('Ex.: 0,85', 'E.g.: 0.85')`.
- Texto que vem da API já chega no idioma (o app manda `Accept-Language`). Chaves da API (categoria, perfil, velocidade) não mudam: traduza o nome na tela (`categoryName`, `profileName`, `speedName`).
- Nomes de idiomas sempre na própria língua ("Português", "English"); nomes próprios (Inmetro, ANEEL, estados, marcas) não se traduzem.

## Armadilhas conhecidas

- Nunca `setState(() => _f = futuro())` com arrow que devolve `Future`: guarde o future antes e chame `setState` em bloco.
- SnackBar que navega usa o `NavigatorState` guardado antes, não o `context` da tela. Avisos somem em 5 s (`noticeDuration`) com `persist: false`.
- Busca: só a resposta mais recente vale (`_request`); acima de 30 por tipo, pedir parte do modelo.
- Teste de widget com API falsa: `http.runWithClient` + `MockClient`.
- `tester.pageBack()` procura o tooltip "Back": dentro do `IampApp` em português a seta é "Voltar" (`find.byTooltip('Voltar')`). Em `MaterialApp` sem `locale` (teste de uma tela só) continua "Back".

## Qualidade

- `flutter analyze` sem avisos e `flutter test` verde antes de abrir PR; teste novo em `test/widget_test.dart` para tela ou regra de formatação nova.
- Texto da interface em português do Brasil, simples, para uma família comum, com a versão em inglês no `tr()`; unidades sempre visíveis (kWh/mês, R$/mês).
- Versão em `pubspec.yaml` e `CHANGELOG.md` a cada APK (ver skill `estrutura-projeto-iamp`).
