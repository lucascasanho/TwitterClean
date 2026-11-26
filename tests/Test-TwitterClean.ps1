# Testes de fumaça sem dependências externas (Windows PowerShell 5.1+ e PowerShell 7+).
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repoRoot 'src\TwitterClean.psm1'
$launcherPath = Join-Path $repoRoot 'TwitterClean.ps1'

Import-Module -Name $modulePath -Force

$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($launcherPath, [ref]$null, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    $messages = ($parseErrors | ForEach-Object { $_.Message }) -join '; '
    throw "Erro de sintaxe em $launcherPath : $messages"
}

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

    # Baseline: one archive, duplicate IDs, and one record with no userLink.
    $outputPath = Join-Path $testRoot 'single-report'
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
        throw "Esperado 1 conta sem link válido; recebido $($result.MissingArchiveLinks)."
    }
    if ($result.UnmatchedFollowingCount -ne 48) {
        throw "Esperado gap de 48 IDs; recebido $($result.UnmatchedFollowingCount)."
    }

    foreach ($path in @($result.CsvPath, $result.HtmlPath, $result.JsonPath, $result.ComparisonCsvPath, $result.ExclusiveIdsCsvPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Arquivo de relatório não foi criado: $path"
        }
    }

    $csvRows = @(Import-Csv -LiteralPath $result.CsvPath)
    if ($csvRows.Count -ne 2) {
        throw "Esperado 2 linhas únicas no CSV; recebido $($csvRows.Count)."
    }

    $jsonText = Get-Content -LiteralPath $result.JsonPath -Raw
    $jsonReport = ConvertFrom-Json -InputObject $jsonText
    if (@($jsonReport.Accounts).Count -ne 2) {
        throw "Esperado 2 contas no JSON; recebido $(@($jsonReport.Accounts).Count)."
    }
    if ($jsonReport.Summary.NetworkRequests -ne 0 -or $jsonReport.Summary.PasswordOrTokenRequested -ne $false) {
        throw 'O relatório não marcou corretamente que a análise é inteiramente local.'
    }

    # Multi-snapshot comparison: merge IDs, use a valid link found in a second
    # backup, retain IDs exclusive to one source, and reject unsafe userLink URLs.
    $sampleSecond = @'
window.YTD.following.part0 = [
  { "following": { "accountId": "1002", "userLink": "https://x.com/1002" } },
  { "following": { "accountId": "1003", "userLink": "https://twitter.com/intent/user?user_id=1003" } },
  { "following": { "accountId": "1004", "userLink": "javascript:alert(1)" } }
];
'@
    $jsSecondPath = Join-Path $testRoot 'following-second.js'
    # This name is intentionally accepted as a following*.js source file.
    Set-Content -LiteralPath $jsSecondPath -Value $sampleSecond -Encoding UTF8

    $multiOutputPath = Join-Path $testRoot 'multi-report'
    $multiResult = New-TwitterCleanReport -ArchivePath @($jsPath, $jsSecondPath) -OutputDirectory $multiOutputPath -DisplayedFollowingCount 50

    if ($multiResult.InputSources -ne 2) {
        throw "Esperado 2 origens; recebido $($multiResult.InputSources)."
    }
    if ($multiResult.ArchiveRecords -ne 6 -or $multiResult.UniqueFollowing -ne 4) {
        throw "Consolidação incorreta: registros=$($multiResult.ArchiveRecords), IDs únicos=$($multiResult.UniqueFollowing)."
    }
    if ($multiResult.DuplicateRecords -ne 2) {
        throw "Esperados 2 registros duplicados entre as origens; recebido $($multiResult.DuplicateRecords)."
    }
    if ($multiResult.MissingArchiveLinks -ne 1) {
        throw "Esperada 1 conta sem link válido depois da consolidação; recebido $($multiResult.MissingArchiveLinks)."
    }
    if ($multiResult.UnmatchedFollowingCount -ne 46 -or $multiResult.ArchiveCountExcess -ne 0) {
        throw 'A comparação com a contagem informada não produziu o gap esperado.'
    }
    if ($multiResult.ArchiveSourceOnlyAccounts -ne 3) {
        throw "Esperados 3 IDs exclusivos de uma origem; recebido $($multiResult.ArchiveSourceOnlyAccounts)."
    }

    $multiRows = @(Import-Csv -LiteralPath $multiResult.CsvPath)
    $account1002 = @($multiRows | Where-Object { $_.AccountId -eq '1002' })[0]
    if ($account1002.ArchiveUserLink -ne 'https://x.com/1002') {
        throw 'O consolidador não aproveitou o link válido encontrado no segundo backup.'
    }

    $account1004 = @($multiRows | Where-Object { $_.AccountId -eq '1004' })[0]
    if ($account1004.ArchiveLinkStatus -ne 'Link não reconhecido; revisão manual') {
        throw 'O link externo/inseguro não foi marcado para revisão manual.'
    }

    $multiHtml = Get-Content -LiteralPath $multiResult.HtmlPath -Raw
    if ($multiHtml -match 'javascript:alert') {
        throw 'Um link javascript foi incluído no HTML do relatório.'
    }

    $sourceRows = @(Import-Csv -LiteralPath $multiResult.ComparisonCsvPath)
    if ($sourceRows.Count -ne 2) {
        throw "Esperadas 2 linhas de comparação de origens; recebidas $($sourceRows.Count)."
    }
    $exclusiveRows = @(Import-Csv -LiteralPath $multiResult.ExclusiveIdsCsvPath)
    if ($exclusiveRows.Count -ne 3) {
        throw "Esperadas 3 contas exclusivas; recebidas $($exclusiveRows.Count)."
    }

    # ZIP compatibility: data/following.js inside an official archive layout.
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

    Write-Host 'Todos os testes do TwitterClean passaram.' -ForegroundColor Green
    Write-Host "Arquivo JS: $($result.ArchiveRecords) registros; $($result.UniqueFollowing) IDs únicos."
    Write-Host "Múltiplas origens: $($multiResult.ArchiveRecords) registros; $($multiResult.UniqueFollowing) IDs consolidados."
    Write-Host "Arquivo ZIP: $($zipResult.ArchiveRecords) registros; $($zipResult.UniqueFollowing) IDs únicos."
}
finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
