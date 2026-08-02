# Converte "Planilha de custo de jogos(atualizada).xlsx" num arquivo de backup
# da Ludoteca, para restaurar direto no app (Ajustes -> Restaurar de um arquivo).
#
# Assim a importação não precisa de código novo no app: ela reusa o mesmo
# caminho de restauração que já existe e já é testado.
#
# O que a planilha tem e o que não tem:
#   Plan1  -> nome, estilo, mín/máx jogadores, última vez jogado
#   Plan2  -> jogos vendidos, com valor de compra e de venda
#   marvel -> heróis/vilões de Marvel Champions (não são jogos; ignorado)
#
# A planilha NÃO tem preço dos jogos que você ainda tem, nem contagem de
# partidas. Esses campos saem vazios e você preenche no app — os gráficos de
# custo só ganham conteúdo depois disso.

param(
    [string]$Xlsx = 'h:\planilha board game\Planilha de custo de jogos(atualizada).xlsx',
    [string]$Saida = 'h:\planilha board game\ludoteca-backup-da-planilha.json',
    # Importar também os 26 jogos já vendidos. Eles não aparecem na coleção por
    # padrão (há um filtro "Vendidos"), mas preservam o histórico de gastos.
    [bool]$IncluirVendidos = $true
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

# ---------------------------------------------------------------- leitura xlsx

$tmp = Join-Path $env:TEMP ('xlsx-' + [guid]::NewGuid().ToString('N'))
[System.IO.Compression.ZipFile]::ExtractToDirectory($Xlsx, $tmp)

try {
    $ss = Get-Content (Join-Path $tmp 'xl\sharedStrings.xml') -Raw -Encoding UTF8
    $strings = [regex]::Matches($ss, '(?s)<si>(.*?)</si>') | ForEach-Object {
        (([regex]::Matches($_.Groups[1].Value, '(?s)<t[^>]*>(.*?)</t>') |
            ForEach-Object { $_.Groups[1].Value }) -join '')
    }

    function Convert-Entity([string]$s) {
        if ($null -eq $s) { return $null }
        $s -replace '&amp;', '&' -replace '&lt;', '<' -replace '&gt;', '>' `
            -replace '&quot;', '"' -replace '&#39;', "'"
    }

    # Devolve uma tabela: linha -> @{ coluna = valor }
    function Read-Sheet([string]$nome) {
        $xml = Get-Content (Join-Path $tmp "xl\worksheets\$nome.xml") -Raw -Encoding UTF8
        $linhas = @{}

        foreach ($rowM in [regex]::Matches($xml, '(?s)<row[^>]*r="(\d+)"[^>]*>(.*?)</row>')) {
            $r = [int]$rowM.Groups[1].Value
            $cels = @{}

            foreach ($cM in [regex]::Matches($rowM.Groups[2].Value, '(?s)<c ([^>]*?)/?>(?:(.*?)</c>)?')) {
                $attrs = $cM.Groups[1].Value
                if (-not ($attrs -match 'r="([A-Z]+)\d+"')) { continue }
                $col = $matches[1]

                $tipo = ''
                if ($attrs -match 't="([^"]+)"') { $tipo = $matches[1] }

                $valor = $null
                $corpo = $cM.Groups[2].Value
                if ($corpo -match '(?s)<v>(.*?)</v>') { $valor = $matches[1] }
                elseif ($corpo -match '(?s)<t[^>]*>(.*?)</t>') { $valor = $matches[1] }
                if ($null -eq $valor -or $valor -eq '') { continue }

                if ($tipo -eq 's') {
                    $i = [int]$valor
                    $valor = if ($i -lt $strings.Count) { $strings[$i] } else { $null }
                }
                $cels[$col] = Convert-Entity $valor
            }

            if ($cels.Count -gt 0) { $linhas[$r] = $cels }
        }
        return $linhas
    }

    $plan1 = Read-Sheet 'sheet1'
    $plan2 = Read-Sheet 'sheet2'
}
finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# ------------------------------------------------------------------ conversão

# Converte número do XML do xlsx.
#
# OBRIGATÓRIO usar InvariantCulture: o xlsx sempre grava número com ponto
# decimal ("94.5"), mas o [double]::TryParse sem cultura usa a do sistema — em
# pt-BR o ponto é separador de MILHAR, e "94.5" virava 945. O erro é silencioso
# e só aparece conferindo os totais contra a planilha.
$script:Invariante = [System.Globalization.CultureInfo]::InvariantCulture
$script:EstiloNum = [System.Globalization.NumberStyles]::Float

function ConvertTo-Num($v) {
    if ($null -eq $v) { return $null }
    $n = 0.0
    if ([double]::TryParse([string]$v, $script:EstiloNum, $script:Invariante, [ref]$n)) {
        return $n
    }
    return $null
}

# Serial do Excel -> data ISO. Base 1899-12-30 (o Excel trata 1900 como
# bissexto, e essa base já compensa o erro).
function ConvertTo-IsoDate($serial) {
    $n = ConvertTo-Num $serial
    if ($null -eq $n) { return $null }
    if ($n -lt 1 -or $n -gt 60000) { return $null }
    ([datetime]'1899-12-30').AddDays([math]::Floor($n)).ToString('yyyy-MM-dd')
}

function ConvertTo-Int($v) {
    $n = ConvertTo-Num $v
    if ($null -eq $n) { return $null }
    return [int]$n
}

$hoje = (Get-Date).ToString('yyyy-MM-dd')
$jogos = New-Object System.Collections.Generic.List[object]
$id = 0
$semJogadores = New-Object System.Collections.Generic.List[string]

# --- Plan1: a coleção atual -------------------------------------------------
# Colunas: B=classificação temática, D=nome, E=estilo, F=mín, G=máx,
#          H=dias sem jogar (calculado, ignorado), I=última vez jogado
foreach ($r in ($plan1.Keys | Sort-Object)) {
    if ($r -eq 1) { continue }  # cabeçalho
    $c = $plan1[$r]

    $nome = $c['D']
    if ([string]::IsNullOrWhiteSpace($nome)) { continue }
    # Linhas de cabeçalho repetido ou rótulo solto.
    if ($nome -in @('Jogos', 'Estilo de jogo', 'ok')) { continue }

    $id++
    $min = ConvertTo-Int $c['F']
    $max = ConvertTo-Int $c['G']
    if ($null -eq $min -and $null -eq $max) { $semJogadores.Add($nome) }

    # O estilo e a classificação temática são categorias suas, sem campo
    # próprio no app — vão para as anotações, onde continuam buscáveis.
    $notas = @()
    if ($c['E']) { $notas += "Estilo: $($c['E'])" }
    if ($c['B']) { $notas += "Ranking temático da planilha: $($c['B'])" }

    $jogos.Add([ordered]@{
        id                 = $id
        bgg_id             = $null
        name               = $nome.Trim()
        name_pt            = $null
        year               = $null
        min_players        = $min
        max_players        = $max
        best_players       = $null
        min_playtime       = $null
        max_playtime       = $null
        weight             = $null
        image_url          = $null
        thumb_url          = $null
        parent_id          = $null
        is_expansion       = if ($nome -match '(?i)expans') { 1 } else { 0 }
        price              = 0
        sleeve_cost        = 0
        accessory_cost     = 0
        purchase_date      = $null
        manual_play_count  = 0
        manual_last_played = ConvertTo-IsoDate $c['I']
        sold               = 0
        sold_price         = $null
        sold_date          = $null
        notes              = if ($notas.Count) { $notas -join ' · ' } else { $null }
        created_at         = $hoje
    })
}

$totalAtuais = $id

# --- Plan2: os vendidos ------------------------------------------------------
# Colunas: B=nome, C=valor de compra, D=valor de venda, E=lucro (calculado)
$totalVendidos = 0
if ($IncluirVendidos) {
    foreach ($r in ($plan2.Keys | Sort-Object)) {
        if ($r -le 2) { continue }  # cabeçalho e linha em branco
        $c = $plan2[$r]

        $nome = $c['B']
        if ([string]::IsNullOrWhiteSpace($nome)) { continue }
        if ($nome -in @('Jogos vendidos', 'Venda', 'Compra', 'Valor total')) { continue }

        $compra = ConvertTo-Num $c['C']
        $venda = ConvertTo-Num $c['D']
        # Sem valor de compra nem de venda não há informação a preservar.
        if ($null -eq $compra -and $null -eq $venda) { continue }

        $id++
        $totalVendidos++

        $jogos.Add([ordered]@{
            id                 = $id
            bgg_id             = $null
            name               = $nome.Trim()
            name_pt            = $null
            year               = $null
            min_players        = $null
            max_players        = $null
            best_players       = $null
            min_playtime       = $null
            max_playtime       = $null
            weight             = $null
            image_url          = $null
            thumb_url          = $null
            parent_id          = $null
            is_expansion       = if ($nome -match '(?i)expans') { 1 } else { 0 }
            price              = if ($null -ne $compra) { $compra } else { 0 }
            sleeve_cost        = 0
            accessory_cost     = 0
            purchase_date      = $null
            manual_play_count  = 0
            manual_last_played = $null
            sold               = 1
            # Venda sem valor registrado (deu 0 na planilha) fica como 0 mesmo:
            # é diferente de "não sei por quanto vendi".
            sold_price         = if ($null -ne $venda) { $venda } else { 0 }
            sold_date          = $null
            notes              = 'Importado da aba "Jogos vendidos" da planilha.'
            created_at         = $hoje
        })
    }
}

# ------------------------------------------------------------------- gravação

$backup = [ordered]@{
    schema       = 1
    exportado_em = (Get-Date).ToString('o')
    jogos        = $jogos.ToArray()
    partidas     = @()
}

$backup | ConvertTo-Json -Depth 6 | Set-Content $Saida -Encoding UTF8

# --------------------------------------------------------------------- relato

Write-Output ''
Write-Output "Arquivo gerado: $Saida"
Write-Output ''
Write-Output "  jogos da colecao atual : $totalAtuais"
Write-Output "  jogos vendidos         : $totalVendidos"
Write-Output "  total de registros     : $($jogos.Count)"
Write-Output ''
Write-Output 'NAO veio da planilha (a planilha nao tem esses dados):'
Write-Output '  - preco dos jogos que voce ainda tem'
Write-Output '  - contagem de partidas'
Write-Output '  - duracao dos jogos  -> sem ela nao ha horas nem custo por hora'
Write-Output '  - capas              -> os jogos aparecem com as iniciais'
Write-Output ''
if ($semJogadores.Count) {
    Write-Output "Sem numero de jogadores na planilha ($($semJogadores.Count)):"
    $semJogadores | ForEach-Object { Write-Output "  - $_" }
}
