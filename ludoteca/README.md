# Ludoteca

App Android para mapear sua coleção de jogos de tabuleiro. Substitui a planilha:
para quantos jogadores cada jogo serve, quantas vezes você jogou, quando foi a
última vez, quanto cada um custou (caixa, sleeves, acessórios) e o que isso dá
por mês, por partida e por hora de mesa.

Também: lista de desejos com alerta de preço, registro de partidas com placar e
vencedor, o mês em círculos para mandar no WhatsApp, e o que fazer quando um jogo
sai da coleção (vendido, trocado ou doado).

Os dados ficam **só no celular**, num banco SQLite dentro do app. Não existe
conta nem servidor: a sincronização com o Comparajogos usa só o seu nome de
usuário público, e o app nunca guarda senha de ninguém.

---

## Ambiente

Já está instalado nesta máquina, fora do projeto:

| O quê | Onde | Versão |
|---|---|---|
| Flutter SDK | `C:\src\flutter` | 3.44.8 stable · Dart 3.12.2 |
| Android SDK | `C:\Android\sdk` | platform 36, build-tools 36.0.0, platform-tools 37 |
| JDK | Temurin em `C:\jdk` | 17 — ver "armadilhas" abaixo |

O Flutter **não está no PATH**. Ou você usa o caminho completo
(`C:\src\flutter\bin\flutter.bat`), ou adiciona `C:\src\flutter\bin` ao PATH do
Windows para poder digitar só `flutter`.

O Android SDK foi instalado pelo `android` CLI novo (`C:\Android\sdk\cmdline-tools\latest\bin\android.exe`),
não pelo `sdkmanager` — o `sdkmanager` está deprecado e, mais prático que isso,
o `android` CLI aceita as licenças sozinho, enquanto o `sdkmanager --licenses`
exige responder "y" num prompt interativo.

## Comandos do dia a dia

```powershell
$env:ANDROID_HOME='C:\Android\sdk'
cd "h:\planilha board game\ludoteca"

C:\src\flutter\bin\flutter.bat analyze          # análise estática
C:\src\flutter\bin\flutter.bat test             # 272 testes
C:\src\flutter\bin\flutter.bat run              # roda no celular com hot reload
C:\src\flutter\bin\flutter.bat build apk --release
```

O APK sai em `build\app\outputs\flutter-apk\app-release.apk`.

Para instalar num celular ligado por USB:

```powershell
C:\Android\sdk\platform-tools\adb.exe install -r build\app\outputs\flutter-apk\app-release.apk
```

Para um APK menor, um por arquitetura (o celular usa só o `arm64-v8a`):

```powershell
C:\src\flutter\bin\flutter.bat build apk --release --split-per-abi
```

### Quatro armadilhas já resolvidas, que não devem voltar

**JDK 17, não o 20.** O Java 20 da Oracle que já estava na máquina faz o Kotlin
compilar para bytecode JVM 20 enquanto o Java compila para 17, e o Gradle aborta
com *"Inconsistent JVM-target compatibility"*. Ignorar essa validação seria pior
que resolvê-la: bytecode versão 64 pode quebrar depois, no dexing. Por isso há um
Temurin 17 em `C:\jdk`, apontado pelo `flutter config --jdk-dir`.

**Projeto no H:, cache do pub no C:.** O compilador incremental do Kotlin chama
`File.relativeTo` entre o fonte do plugin (no `C:`) e o projeto (no `H:`) e
estoura com *"this and base files have different roots"* — drives diferentes não
têm caminho relativo no Windows. `kotlin.incremental=false` em
`android/gradle.properties` resolve. Se um dia o projeto for para o `C:`, essa
linha pode sair.

**Não trave plugin Android em versão antiga.** Detalhado em "Dependências",
abaixo. Em uma linha: plugin velho compila contra SDK velho, e isso só aparece no
fim de um build de vários minutos.

**Permissão de internet.** O `flutter create` declara `INTERNET` apenas nos
manifestos de `debug` e `profile`. Sem a linha no manifesto principal, o APK de
release sai sem rede e a busca no catálogo falha calada — só na versão instalada no
celular, que é justamente onde ninguém olha o log. A linha está em
`android/app/src/main/AndroidManifest.xml`; se você regerar a pasta `android/`,
recoloque.

**`flutter create` sobrescreve arquivos.** Se precisar rodar de novo, faça backup
de `pubspec.yaml` e confira o manifesto e os ícones depois. Ele também recria
`test/widget_test.dart`, um teste de template que referencia `MyApp` (esta app
chama `LudotecaApp`) e por isso quebra o `flutter test` — apague-o.

---

## Dependências

```yaml
sqflite: ^2.3.3          # banco local
path: ^1.9.0
path_provider: ^2.1.4
http: ^1.2.2             # Comparajogos (GraphQL) e BGG (XML)
xml: ^6.5.0              # a API do BGG responde XML
collection: ^1.18.0
cached_network_image: ^3.4.1   # capas em cache, funciona offline
provider: ^6.1.2
share_plus: ^12.0.2      # backup e compartilhar coleção / imagem do mês
file_picker: ^11.0.0     # escolher o arquivo de backup na restauração
```

**Não trave `share_plus` e `file_picker` numa versão antiga.** A tentação é fixar
a versão exata porque as APIs mudam entre versões menores — e foi o que este
arquivo recomendava por um tempo. O problema é pior do outro lado: plugin velho
compila contra SDK velho, e o `file_picker` 8.1.2 puxa uma dependência transitiva
que exige `compileSdk` 36. Quebra de API o `flutter analyze` acha em 10 segundos;
incompatibilidade de compileSdk só aparece no fim de um build de vários minutos.

`share_plus` fica no 12 e não no 13 porque o `file_picker` 11 conflita com o 13
numa dependência transitiva em comum. Os dois são versões atuais.

Se algum dos dois der problema de build no Android, o app funciona inteiro sem
eles — só o backup e o compartilhamento param de existir.

Não há dependência de biblioteca de gráficos: a rosca é um `CustomPainter`, as
barras são widgets comuns e o empacotamento dos círculos do mês é feito à mão, em
`lib/widgets/`.

---

## Como o app está organizado

```
lib/
  main.dart                    entrada, temas claro/escuro
  theme.dart                   paleta de dados (VizColors) + tema Material
  models/
    game.dart                  Game + GameEntry, Ownership, Disposal, LinkKind
    play.dart                  Play (uma partida)
    play_score.dart            PlayScore (jogador, pontos, venceu)
  data/
    database.dart              schema SQLite e migrações (v7)
    game_repository.dart       todo o SQL vive aqui
  services/
    game_catalog.dart          interface de catálogo, neutra de fonte
    comparajogos_service.dart  Comparajogos (GraphQL) — catálogo principal
    bgg_service.dart           XML API2 do BoardGameGeek — opcional, com token
    wishlist_service.dart      sincronizar listas e conferir preço-alvo
    tag_backfill_service.dart  puxar tema/mecânica do catálogo em lote
    backup_service.dart        exportar/restaurar JSON
    share_service.dart         texto da coleção, do mês, e captura em PNG
  state/
    collection_store.dart      estado, filtros, ordenação
  stats/
    cost_stats.dart            as métricas de custo (funções puras)
  screens/
    home_shell.dart            navegação em abas
    collection_screen.dart     lista, busca, filtros, compartilhar
    game_detail_screen.dart    ficha, custos, histórico com placar
    add_game_screen.dart       busca no catálogo
    game_form_screen.dart      cadastro e edição
    wishlist_screen.dart       lista de desejos e alerta de preço
    costs_screen.dart          gráficos, separados por tópico
    settings_screen.dart       backup, token do BGG, usuário do Comparajogos
  widgets/
    donut_chart.dart           pizza em rosca (CustomPainter)
    month_bar_chart.dart       barras de gasto mensal
    ranked_bar_list.dart       rankings em barra horizontal
    play_bubbles.dart          o mês em círculos, e a imagem para compartilhar
    play_calendar.dart         frequência de partidas ao longo do tempo
    stat_tile.dart             números de cabeceira
    expansion_picker_sheet.dart  checklist de expansões
    tag_filter_sheet.dart      filtro por tema e mecânica
    pick_game_sheet.dart       escolher o jogo ao registrar uma partida
    log_play_sheet.dart        registrar partida (3 modos de duração + placar)
    score_editor.dart          jogadores, pontos e vencedor
    disposal_sheet.dart        vendido, trocado ou doado
    game_card.dart, game_cover.dart, chart_card.dart

test/
  cost_stats_test.dart           matemática dos custos e das horas
  database_migration_test.dart   abre bancos antigos e roda o onUpgrade
  disposal_scores_test.dart      saída da coleção, troca e placar
  comparajogos_service_test.dart cliente GraphQL com http falso
  bgg_service_test.dart          cliente do BGG com http falso (401, 202, XML)
  tags_test.dart                 tema e mecânica
  share_service_test.dart        o texto que vai para o WhatsApp
  screens_test.dart              telas renderizam contra um banco de verdade
  widgets_smoke_test.dart        gráficos renderizam nos dois temas
```

272 testes, todos passando. Os de gráfico não checam aparência — checam que
renderizam sem exceção de painter, sem overflow de layout e com a extensão de
tema presente, nos temas claro e escuro. Os de rede usam `MockClient`. Os de
banco usam `sqflite_common_ffi`, que roda SQLite de verdade no desktop.

Duas armadilhas de teste que custaram tempo:

- **`tester.runAsync` é obrigatório para I/O real dentro de `testWidgets`.** A
  zona de tempo falso nunca completa um future de `dart:io`, e o teste trava para
  sempre — sem erro, sem timeout, sem pista.
- **Tela que carrega no `initState` precisa do `pumpWidget` dentro do
  `runAsync`.** Senão a consulta nasce na zona falsa e a tela fica "carregando"
  para o resto do teste.

### As quatro métricas de custo

| Métrica | Como é calculada | Onde aparece |
|---|---|---|
| **Custo por partida** | (caixa + sleeves + acessórios + expansões) ÷ partidas | ranking em barras, e na ficha de cada jogo |
| **Custo por hora** | investimento ÷ horas de mesa | ranking em barras, e na ficha |
| **Custo de posse por mês** | total investido ÷ meses desde a compra (piso de 1 mês) | **pizza** "quem puxa o custo por mês", ranking em barras, e na ficha |
| **Gasto por mês** | soma das compras agrupada pelo mês da data de compra | barras roláveis, mês a mês |
| **Composição do gasto** | fatia de cada jogo no total investido, e caixa × sleeves × acessórios | duas **pizzas** |

São três pizzas na aba Custos: onde está o dinheiro (por jogo), quem puxa o custo
mensal (por jogo), e em que você gastou (caixa × sleeves × acessórios).

Cada pizza mostra no máximo **6 fatias** — as maiores, com a cauda dobrada em
"Outros N". Não é economia de espaço: passando de seis, fatias vizinhas deixam de
se distinguir, e sob daltonismo bem antes disso. A soma das fatias continua
fechando com o total, então nada de dinheiro desaparece no "Outros" — há teste
para isso. A legenda de cada pizza traz valor e percentual de toda fatia, então
ela também serve de tabela e nenhum número depende de você acertar o toque no
arco.

O custo por partida e o custo mensal por jogo aparecem como **barras, não pizza**,
de propósito: aqueles dois são um ranking (quem é o maior), e comparar
comprimentos lado a lado é preciso, enquanto comparar ângulos de fatia não é. A
pizza fica onde ela é boa: parte sobre o total.

Duas decisões que valem saber, porque senão os cartões parecem se contradizer:

- **Investimento e composição olham só o que está na estante hoje.** Jogo vendido
  sai da conta e o que você recebeu por ele aparece como "recuperado em vendas".
- **A linha do tempo de gastos inclui jogos já vendidos**, porque o dinheiro saiu
  do bolso naquele mês, independente do que aconteceu depois.

Cada cartão declara a sua base no subtítulo.

### Horas jogadas e custo por hora

Você **não precisa cronometrar nada**. Cada partida guarda uma duração opcional
(`plays.duration_minutes`); quando ela é nula — o caso normal — o cálculo usa a
**duração média do jogo**, que é o meio da faixa que o BGG informa (um jogo de
60–120 min conta 90 min por partida).

Ao registrar uma partida há três caminhos, e o primeiro já vem selecionado:

| Modo | O que faz |
|---|---|
| **Média** | não pergunta nada; a partida conta pela média do jogo |
| **Minutos** | você digita quanto durou, com atalhos na faixa do próprio jogo |
| **Início e fim** | você marca as duas horas e o app calcula (inclusive se a partida virou a meia-noite) |

Só a duração final é gravada, não o par início/fim — aquele é um jeito de chegar
no número, então editar a partida depois mostra os minutos.

**Número estimado nunca é exibido como se fosse medido.** Quando qualquer parte
das horas vem da média, o valor aparece com `≈` na frente, e a ficha explica a
composição ("3 cronometradas + 5 pela média de 1h30"). Um jogo sem duração
cadastrada e sem nenhuma partida cronometrada mostra `—`, não zero: não saber e
não ter jogado são coisas diferentes.

O custo por hora existe porque o custo por partida engana quando as durações são
muito diferentes. Dois jogos de R$ 200 com 10 partidas cada empatam em R$ 20 por
partida; se um é um filler de 20 minutos e o outro uma campanha de 4 horas, o
custo por hora separa R$ 60/h de R$ 5/h. Há teste para exatamente esse caso.

### Expansões e séries agrupadas

Um item agrupado é um registro normal com `link_kind` (`expansao` ou `serie`) e
`parent_id` apontando para o jogo-base. O custo dele entra no total do jogo-base,
e o cálculo tem o cuidado de **não contá-lo duas vezes** (nele mesmo e dentro do
pai) — existe teste para isso. Item sem pai vinculado entra por conta própria,
para o dinheiro não desaparecer do total.

`serie` existe por causa de Unmatched: cada caixa é um jogo completo, mas você
quer uma linha só na estante. A diferença para `expansao` é semântica; para o
dinheiro as duas se comportam igual.

Isso já foi um bug de dinheiro: o código perguntava "é expansão?" onde queria
saber "está agrupado?", e uma caixa de série era **contada duas vezes**. Por isso
`Game` expõe `isGrouped` e não só `isExpansion`, e há teste de regressão.

### Um botão para adicionar expansão depois

Expansão quase nunca chega junto com o jogo. Na ficha há um botão que busca no
catálogo os itens ligados àquele jogo e deixa você marcar quais tem. Sem isso, a
única forma de vincular seria cadastrar o item novo e apontar o pai à mão.

Serve também para agrupar séries como Unmatched, em que cada caixa é um jogo
completo mas você quer uma linha só na estante.

### Importar a planilha antiga

`..\ferramentas\planilha-para-backup.ps1` lê o `.xlsx` e gera um arquivo no
**formato de backup do próprio app**. A importação então reusa o caminho de
restauração que já existe em Ajustes, em vez de exigir código novo de importação
no app.

```powershell
& "h:\planilha board game\ferramentas\planilha-para-backup.ps1"
```

Sai `ludoteca-backup-da-planilha.json` com 56 jogos da coleção e 26 vendidos.
Passe para o celular e use **Ajustes → Restaurar de um arquivo**. Atenção:
restaurar **substitui** a coleção do app, então faça isso antes de cadastrar
qualquer coisa à mão.

O que a planilha tem e vira o quê:

| Planilha (Plan1) | No app |
|---|---|
| nome | nome |
| mín/máx jogadores | mín/máx jogadores |
| última vez jogado | histórico anterior → última vez |
| estilo (Party/Evento/Meio termo) | anotações, buscáveis |
| ranking temático | anotações |
| dias sem jogar | descartado — o app recalcula |

A aba Plan2 (jogos vendidos) entra como jogos marcados vendidos, com valor de
compra e de venda. A aba `marvel` é a lista de heróis e vilões de Marvel
Champions, não são jogos, e é ignorada.

**O que a planilha não tem:** preço dos jogos que você ainda tem, contagem de
partidas, e duração dos jogos. Sem duração não há horas nem custo por hora; sem
preço os gráficos de custo ficam vazios. Esses campos você preenche no app, e o
jeito rápido de trazer duração e capa de uma vez é editar o jogo depois de
cadastrá-lo pela busca do BGG.

Duas armadilhas que apareceram escrevendo esse script, e que o teste contra os
totais da planilha pegou:

- **`[double]::TryParse` sem cultura invariante.** O xlsx grava número com ponto
  decimal (`94.5`), mas em pt-BR o ponto é separador de milhar — `94.5` virava
  `945`. O erro é silencioso: só apareceu somando os vendidos e comparando com
  o total que a planilha já calculava (R$ 3.087).
- **PowerShell 5.1 lê `.ps1` sem BOM como ANSI.** Os acentos do script viravam
  mojibake nas anotações geradas. O arquivo está salvo com BOM UTF-8 por isso.

### O histórico que veio da planilha

Cada jogo tem `manual_play_count` e `manual_last_played`: o número de partidas que
você já tinha anotado antes de usar o app. As partidas registradas somam em cima
disso, e a ficha mostra as duas coisas separadas — o app não finge que aquelas
partidas antigas têm data.

---

## Três estados de posse

Um jogo na base pode ser **seu**, **jogado sem ter** ou **desejado**. É um campo
só (`ownership`), e não três tabelas, porque as três coisas são o mesmo jogo em
momentos diferentes da sua relação com ele — e mover entre os estados não pode
perder o histórico de partidas.

O que isso resolve, na prática:

- Você joga o jogo de um amigo e quer que as horas contem. Ele entra como *só
  joguei*: aparece nas partidas e nas horas, mas **o preço dele não entra no seu
  investimento**, porque você não gastou esse dinheiro.
- Um jogo desejado vira seu no dia da compra sem perder o preço que você vinha
  acompanhando.

Quem sai da coleção é caso à parte (`disposal`), abaixo.

## Quando um jogo sai da coleção

Vendido, trocado ou doado. O jogo **não é apagado**: as partidas e as horas
continuam contando na sua história. O que muda é a conta do dinheiro, e cada
saída mexe nela de um jeito diferente:

| Saída | O que acontece com o dinheiro |
|---|---|
| **Vendido** | o valor recebido abate; o jogo sai do investimento atual e entra em "recuperado em vendas" |
| **Trocado** | o investido inteiro (caixa + sleeves + acessórios) **passa para o jogo que entrou** |
| **Doado** | nada volta; o que você gastou continua contado como gasto |

A transferência na troca existe porque o jogo novo foi pago com o que você já
tinha. Sem ela, ele nasceria com custo zero e um custo por partida irreal —
e o total da coleção cairia sozinho, como se dinheiro tivesse evaporado. Desfazer
a troca devolve o valor de onde veio; há teste para os dois sentidos.

Apagar de vez continua existindo, mas o diálogo oferece marcar a saída primeiro.

## Placar das partidas

Ao registrar uma partida dá para anotar quem jogou, quantos pontos fez e quem
venceu. Tudo opcional: muito jogo não tem placar, e exigir os campos travaria o
lançamento rápido, que é o caso comum.

Duas decisões que parecem detalhe e não são:

- **A coroa de vencedor não é exclusiva.** Em cooperativo, todo mundo ganhou.
- **"Quem fez mais pontos venceu" é um botão, não algo automático.** Existe jogo
  de menor pontuação e existe cooperativo; quem sabe qual é o caso é você.

Os nomes já usados viram sugestões de um toque — você joga quase sempre com as
mesmas pessoas, e redigitar no teclado do celular toda vez é o tipo de atrito que
faz parar de anotar.

## O mês em círculos

Cada jogo do mês vira um círculo com a capa dentro, e o tamanho é quantas vezes
foi à mesa. O raio cresce com a **raiz** da contagem, porque o que o olho compara
num círculo é a área — raio proporcional faria 4 partidas parecerem 16.

O empacotamento é uma espiral simples: o maior no centro, e cada seguinte procura
o primeiro lugar livre em anéis crescentes. Não é o empacotamento ótimo (esse é um
problema difícil e o ganho visual não pagaria), mas é determinístico — a mesma
coleção desenha igual toda vez, sem os círculos "pulando" a cada rebuild.

O botão de compartilhar manda a **imagem**, não a lista de nomes: captura o quadro
em PNG e abre a folha do Android. Na imagem saem só o mês, o ano e os círculos —
setas de navegação, contagem de partidas e a legenda com os nomes ficam de fora,
senão a imagem vira o mesmo texto que ela veio substituir.

## Compartilhar a coleção

O botão manda **exatamente a lista que está na tela**, com o filtro aplicado. Se
você filtrou por 5 jogadores para decidir o que jogar hoje, é essa lista que
chega do outro lado.

Quando há filtro ligado, o texto leva uma linha dizendo qual era. Sem isso, uma
lista filtrada chega parecendo a coleção inteira, e quem recebe conclui que você
tem cinco jogos.

---

## Os catálogos

O app fala com dois catálogos por uma interface só (`GameCatalog`), e o
Comparajogos é o principal. O BGG virou opcional depois que fechou a API.

### Comparajogos (GraphQL)

Preços do mercado brasileiro, nomes em português e as suas listas públicas
(coleção, desejos, alerta de preço, troca). A sincronização pede **só o nome de
usuário** — a API não tem login, então não há senha para o app guardar.

**O teto de 15 linhas.** O papel anônimo do Hasura deles ignora o `limit` e
devolve no máximo 15 itens por consulta, sem avisar. Uma lista de 40 jogos vinha
pela metade com mensagem de sucesso — o pior tipo de bug, porque parece que
funcionou. O cliente pagina por `offset` em blocos de 15; há teste, e foi
validado contra uma conta real de 40 jogos.

A sincronização **nunca apaga** nada e **nunca rebaixa** um jogo que você já tem
para "desejado": a fonte da verdade sobre a sua estante é o seu celular.

### BoardGameGeek — exige token, e o cadastro passa por análise

Desde o fim de outubro de 2025 a XML API **não é mais aberta**. Sem credencial,
todo endpoint responde `401` com `WWW-Authenticate: Bearer realm="xml api"` —
enquanto a home do site continua abrindo normalmente, o que faz o sintoma parecer
problema de internet quando não é.

Para obter o token: <https://boardgamegeek.com/using_the_xml_api>, logado na conta
do BGG, em *Apply to use the XML API*. **O formulário termina em "Submit for
evaluation": um humano do BGG revisa e aprova.** O identificador (um UUID) que
aparece logo após enviar **não funciona antes da aprovação** — é isso, e não erro
de formato, que causa 401 com um token aparentemente válido em mãos.

O token vai em **Ajustes → Token do BGG**, com um botão *Salvar e testar* que faz
uma busca real por "Catan" e diz na hora se funcionou. Testar de verdade em vez de
só validar o formato é deliberado: um token com formato certo mas revogado
passaria numa validação de formato e falharia depois, na hora de cadastrar um
jogo.

Onde ele fica: tabela `settings` do próprio SQLite, não num plugin de
preferências — uma dependência nativa a menos no build. E **fora do arquivo de
backup de propósito**, porque o backup é feito para sair do aparelho (Drive,
e-mail, WhatsApp) e credencial não viaja nisso. Pelo mesmo motivo, restaurar um
backup não apaga o token.

### Três comportamentos dela tratados em `bgg_service.dart`

São as causas mais comuns de integração quebrada:

1. **HTTP 202 com corpo vazio** quando ela enfileira o pedido. Não é erro — é
   "pergunte de novo em instantes", e o cliente reconsulta com espera
   progressiva.
2. **429** se você acelerar. A busca tem `debounce` de 550 ms, e chamadas de
   detalhe são agrupadas (vários ids num `/thing` só) em vez de uma por jogo.
3. **401 e 403 falham na hora, sem repetir.** Isto foi um bug: eu tratava 401
   como erro temporário, então uma falta de token virava cinco tentativas com
   espera antes de um erro genérico — o usuário olhava um spinner por quinze
   segundos. Falta de credencial não melhora tentando de novo. Há teste
   garantindo que é uma requisição só.

Nome, capa, número de jogadores, duração e peso são gravados no banco no momento
do cadastro, então a coleção abre offline. Só cadastrar jogo novo precisa de rede.

O nome vem em inglês (é o campo `primary` do BGG). O campo *Nome em português* é
seu, editável, e tem prioridade na exibição.

### Expansões ao cadastrar um jogo

O `/thing` traz as expansões do jogo como `<link type="boardgameexpansion">`.
Depois de salvar um jogo-base que tenha expansões conhecidas, o app abre uma lista
com checkbox e **nada entra sem marcação explícita**. Não é excesso de zelo:
Marvel Champions tem dezenas de pacotes, e adicionar todos encheria a estante do
que você não tem e sujaria os custos, porque cada expansão soma no investimento do
jogo-base.

As marcadas entram com preço zero, para você preencher depois, e são buscadas em
lotes de 20 ids por requisição.

Uma pegadinha do formato: na ficha de uma **expansão**, o BGG lista o jogo-base
também como `boardgameexpansion`, mas com `inbound="true"`. Sem filtrar esse
atributo, abrir uma expansão ofereceria o jogo-base como "expansão dela". Há
teste.
