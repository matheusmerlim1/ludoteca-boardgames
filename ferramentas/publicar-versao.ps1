# Publica uma versão nova da Ludoteca na página de releases do GitHub.
#
# O app procura atualização nessa página toda vez que abre (UpdateService): se
# o release mais novo tiver versão maior que a instalada e um APK anexado, ele
# oferece baixar e instalar. Então publicar uma versão é:
#   1. subir o `version:` do ludoteca/pubspec.yaml (ex.: 1.1.0+2 -> 1.2.0+3);
#   2. commitar e dar push;
#   3. rodar este script.
#
# O APK precisa sair sempre assinado com a MESMA chave, senão o Android recusa
# a atualização por cima da versão instalada. Hoje o build de release usa a
# chave de debug desta máquina (~/.android/debug.keystore) — compile sempre
# aqui, ou copie esse arquivo para a outra máquina.

param(
    # Texto do "o que mudou" que aparece no aviso de atualização do app.
    [string]$Notas = ''
)

$ErrorActionPreference = 'Stop'
$app = Join-Path $PSScriptRoot '..\ludoteca'
$flutter = if (Get-Command flutter -ErrorAction SilentlyContinue) { 'flutter' } else { 'C:\src\flutter\bin\flutter.bat' }

$linha = Select-String -Path (Join-Path $app 'pubspec.yaml') -Pattern '^version:\s*(\S+)' | Select-Object -First 1
if (-not $linha) { throw 'Não achei a linha version: no pubspec.yaml' }
$versao = $linha.Matches[0].Groups[1].Value.Split('+')[0]
$tag = "v$versao"

gh release view $tag -R matheusmerlim1/ludoteca-boardgames *> $null
if ($LASTEXITCODE -eq 0) { throw "O release $tag já existe. Suba a versão no pubspec.yaml." }

# O Android Gradle recusa caminho com acento ("Informação"): compila por uma
# letra de unidade temporária apontando para a pasta do projeto.
$letra = 'L:'
subst $letra (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location "$letra\ludoteca"
try {
    & $flutter build apk --release
    if ($LASTEXITCODE -ne 0) { throw 'O build do APK falhou.' }
} finally { Pop-Location; subst $letra /D }

$apk = Join-Path $env:TEMP "ludoteca-$versao.apk"
Copy-Item (Join-Path $app 'build\app\outputs\flutter-apk\app-release.apk') $apk -Force

# Sem -Notas, o "o que mudou" sai dos títulos dos commits desde o último
# release: feat: vira Novidades, fix: vira Correções (o app mostra essas duas
# listas na caixa de atualização). Por isso o título do commit deve ser escrito
# para quem usa o app ler.
if (-not $Notas) {
    $raiz = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    git -C $raiz fetch --tags --quiet
    $anterior = gh release view -R matheusmerlim1/ludoteca-boardgames --json tagName -q .tagName 2>$null
    $faixa = if ($LASTEXITCODE -eq 0 -and $anterior) { "$anterior..HEAD" } else { 'HEAD' }
    $titulos = git -C $raiz log $faixa --no-merges --format=%s
    function Itens($tipo) {
        $titulos | Where-Object { $_ -match "^$tipo(\([^)]*\))?:\s*(.+)$" } | ForEach-Object {
            $t = ($_ -replace "^$tipo(\([^)]*\))?:\s*", '').Trim()
            '- ' + $t.Substring(0, 1).ToUpper() + $t.Substring(1)
        }
    }
    $partes = @()
    $nov = @(Itens 'feat'); if ($nov.Count) { $partes += "## Novidades`n" + ($nov -join "`n") }
    $cor = @(Itens 'fix');  if ($cor.Count) { $partes += "## Correções`n" + ($cor -join "`n") }
    $Notas = if ($partes.Count) { $partes -join "`n`n" } else { "Ludoteca $versao" }
}
Write-Host "Notas do release:`n$Notas`n"
gh release create $tag $apk -R matheusmerlim1/ludoteca-boardgames --title "Ludoteca $versao" --notes $Notas
if ($LASTEXITCODE -ne 0) { throw 'Não consegui criar o release.' }
Write-Host "Publicado $tag. Os aparelhos com a Ludoteca vão oferecer a atualização na próxima abertura."
