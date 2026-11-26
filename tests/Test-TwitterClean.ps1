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
