# Iamp: app Flutter

App do Iamp, o copiloto de eficiência energética residencial do bootcamp TCS 2026. Ele mostra quanto cada
aparelho custa por mês, soma os aparelhos da casa, sugere modelos que gastam menos e monta um plano de
economia (Eco-Coach). O app não calcula nada: mostra o que a API devolve, com os avisos.

A documentação completa do projeto está no [README da raiz](../README.md) (seção 8 para o app).

## Rodar

Com a API no ar (`docker compose up -d --build` na raiz do projeto):

```bash
flutter pub get
flutter run -d chrome                                         # API em http://localhost:8000
flutter run -d chrome --dart-define=API_URL=http://<endereco>  # outra API (Terraform na 8080, Render...)
```

No emulador Android o endereço padrão já é `http://10.0.2.2:8000`. Rodar como programa do Windows
(`-d windows`) exige o Visual Studio com "Desenvolvimento para desktop com C++".

## Checar

```bash
flutter analyze
flutter test
```

Os testes de widget (`test/widget_test.dart`) usam uma API falsa e cobrem o fluxo completo, as abas, a
estimativa, o Eco-Coach, o modo claro, o idioma inglês, o contraste, o tamanho de toque e a fonte em 2x.

## Organização (`lib/`)

| Arquivo | O que faz |
|---|---|
| `main.dart` | Abre o app (boas-vindas por cima das abas) e acorda a API |
| `api.dart` | Modelos e todas as chamadas HTTP |
| `casa.dart` | Estado da casa ("Minha casa", trocas avaliadas, plano do Eco-Coach), só em memória |
| `conta.dart` | Cadastro opcional (nome e e-mail), só em memória, nunca enviado à API |
| `idioma.dart` | Português e inglês (`tr('pt', 'en')`) |
| `tema.dart` | Cores (escuro e claro), estilos de texto, espaçamentos e transições |
| `navegacao.dart` | Barra inferior com 3 abas: Calcular, Minha casa e Economizar |
| `telas/` | Uma tela por arquivo; widgets comuns em `telas/comum.dart` |

## Gerar o APK

```bash
flutter build apk --release --split-per-abi --dart-define=API_URL=<endereco-da-api>
```

Versão em `pubspec.yaml`, histórico no [CHANGELOG](../CHANGELOG.md) e o passo a passo de assinatura e
publicação no README da raiz.
