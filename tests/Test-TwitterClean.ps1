# Testes de fumaça sem dependências externas (PowerShell 5.1+).
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\TwitterClean.psm1'
Import-Module -Name $modulePath -Force

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("TwitterClean-Test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null

try {
    $sample = @'
window.YTD.following.part0 = [
  { "following": { "accountId": "1001", "userLink": "https://twitter.com/intent/user?user_id=1001" } },
  { "following": { "accountId": "1002" } },
  { "following": { "accountId": "1001", "userLink": "https://twitter.com/intent/user?user_id=1001" } }
];
'@

    $jsPath = Join-Path $testRoot 'following.js'
    Set-Content -LiteralPath $jsPath -Value $sample -Encoding UTF8

    $outputPath = Join-Path $testRoot 'report'
    $result = New-TwitterCleanReport -ArchivePath $jsPath -OutputDirectory $outputPath -DisplayedFollowingCount 50

    if ($result.ArchiveRecords -ne 3) {
        throw "Esperado 3 registros; recebido $($result.ArchiveRecords)."
    }
    if ($result.UniqueFollowing -ne 2) {
        throw "Esperado 2 IDs únicos; recebido $($result.UniqueFollowing)."
    }
    if ($result.DuplicateRecords -ne 1) {
        throw "Esperado 1 duplicado; recebido $($result.DuplicateRecords)."
    }
    if ($result.MissingArchiveLinks -ne 1) {
        throw "Esperado 1 registro sem userLink; recebido $($result.MissingArchiveLinks)."
    }

    foreach ($path in @($result.CsvPath, $result.HtmlPath, $result.JsonPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Arquivo de relatório não foi criado: $path"
        }
    }

    $csvRows = @(Import-Csv -LiteralPath $result.CsvPath)
    if ($csvRows.Count -ne 2) {
        throw "Esperado 2 linhas únicas no CSV; recebido $($csvRows.Count)."
    }

    $jsonRows = @(Get-Content -LiteralPath $result.JsonPath -Raw | ConvertFrom-Json)
    if ($jsonRows.Count -ne 2) {
        throw "Esperado 2 registros no JSON; recebido $($jsonRows.Count)."
    }

    # Também valida a leitura do ZIP completo, no caminho data/following.js.
    $archiveRoot = Join-Path $testRoot 'archive'
    $archiveData = Join-Path $archiveRoot 'data'
    New-Item -ItemType Directory -Path $archiveData -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $archiveData 'following.js') -Value $sample -Encoding UTF8

    $zipPath = Join-Path $testRoot 'sample-x-archive.zip'
    Compress-Archive -Path (Join-Path $archiveRoot '*') -DestinationPath $zipPath -Force

    $zipReportPath = Join-Path $testRoot 'zip-report'
    $zipResult = New-TwitterCleanReport -ArchivePath $zipPath -OutputDirectory $zipReportPath
    if ($zipResult.UniqueFollowing -ne 2 -or $zipResult.MissingArchiveLinks -ne 1) {
        throw 'A leitura do ZIP não produziu os resultados esperados.'
    }

    Write-Host 'Todos os testes de fumaça passaram.' -ForegroundColor Green
    Write-Host "Arquivo JS: $($result.ArchiveRecords) registros; $($result.UniqueFollowing) IDs únicos."
    Write-Host "Arquivo ZIP: $($zipResult.ArchiveRecords) registros; $($zipResult.UniqueFollowing) IDs únicos."
}
finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}


# Validates PowerShell syntax for the online launcher and OAuth module without network access.
$apiModulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\TwitterClean.Api.psm1'
$onlineLauncherPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'TwitterClean-Online.ps1'

foreach ($sourcePath in @($apiModulePath, $onlineLauncherPath)) {
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$null, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        $messages = ($parseErrors | ForEach-Object { $_.Message }) -join '; '
        throw "Erro de sintaxe em $sourcePath : $messages"
    }
}

Import-Module -Name $apiModulePath -Force
$pkce = New-TwitterCleanPkce
if ($pkce.Verifier.Length -lt 43 -or $pkce.Challenge.Length -ne 43 -or $pkce.State.Length -lt 20) {
    throw 'Os valores PKCE gerados não possuem o formato esperado.'
}

$formBody = ConvertTo-TwitterCleanFormBody -Values @{ client_id = 'abc+123'; redirect_uri = 'http://127.0.0.1:8787/callback/' }
if ($formBody -notmatch 'client_id=abc%2B123' -or $formBody -notmatch 'redirect_uri=http%3A%2F%2F127.0.0.1%3A8787%2Fcallback%2F') {
    throw "A codificação application/x-www-form-urlencoded não foi gerada como esperado: $formBody"
}

Write-Host 'Testes de sintaxe e OAuth PKCE passaram.' -ForegroundColor Green
