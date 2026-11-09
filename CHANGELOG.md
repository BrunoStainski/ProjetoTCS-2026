# Histórico de versões

App = `version` em `app_gerenciamento_energetico/pubspec.yaml`. API = `version` em `src/main.py`.
Regra: correção = 1.0.**1**, funcionalidade nova = 1.**1**.0, mudança grande = **2**.0.0.
O número depois do `+` (build) sobe 1 a cada APK, senão o Android não aceita como atualização.

## App 1.1.2+4 / API 0.2.0

- Só documentação (README e CLAUDE.md); app e API sem mudanças, o APK 1.1.1 continua valendo.
- README: passo opcional para subir tudo com Terraform (cuidados no Windows), seção "Instalar no
  celular" (enviar o APK, atualizar por cima, rede e IP, redes que bloqueiam aparelhos, iPhone) e
  listas "O que já foi feito" e "Próximas etapas" atualizadas.
- CLAUDE.md: Terraform testado, roteiro de cada versão, chave do projeto, celular e iOS.

## App 1.1.1+3 / API 0.2.0

- Busca: trocar o tipo de aparelho atualiza a lista na hora (antes era preciso tocar na lupa de novo).
  Só vale a resposta da última troca, então trocar rápido não mostra a lista errada.
- API sem mudanças.

## App 1.1.0+2 / API 0.2.0

- Busca: os resultados vêm separados por tipo de aparelho (geladeiras, ar-condicionado...) em seções
  que abrem ao tocar, com a quantidade de modelos. Antes, uma marca com vários tipos só mostrava o
  primeiro em ordem alfabética (ex.: "brastemp" trazia só máquinas de lavar).
- API: em `GET /aparelhos`, o `limite` passou a valer por tipo de aparelho e cada item traz
  `total_categoria`. Compatível com o app 1.0.0 (o campo novo é ignorado).
- Aviso "foi para a sua casa" some sozinho em 5 s (antes ficava na tela até alguém tocar).
- APK assinado com a chave do projeto quando existe `android/key.properties`.

## App 1.0.0+1 / API 0.1.0

- Cálculo de consumo e custo por aparelho (Inmetro + ANEEL), Minha casa com perfil K-Means,
  sugestões de modelos mais econômicos com payback e Eco-Coach (RAG + Gemini).
