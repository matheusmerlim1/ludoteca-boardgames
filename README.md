# Ludoteca

App Android para a sua coleção de jogos de tabuleiro — o que substituiu uma
planilha de Excel que já não dava conta.

Ele responde às perguntas que a estante não responde: **para quantos jogadores
esse jogo serve**, **quantas vezes eu joguei**, **há quanto tempo não joga**, e —
a que motivou o projeto — **quanto cada jogo custou de verdade**, por partida,
por hora de mesa e por mês de posse.

Feito em Flutter, com **SQLite no próprio aparelho**. Não existe conta, não
existe servidor, e nada é enviado para lugar nenhum sem você mandar.

> Projeto pessoal, escrito para um uso real. Não está publicado em loja: o jeito
> de usar é compilar o APK (instruções em [Como rodar](#como-rodar)).

---

## O que ele faz

**Coleção.** Lista com busca branda (acha "Caçadores da Galáxia" digitando
"galaxia cacadores"), filtro por número de jogadores, por tema e mecânica, por
nunca jogados, e treze ordenações agrupadas por pergunta — "o que dá para jogar
em 40 minutos?", "qual está há mais tempo parado?", "qual saiu mais caro por
partida?".

**Partidas.** Registrar leva dois toques a partir da tela inicial. Dá para anotar
o placar — quem jogou, quantos pontos fez, quem venceu — e dá para registrar
partida de um jogo que **não é seu**, para as horas contarem.

**Custos.** Quatro métricas, três pizzas e rankings em barra, separados por
tópico para você não rolar a tela inteira atrás de um número. Detalhe em
[As métricas de custo](#as-métricas-de-custo).

**O mês em círculos.** Cada jogo do mês vira um círculo com a capa dentro, do
tamanho de quantas vezes foi à mesa — e sai como imagem pronta para mandar no
WhatsApp.

**Lista de desejos.** Com preço-alvo: o app consulta o Comparajogos e avisa
quando o jogo chegou no valor que você queria.

**Quando um jogo sai.** Vendido, trocado ou doado — cada um mexe no dinheiro de
um jeito, e nenhum deles apaga o seu histórico de partidas.

**Backup.** Exporta e restaura um JSON. Sem credencial dentro, de propósito.

---

## Privacidade

Vale ser explícito, porque é uma decisão de projeto e não um detalhe:

- **Os dados ficam no aparelho**, num SQLite dentro do app.
- **Não há login em lugar nenhum.** A sincronização com o Comparajogos usa só o
  seu nome de usuário público — a API deles não tem autenticação, então não há
  senha para o app guardar.
- **O token do BGG, se você tiver um, fica fora do backup.** O backup existe para
  sair do aparelho (Drive, e-mail, WhatsApp), e credencial não viaja nisso. Pelo
  mesmo motivo, restaurar um backup não apaga o token que já está lá.
- **Nada é enviado sem ação sua.** As únicas chamadas de rede são busca no
  catálogo, sincronização de lista e download de capa.

---

## Decisões que valem explicar

O resto deste arquivo é o *porquê* das escolhas — o tipo de coisa que, sem
registro, alguém desfaz em seis meses achando que era descuido.

### Três estados de posse

Um jogo pode ser **seu**, **jogado sem ter** ou **desejado**. É um campo só
(`ownership`), e não três tabelas, porque as três coisas são o mesmo jogo em
momentos diferentes da sua relação com ele — e mover entre os estados não pode
perder o histórico de partidas.

O que isso resolve na prática:

- Você joga o jogo de um amigo e quer que as horas contem. Ele entra como *só
  joguei*: aparece nas partidas e nas horas, mas **o preço dele não entra no seu
  investimento**, porque você não gastou esse dinheiro.
- Um jogo desejado vira seu no dia da compra sem perder o preço que você vinha
  acompanhando.

### Quando um jogo sai da coleção

Vendido, trocado ou doado. O jogo **não é apagado**: as partidas e as horas
continuam contando na sua história. O que muda é a conta do dinheiro, e cada
saída mexe nela de um jeito diferente:

| Saída | O que acontece com o dinheiro |
|---|---|
| **Vendido** | o valor recebido abate; o jogo sai do investimento atual e entra em "recuperado em vendas" |
| **Trocado** | o investido inteiro (caixa + sleeves + acessórios) **passa para o jogo que entrou** |
| **Doado** | nada volta; o que você gastou continua contado como gasto |

A transferência na troca existe porque o jogo novo foi pago com o que você já
tinha. Sem ela, ele nasceria com custo zero e um custo por partida irreal — e o
total da coleção cairia sozinho, como se dinheiro tivesse evaporado. Desfazer a
troca devolve o valor de onde veio; há teste para os dois sentidos.

Apagar de vez continua existindo, mas o diálogo oferece marcar a saída primeiro.

### As métricas de custo

| Métrica | Como é calculada | Onde aparece |
|---|---|---|
| **Custo por partida** | (caixa + sleeves + acessórios + expansões) ÷ partidas | ranking em barras, e na ficha de cada jogo |
| **Custo por hora** | investimento ÷ horas de mesa | ranking em barras, e na ficha |
| **Custo de posse por mês** | total investido ÷ meses desde a compra (piso de 1 mês) | pizza "quem puxa o custo por mês", ranking, e na ficha |
| **Gasto por mês** | soma das compras agrupada pelo mês da data de compra | barras roláveis, mês a mês |
| **Composição do gasto** | fatia de cada jogo no total, e caixa × sleeves × acessórios | duas pizzas |

São três pizzas na aba Custos: onde está o dinheiro (por jogo), quem puxa o custo
mensal (por jogo), e em que você gastou (caixa × sleeves × acessórios).

Cada pizza mostra no máximo **6 fatias** — as maiores, com a cauda dobrada em
"Outros N". Não é economia de espaço: passando de seis, fatias vizinhas deixam de
se distinguir, e sob daltonismo bem antes disso. A soma das fatias continua
fechando com o total, então nada de dinheiro desaparece no "Outros" — há teste
para isso. A legenda traz valor e percentual de toda fatia, então ela também
serve de tabela e nenhum número depende de você acertar o toque no arco.

O custo por partida e o custo mensal por jogo aparecem como **barras, não pizza**,
de propósito: aqueles dois são um ranking (quem é o maior), e comparar
comprimentos lado a lado é preciso, enquanto comparar ângulos de fatia não é. A
pizza fica onde ela é boa: parte sobre o total.

Duas decisões que valem saber, porque senão os cartões parecem se contradizer:

- **Investimento e composição olham só o que está na estante hoje.** Jogo que saiu
  fica de fora, e o que você recebeu por ele aparece como "recuperado em vendas".
- **A linha do tempo de gastos inclui jogos já vendidos**, porque o dinheiro saiu
  do bolso naquele mês, independente do que aconteceu depois.

Cada cartão declara a sua base no subtítulo.

### Horas de mesa sem cronômetro

Você **não precisa cronometrar nada**. Cada partida guarda uma duração opcional;
quando ela é nula — o caso normal — o cálculo usa a **duração média do jogo**, o
meio da faixa que o catálogo informa (um jogo de 60–120 min conta 90 min).

Ao registrar há três caminhos, e o primeiro já vem selecionado:

| Modo | O que faz |
|---|---|
| **Média** | não pergunta nada; a partida conta pela média do jogo |
| **Minutos** | você digita quanto durou, com atalhos na faixa do próprio jogo |
| **Início e fim** | você marca as duas horas e o app calcula (inclusive se virou a meia-noite) |

Só a duração final é gravada, não o par início/fim — aquele é um jeito de chegar
no número, então editar a partida depois mostra os minutos.

**Número estimado nunca é exibido como se fosse medido.** Quando qualquer parte
das horas vem da média, o valor aparece com `≈` na frente, e a ficha explica a
composição ("3 cronometradas + 5 pela média de 1h30"). Um jogo sem duração
cadastrada e sem partida cronometrada mostra `—`, não zero: não saber e não ter
jogado são coisas diferentes.

O custo por hora existe porque o custo por partida engana quando as durações são
muito diferentes. Dois jogos de R$ 200 com 10 partidas cada empatam em R$ 20 por
partida; se um é um filler de 20 minutos e o outro uma campanha de 4 horas, o
custo por hora separa R$ 60/h de R$ 5/h. Há teste para exatamente esse caso.

### Placar das partidas

Quem jogou, quantos pontos fez e quem venceu — tudo opcional. Muito jogo não tem
placar, e exigir os campos travaria o lançamento rápido, que é o caso comum.

Duas decisões que parecem detalhe e não são:

- **A coroa de vencedor não é exclusiva.** Em cooperativo, todo mundo ganhou.
- **"Quem fez mais pontos venceu" é um botão, não algo automático.** Existe jogo
  de menor pontuação e existe cooperativo; quem sabe qual é o caso é você.

Os nomes já usados viram sugestões de um toque — você joga quase sempre com as
mesmas pessoas, e redigitar no teclado do celular toda vez é o tipo de atrito que
faz parar de anotar.

### O mês em círculos

O raio cresce com a **raiz** da contagem de partidas, porque o que o olho compara
num círculo é a área — raio proporcional faria 4 partidas parecerem 16.

O empacotamento é uma espiral simples: o maior no centro, e cada seguinte procura
o primeiro lugar livre em anéis crescentes. Não é o empacotamento ótimo (esse é um
problema difícil e o ganho visual não pagaria), mas é determinístico — a mesma
coleção desenha igual toda vez, sem os círculos "pulando" a cada rebuild.

Compartilhar manda a **imagem**, não a lista de nomes: captura o quadro em PNG e
abre a folha do Android. Na imagem saem só o mês, o ano e os círculos — setas de
navegação, contagem de partidas e a legenda com os nomes ficam de fora, senão a
imagem vira o mesmo texto que ela veio substituir.

### Compartilhar a coleção

O botão manda **exatamente a lista que está na tela**, com o filtro aplicado. Se
você filtrou por 5 jogadores para decidir o que jogar hoje, é essa lista que chega
do outro lado.

Quando há filtro ligado, o texto leva uma linha dizendo qual era. Sem isso, uma
lista filtrada chega parecendo a coleção inteira, e quem recebe conclui que você
tem cinco jogos.

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

Expansão quase nunca chega junto com o jogo, então a ficha tem um botão que busca
no catálogo os itens ligados àquele jogo e deixa você marcar quais tem. **Nada
entra sem marcação explícita**: Marvel Champions tem dezenas de pacotes, e
adicionar todos encheria a estante do que você não tem e sujaria os custos.

---

## Os catálogos

O app fala com dois catálogos por uma interface só (`GameCatalog`). O Comparajogos
é o principal; o BGG virou opcional depois que fechou a API.

### Comparajogos (GraphQL)

Preços do mercado brasileiro, nomes em português e as suas listas públicas
(coleção, desejos, alerta de preço, troca).

**O teto de 15 linhas.** O papel anônimo do Hasura deles ignora o `limit` e
devolve no máximo 15 itens por consulta, **sem avisar**. Uma lista de 40 jogos
vinha pela metade com mensagem de sucesso — o pior tipo de bug, porque parece que
funcionou. O cliente pagina por `offset` em blocos de 15; há teste, e foi validado
contra uma conta real de 40 jogos.

A sincronização **nunca apaga** nada e **nunca rebaixa** para "desejado" um jogo
que você já tem: a fonte da verdade sobre a sua estante é o seu celular.

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
só validar o formato é deliberado: um token com formato certo mas revogado passa
numa validação de formato e falha depois, na hora de cadastrar um jogo.

Ele fica na tabela `settings` do próprio SQLite, não num plugin de preferências —
uma dependência nativa a menos no build.

### Três comportamentos tratados em `bgg_service.dart`

São as causas mais comuns de integração quebrada:

1. **HTTP 202 com corpo vazio** quando a API enfileira o pedido. Não é erro — é
   "pergunte de novo em instantes", e o cliente reconsulta com espera progressiva.
2. **429** se você acelerar. A busca tem `debounce` de 550 ms, e chamadas de
   detalhe são agrupadas (vários ids num `/thing` só) em vez de uma por jogo.
3. **401 e 403 falham na hora, sem repetir.** Isto foi um bug: eu tratava 401 como
   erro temporário, então uma falta de token virava cinco tentativas com espera
   antes de um erro genérico — o usuário olhava um spinner por quinze segundos.
   Falta de credencial não melhora tentando de novo. Há teste garantindo que é uma
   requisição só.

Uma pegadinha do formato: na ficha de uma **expansão**, o BGG lista o jogo-base
também como `boardgameexpansion`, mas com `inbound="true"`. Sem filtrar esse
atributo, abrir uma expansão ofereceria o jogo-base como "expansão dela". Há teste.

Nome, capa, número de jogadores, duração e peso são gravados no banco no momento
do cadastro, então a coleção abre offline. Só cadastrar jogo novo precisa de rede.

---

## Como rodar

Precisa de Flutter 3.44+ (Dart 3.12+), Android SDK 36 e **JDK 17**.

```bash
cd ludoteca
flutter pub get
flutter test            # 272 testes
flutter analyze
flutter run             # com o celular ligado por USB
flutter build apk --release
```

O APK sai em `build/app/outputs/flutter-apk/app-release.apk`. Para um menor, um
por arquitetura (celular moderno usa `arm64-v8a`):

```bash
flutter build apk --release --split-per-abi
```

<details>
<summary>Caminhos desta máquina (Windows, sem Flutter no PATH)</summary>

```powershell
$env:ANDROID_HOME='C:\Android\sdk'
cd "h:\planilha board game\ludoteca"

C:\src\flutter\bin\flutter.bat analyze
C:\src\flutter\bin\flutter.bat test
C:\src\flutter\bin\flutter.bat build apk --release

C:\Android\sdk\platform-tools\adb.exe install -r build\app\outputs\flutter-apk\app-release.apk
```

O Android SDK foi instalado pelo `android` CLI novo
(`cmdline-tools\latest\bin\android.exe`), não pelo `sdkmanager` — o `sdkmanager`
está deprecado e, mais prático que isso, o `android` CLI aceita as licenças
sozinho, enquanto o `sdkmanager --licenses` exige responder "y" num prompt
interativo.

Em MIUI, `adb install` falha com `INSTALL_FAILED_USER_RESTRICTED` se a tela
estiver apagada. Com ela acesa funciona; o caminho mais confiável é empurrar para
`/data/local/tmp/` e usar `pm install -r` de lá.

</details>

### Armadilhas de build já resolvidas

**JDK 17, não o 20.** O Java 20 faz o Kotlin compilar para bytecode JVM 20
enquanto o Java compila para 17, e o Gradle aborta com *"Inconsistent JVM-target
compatibility"*. Ignorar essa validação seria pior que resolvê-la: bytecode versão
64 pode quebrar depois, no dexing. Aponte o JDK certo com
`flutter config --jdk-dir`.

**Projeto e cache do pub em drives diferentes (Windows).** O compilador incremental
do Kotlin chama `File.relativeTo` entre o fonte do plugin e o projeto e estoura com
*"this and base files have different roots"* — drives diferentes não têm caminho
relativo no Windows. `kotlin.incremental=false` em `android/gradle.properties`
resolve; se um dia os dois ficarem no mesmo drive, essa linha pode sair.

**Permissão de internet.** O `flutter create` declara `INTERNET` apenas nos
manifestos de `debug` e `profile`. Sem a linha no manifesto principal, o APK de
release sai sem rede e a busca no catálogo falha calada — só na versão instalada
no celular, que é justamente onde ninguém olha o log. A linha está em
`android/app/src/main/AndroidManifest.xml`; se regerar a pasta `android/`,
recoloque.

**`flutter create` sobrescreve arquivos.** Se precisar rodar de novo, faça backup
do `pubspec.yaml` e confira o manifesto e os ícones depois. Ele também recria
`test/widget_test.dart`, um teste de template que referencia `MyApp` (esta app
chama `LudotecaApp`) e por isso quebra o `flutter test` — apague-o.

---

## Dependências

```yaml
sqflite: ^2.3.3                # banco local
path: ^1.9.0
path_provider: ^2.1.4
http: ^1.2.2                   # Comparajogos (GraphQL) e BGG (XML)
xml: ^6.5.0                    # a API do BGG responde XML
collection: ^1.18.0
cached_network_image: ^3.4.1   # capas em cache, funciona offline
provider: ^6.1.2
share_plus: ^12.0.2            # backup, compartilhar coleção e imagem do mês
file_picker: ^11.0.0           # escolher o arquivo de backup na restauração
```

**Não trave `share_plus` e `file_picker` numa versão antiga.** A tentação é fixar
a versão exata porque as APIs mudam entre versões menores — e foi o que este
arquivo recomendava por um tempo. O problema é pior do outro lado: plugin velho
compila contra SDK velho, e o `file_picker` 8.1.2 puxa uma dependência transitiva
que exige `compileSdk` 36. Quebra de API o `flutter analyze` acha em 10 segundos;
incompatibilidade de compileSdk só aparece no fim de um build de vários minutos.

`share_plus` fica no 12 e não no 13 porque o `file_picker` 11 conflita com o 13
numa dependência transitiva em comum. Os dois são versões atuais.

Se algum dos dois der problema de build, o app funciona inteiro sem eles — só o
backup e o compartilhamento param de existir.

**Não há dependência de biblioteca de gráficos.** A rosca é um `CustomPainter`, as
barras são widgets comuns e o empacotamento dos círculos é feito à mão, em
`lib/widgets/`.

---

## Como o código está organizado

O app é a pasta `ludoteca/`; `ferramentas/` tem só o script de importação da
planilha.

```
ludoteca/lib/
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
```

Nenhuma tela fala SQL: tudo passa por `game_repository.dart`. As métricas de custo
são funções puras em `cost_stats.dart`, testadas sem banco e sem widget.

O banco tem migrações versionadas (`onUpgrade`) e está na **v7**. Elas importam
mais do que parece: quem já tem o app instalado tem dados no aparelho, e uma
versão nova abre o banco *antigo* dele. Se o `onUpgrade` falhar, o app quebra ao
abrir e a coleção fica inacessível — o pior bug possível aqui, porque atinge
exatamente quem já usava. Por isso há um arquivo de teste só para isso, que cria
bancos em versões antigas com dados dentro e reabre pelo código de produção.

---

## Testes

```
ludoteca/test/
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
renderizam sem exceção de painter, sem overflow de layout e com a extensão de tema
presente, nos dois temas. Os de rede usam `MockClient`. Os de banco usam
`sqflite_common_ffi`, que roda SQLite de verdade no desktop.

Duas armadilhas de teste que custaram tempo:

- **`tester.runAsync` é obrigatório para I/O real dentro de `testWidgets`.** A zona
  de tempo falso nunca completa um future de `dart:io`, e o teste trava para
  sempre — sem erro, sem timeout, sem pista.
- **Tela que carrega no `initState` precisa do `pumpWidget` dentro do `runAsync`.**
  Senão a consulta nasce na zona falsa e a tela fica "carregando" para o resto do
  teste.

---

## Importar uma planilha antiga

`ferramentas/planilha-para-backup.ps1` lê um `.xlsx` e gera um arquivo no **formato
de backup do próprio app**. A importação então reusa o caminho de restauração que
já existe em Ajustes, em vez de exigir código novo de importação no app.

```powershell
& ".\ferramentas\planilha-para-backup.ps1"
```

Passe o JSON para o celular e use **Ajustes → Restaurar de um arquivo**. Atenção:
restaurar **substitui** a coleção, então faça isso antes de cadastrar qualquer
coisa à mão.

O script é feito para uma planilha específica (a que deu origem ao projeto) e
serve mais de exemplo do que de ferramenta geral. O que ele mapeia:

| Planilha | No app |
|---|---|
| nome | nome |
| mín/máx jogadores | mín/máx jogadores |
| última vez jogado | histórico anterior → última vez |
| estilo (Party/Evento/Meio termo) | anotações, buscáveis |
| dias sem jogar | descartado — o app recalcula |

Cada jogo tem `manual_play_count` e `manual_last_played`: as partidas que você já
tinha anotado antes de usar o app. As partidas registradas somam em cima disso, e
a ficha mostra as duas coisas separadas — o app não finge que aquelas partidas
antigas têm data.

Duas armadilhas que apareceram escrevendo o script, e que o teste contra os totais
da planilha pegou:

- **`[double]::TryParse` sem cultura invariante.** O xlsx grava número com ponto
  decimal (`94.5`), mas em pt-BR o ponto é separador de milhar — `94.5` virava
  `945`. O erro é silencioso: só apareceu somando os vendidos e comparando com o
  total que a planilha já calculava.
- **PowerShell 5.1 lê `.ps1` sem BOM como ANSI.** Os acentos do script viravam
  mojibake nas anotações geradas. O arquivo está salvo com BOM UTF-8 por isso.
