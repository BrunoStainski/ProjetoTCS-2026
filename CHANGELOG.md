# Histórico de versões

App = `version` em `app_gerenciamento_energetico/pubspec.yaml`. API = `version` em `src/main.py`.
Regra: correção = 1.0.**1**, funcionalidade nova = 1.**1**.0, mudança grande = **2**.0.0.
O número depois do `+` (build) sobe 1 a cada APK, senão o Android não aceita como atualização.

## Próxima versão (ainda sem número)

- Tensão: modelo vendido numa tensão só também guarda a tensão e mostra no detalhe ("12 kg · 220 V"). Antes ele
  ficava como "vale para as duas" e a troca podia sugerir a quem tem 127 V uma máquina que só existe em 220 V.
- Casas salvas: com as versões 127 V e 220 V do mesmo modelo, o id salvo também é conferido pelo detalhe; antes,
  depois de recarregar o catálogo, o chuveiro de 220 V podia voltar como o de 127 V. A conferência agora só roda ao
  ler as casas (antes rodava também a cada gravação, com 1 a 2 consultas por item).
- Lista de marcas: as versões 127 V e 220 V do mesmo modelo contam como um modelo.
- Login: 5 senhas erradas em 15 minutos para o mesmo e-mail fazem esperar (429), contra chute de senha. Duas
  contas criadas ao mesmo tempo com o mesmo e-mail dão 409 (antes, erro 500).
- Testes novos: separação por tensão, sugestão só da mesma tensão, id da outra tensão e limite de senha errada.

## App 2.1.0+7 / API 0.6.0

- Tensão 127 V × 220 V: o catálogo guardava só a primeira versão de cada modelo e o chuveiro de 220 V sumia
  (ex.: Cardal Ducha 5 Luxo, 5500 W em 127 V e 7600 W em 220 V; ficava a de 127 V em 77 de 84 modelos). Agora,
  quando a versão de outra tensão gasta diferente, as duas aparecem, com a tensão no detalhe ("7600 W · 220 V"):
  55 chuveiros, 19 máquinas de lavar e 6 micro-ondas. As sugestões de troca só comparam modelos da mesma tensão.
  Catálogo: 24.148 -> 24.228 aparelhos (o banco recarrega sozinho no deploy e os ids mudam).
- Casas salvas: ao trazer uma casa da conta, o id de cada aparelho é conferido pelo nome (categoria, marca e
  modelo) e corrigido se o catálogo foi recarregado; sem isso, "Ver modelos que gastam menos" podia usar outro
  aparelho. Aparelho que saiu do catálogo volta com id 0 (sem sugestão de troca).

- Conta e várias casas na nuvem: a pessoa cria uma conta (nome, e-mail e senha, com o aceite do aviso de
  privacidade) ou entra, e as casas ficam salvas no servidor. Uma conta pode ter várias casas (ex.: a casa e a casa
  da praia), cada uma com os próprios aparelhos e moradores; dá para criar, trocar, renomear e apagar. Sem conta,
  o app funciona como antes. API 0.6.0: rotas `/contas`, `/login`, `/logout`, `/conta`, `/conta/dados` e `/casas`;
  tabelas `usuarios`, `sessoes`, `casas` e `itens_casa` (não são apagadas ao recarregar o catálogo).
- Eco-Coach mais curto, a pedido do professor: o plano tem no máximo ~120 palavras (1 frase de diagnóstico
  e 3 ações curtas) e as dicas por aparelho ~80 (1 frase e 3 dicas). Antes eram ~250 e ~180. Avisos e
  mensagem de espera também mais curtos.
- Documentação atualizada para a versão atual (README, documento do processo e PDF, CLAUDE.md, skills e o
  README do app, que ainda era o modelo padrão do Flutter).
- Correção: "Ver modelos que gastam menos" dava erro quando o tempo de uso era 0 h 0 min (ou 0 ciclos). Agora
  explica que, com esse uso, o aparelho não gasta energia.
- Correção: quando a API respondia com erro em texto (ou o servidor ainda estava acordando), o app mostrava
  "FormatException" ou não mostrava nada. Agora aparece "O Iamp está com um problema agora. Tente de novo em
  instantes."
- Correção: o Eco-Coach continuava recebendo trocas de aparelhos que já tinham saído da casa (removidos ou já
  trocados) e podia recomendar uma troca feita. Agora só entram as trocas de aparelhos que estão na casa.
- Correção: o modelo reserva do Gemini (`gemini-3.5-flash-lite`) recusava o pedido e nunca entrava quando o
  principal estava sobrecarregado. Agora ele é chamado de novo sem a opção que recusava.
- Correção de dados do ar-condicionado: 185 modelos tinham consumo cerca de 20 vezes menor que o real (o
  cadastro do Inmetro trazia, no campo do consumo anual, o kWh/mês de 1 hora por dia) e o app mostrava perto de
  R$ 1 por mês. A limpeza agora confere capacidade, potência e consumo entre si e refaz o que não combina
  (ex.: GREE GWH09QB-D3NNB4C, 9.000 BTU/h: de 1,4 para 52 kWh/mês). Os modelos corrigidos mostram o aviso de
  consumo completado na limpeza e não entram nas sugestões de troca.
- Correção de dados do ventilador de teto: 41 modelos com consumo impossível (até 65 kWh/mês para 1 hora por
  dia, um motor de 2.000 W) agora usam a potência do próprio ensaio do Inmetro ou ficam sem aquela velocidade.
  O catálogo passou de 24.155 para 24.148 aparelhos (7 cadastros sem nenhum número aproveitável saíram).

- Modo claro: no menu (☰), seção "Aparência" com "Escuro" e "Claro". O app abre no escuro (a identidade do
  Iamp) e a escolha não fica gravada. No claro, o amarelo fica só nos preenchimentos (botões, aba escolhida) e
  os detalhes usam um âmbar escuro, para manter o contraste AA no fundo branco.
- Transição entre as etapas: a tela nova entra deslizando da direita enquanto a anterior apaga, a barra
  "Etapa n de 6" avança animada e as perguntas da estimativa trocam do mesmo jeito. Com "remover animações"
  ligado no celular, as telas trocam direto.
- Cadastro (opcional) nas boas-vindas e no menu: nome e e-mail, com aviso de privacidade antes de preencher,
  correção e "Apagar meu cadastro". Os dados ficam só no aparelho (memória): não vão para a API nem para o
  banco. Quem se cadastra vê "Olá, <nome>!" nas boas-vindas.

- Código padronizado em inglês: nomes de classes, métodos, funções e variáveis (Python e Dart). Textos para o
  usuário, mensagens, comentários e nomes de arquivo continuam em português, e o contrato da API não muda: o
  JSON segue com as chaves em português (`JSON_NAMES` + `ApiModel` em main.py) e os parâmetros de URL também
  (`Query(alias="busca")`). Mesmos resultados: testes iguais e a limpeza dos dados gera arquivos idênticos.
- Pronto para a nuvem gratuita (Render + Neon): a busca do Eco-Coach usa os embeddings do Gemini
  (`gemini-embedding-001`, 768 dim) em vez do modelo local (~550 MB); a API caiu de ~750 MB para ~150 MB e
  a imagem de 1,2 GB para ~530 MB. Com o banco vazio, a API carrega sozinha o catálogo e a base do Eco-Coach.
  Porta pela variável `PORT`, endereço `postgresql://` do Neon aceito, `render.yaml` com a configuração.
- App: chama a API ao abrir (acorda o servidor que dorme no plano grátis), espera até 75 s (Eco-Coach 120 s)
  e, se o carregamento passar de 8 s, avisa que o servidor está acordando.

- Idioma: o app pode ficar todo em inglês, para apresentar a quem não fala português. No menu (☰), seção
  "Idioma · Language" com "Português" e "English" (cada um escrito na própria língua). O app sempre abre em
  português; a troca não fica gravada. Ao trocar, as abas voltam para a primeira tela (respostas antigas da API
  estavam no outro idioma) e a casa continua. Valores seguem em reais, no formato do idioma ("R$ 1,234.50").
  Os textos do próprio Flutter (voltar, copiar, colar) também seguem o idioma (`flutter_localizations`, do SDK):
  antes ficavam sempre em inglês, inclusive para o leitor de tela.
- API 0.5.0: com o cabeçalho `Accept-Language: en`, os textos das respostas (método, avisos, mensagens, nomes
  dos tipos, erros e o plano do Eco-Coach) vêm em inglês; sem ele, em português, como antes (o APK antigo
  continua igual). A resposta traz `Content-Language` e `Vary: Accept-Language`. Os números e as chaves
  (categoria, perfil, velocidade) não mudam.
- Ventiladores: o consumo mensal do Inmetro é de 1 hora por dia e o app não perguntava as horas (um ventilador
  ligado a noite toda saía 8 vezes menor). Agora pergunta a velocidade e as horas, no catálogo e na estimativa.
- Estimativa de eletro grande (antigo ou fora do catálogo) refeita: tipo com nome conhecido ("Automática que
  abre por cima", "Split de parede"...) e tamanho em opções prontas; depois "você consegue ver algum destes no
  aparelho?" (etiqueta do Inmetro ou a potência escrita na plaqueta, que vale para aparelho antigo); sem número,
  o gasto sai dos modelos parecidos do catálogo.
  Ar-condicionado e ventilador não pedem mais o kWh/mês da etiqueta (unidade e base mudaram entre etiquetas).
- "Gastar menos" de aparelho estimado pelos modelos parecidos não diz mais que ele "já está entre os mais
  econômicos" (era circular: o gasto dele é a mediana desses modelos); explica e pede o número da etiqueta.
  Textos dessa tela com acento e critério legível ("até 15% de diferença").
- Corrigido: o texto "Como calculamos" da estimativa mostrava o kWh/ciclo do primeiro modelo da lista e não o
  da mediana usada no cálculo (ex.: 0,27 × 15 com resultado 3,83 kWh). Agora o mesmo valor entra nos dois.
  Com menos de 4 modelos parecidos, a faixa é do menor ao maior. Acentos e textos da tela corrigidos; a origem
  da tarifa não mostra mais o nome do arquivo CSV.
- API: `GET /estimativa/categorias` troca `etiqueta_campo`, `etiqueta_rotulo` e `etiqueta_obrigatoria` por
  `formas`, `tamanhos`, `unidade_medida` e `valor_obrigatorio`, e `tipos` vira lista de `{valor, nome, descricao}`;
  `POST /calcular/estimado` ganha `campo_etiqueta`; `PerguntaDeUso` ganha `perguntar_horas`.

## App 2.0.0+6 / API 0.4.0

- App redesenhado para o cliente final (público geral, incluindo pessoas mais velhas), mantendo a
  paleta preto e amarelo: texto base 18 (nada abaixo de 16), contraste AA, toque mínimo de 48dp,
  respeita a fonte do sistema até 2x sem quebrar, leitor de tela (TalkBack/VoiceOver) com descrições.
- Navegação inferior com 3 abas: Calcular, Minha casa e Economizar.
- Tela de boas-vindas ao abrir o app: só a logo grande com o nome ao lado e o botão
  "Comece a economizar".
- Etapa 2 (marca e modelo): lista com todas as marcas do tipo escolhido (ex.: todas as de
  ar-condicionado), com a quantidade de modelos; tocar na marca abre os modelos dela. Digitar no campo
  filtra a lista, e "Buscar" continua procurando pela marca e pelo modelo digitados.
- API: `GET /marcas?categoria=` (marcas de um tipo, sem repetir maiúsculas: "Agratto" e "AGRATTO") e
  `GET /modelos?categoria=&marca=` (modelos de uma marca, até 50 por padrão).
- Menu de acesso rápido (☰) com a logo do app (contorno amarelo esmaecido) e o nome: Início, Calcular,
  Estimar, Minha casa e Economizar.
- Uma decisão por tela: tipo -> marca/modelo -> uso -> estado -> distribuidora -> resultado
  ("Etapa n de 6"); a estimativa fora do catálogo pergunta uma coisa por vez.
- Valores em R$ como informação principal; kWh e fórmula como secundários.
- Nome exibido "Iamp" (I maiúsculo) no app, na web, no Android e no iOS.
- Remover aparelho da casa tem "Desfazer".
- Removido o cálculo de gás de cozinha (app, API, banco, scripts, dados e testes): o projeto foca só em
  energia elétrica. **Mudança que quebra a API:** `GET /fogoes`, `GET /gas/precos` e
  `POST /calcular/gas` não existem mais.

## App 1.2.0+5 / API 0.3.0

- Gás de cozinha: fogões do Inmetro, preço do GLP por estado (ANP) e tela "Gás de cozinha" no app
  (`GET /fogoes`, `GET /gas/precos`, `POST /calcular/gas`).
- Estimar aparelho fora do catálogo: abas "Eletro pesado" (todas as categorias) e "Eletroportáteis"
  (liquidificador, cafeteira, chaleira, forno elétrico, aspirador, torradeira...), com horas e minutos.
  Geladeira antiga pela etiqueta ou pela regra do Inmetro de 2006; compra recente pelo Random Forest.
  (`POST /calcular/estimado`, `/calcular/refrigerador-antigo`, `/calcular/resistivo`,
  `/sugestoes/estimado`, `/comparar/estimado`, `/eco-coach/aparelho` e listas de apoio.)
- Geladeiras: consumos da metodologia antiga convertidos para a atual (a economia nas trocas era
  exagerada); volume errado refeito pela soma (ex.: Consul CRM44, 94 L -> 377 L).
- Eco-Coach: não recomenda etiqueta/Selo Procel para aparelho sem etiqueta; horário de ponta só na
  tarifa branca.
- Atalhos "Estimar aparelho" e "Gás de cozinha" na tela de busca.
- Banco: tabelas novas `portateis`, `fogoes` e `precos_glp` (a API recarrega sozinha se faltarem).

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
