Set-StrictMode -Version Latest

function ConvertFrom-TwitterArchiveJs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $jsonText = $Content.Trim()
    $assignmentIndex = $jsonText.IndexOf('=')
    if ($assignmentIndex -ge 0) {
        $jsonText = $jsonText.Substring($assignmentIndex + 1).Trim()
    }

    if ($jsonText.EndsWith(';')) {
        $jsonText = $jsonText.Substring(0, $jsonText.Length - 1).Trim()
    }

    if ([string]::IsNullOrWhiteSpace($jsonText)) {
        throw 'O arquivo following.js não contém dados JSON.'
    }

    try {
        $parsed = ConvertFrom-Json -InputObject $jsonText -ErrorAction Stop
    }
    catch {
        throw "Não foi possível interpretar o JSON do arquivo do X: $($_.Exception.Message)"
    }

    return ,$parsed
}

function Get-TwitterFollowingSourceFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ArchivePath
    )

    if (-not (Test-Path -LiteralPath $ArchivePath)) {
        throw "O caminho informado não existe: $ArchivePath"
    }

    $resolvedPath = (Resolve-Path -LiteralPath $ArchivePath).Path
    $sources = @()

    if (Test-Path -LiteralPath $resolvedPath -PathType Container) {
        $files = @(Get-ChildItem -LiteralPath $resolvedPath -Recurse -File -ErrorAction Stop |
            Where-Object { $_.Name -match '^following(?:[-_].*)?\.js$' } |
            Sort-Object FullName)

        foreach ($file in $files) {
            $sources += [pscustomobject]@{
                Name    = $file.FullName
                Content = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
            }
        }
    }
    elseif ([System.IO.Path]::GetExtension($resolvedPath) -ieq '.zip') {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $archive = [System.IO.Compression.ZipFile]::OpenRead($resolvedPath)
        try {
            $entries = @($archive.Entries |
                Where-Object {
                    $leafName = [System.IO.Path]::GetFileName($_.FullName)
                    $leafName -match '^following(?:[-_].*)?\.js$'
                } |
                Sort-Object FullName)

            foreach ($entry in $entries) {
                $stream = $entry.Open()
                try {
                    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8, $true)
                    try {
                        $sourceContent = $reader.ReadToEnd()
                    }
                    finally {
                        $reader.Dispose()
                    }
                }
                finally {
                    $stream.Dispose()
                }

                $sources += [pscustomobject]@{
                    Name    = $entry.FullName
                    Content = $sourceContent
                }
            }
        }
        finally {
            $archive.Dispose()
        }
    }
    elseif ([System.IO.Path]::GetExtension($resolvedPath) -ieq '.js') {
        $sources += [pscustomobject]@{
            Name    = $resolvedPath
            Content = [System.IO.File]::ReadAllText($resolvedPath, [System.Text.Encoding]::UTF8)
        }
    }
    else {
        throw 'Informe o arquivo ZIP do arquivo do X, a pasta extraída ou diretamente um arquivo following.js.'
    }

    if ($sources.Count -eq 0) {
        throw 'Nenhum arquivo following.js foi encontrado. No arquivo do X, procure a pasta data.'
    }

    return ,$sources
}

function Get-TwitterFollowingRecords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ArchivePath
    )

    $sources = @(Get-TwitterFollowingSourceFiles -ArchivePath $ArchivePath)
    $records = @()

    foreach ($source in $sources) {
        $parsedItems = ConvertFrom-TwitterArchiveJs -Content $source.Content

        foreach ($item in @($parsedItems)) {
            if ($null -eq $item) {
                continue
            }

            $followingProperty = $item.PSObject.Properties['following']
            if ($null -eq $followingProperty -or $null -eq $followingProperty.Value) {
                continue
            }

            $following = $followingProperty.Value
            $idProperty = $following.PSObject.Properties['accountId']
            if ($null -eq $idProperty -or [string]::IsNullOrWhiteSpace([string]$idProperty.Value)) {
                continue
            }

            $accountId = [string]$idProperty.Value
            $linkProperty = $following.PSObject.Properties['userLink']
            $archiveLink = ''
            if ($null -ne $linkProperty -and $null -ne $linkProperty.Value) {
                $archiveLink = [string]$linkProperty.Value
            }

            $profileUrl = ''
            if ($accountId -match '^\d+$') {
                $profileUrl = "https://x.com/i/user/$accountId"
            }

            $hint = 'Não verificada. O arquivo não informa o estado atual da conta.'
            if ([string]::IsNullOrWhiteSpace($archiveLink)) {
                $hint = 'Sem userLink no arquivo. Pode ser conta indisponível, protegida ou dado incompleto; exige revisão manual.'
            }

            $records += [pscustomobject]@{
                AccountId       = $accountId
                ProfileUrl      = $profileUrl
                ArchiveUserLink = $archiveLink
                AvailabilityHint = $hint
                SourceFile      = $source.Name
            }
        }
    }

    return ,$records
}

function New-TwitterCleanReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ArchivePath,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 2147483647)]
        [int]$DisplayedFollowingCount,

        [Parameter(Mandatory = $false)]
        [string]$OutputDirectory
    )

    $records = @(Get-TwitterFollowingRecords -ArchivePath $ArchivePath)

    $seen = @{}
    $uniqueRecords = @()
    $duplicateRecords = 0

    foreach ($record in $records) {
        if ($seen.ContainsKey($record.AccountId)) {
            $duplicateRecords++
            continue
        }

        $seen[$record.AccountId] = $true
        $uniqueRecords += $record
    }

    $missingLinks = @($uniqueRecords | Where-Object { [string]::IsNullOrWhiteSpace($_.ArchiveUserLink) }).Count
    $generatedAt = Get-Date -Format 'yyyyMMdd-HHmmss'

    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
        $OutputDirectory = Join-Path (Get-Location).Path "TwitterClean-Report-$generatedAt"
    }

    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }

    $csvPath = Join-Path $OutputDirectory 'following-report.csv'
    $htmlPath = Join-Path $OutputDirectory 'following-report.html'
    $jsonPath = Join-Path $OutputDirectory 'following-report.json'

    $uniqueRecords |
        Select-Object AccountId, ProfileUrl, ArchiveUserLink, AvailabilityHint, SourceFile |
        Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

    $uniqueRecords |
        ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath $jsonPath -Encoding UTF8

    $rowHtml = foreach ($record in $uniqueRecords) {
        $id = [System.Net.WebUtility]::HtmlEncode([string]$record.AccountId)
        $url = [System.Net.WebUtility]::HtmlEncode([string]$record.ProfileUrl)
        $archiveLink = [System.Net.WebUtility]::HtmlEncode([string]$record.ArchiveUserLink)
        $hint = [System.Net.WebUtility]::HtmlEncode([string]$record.AvailabilityHint)
        $source = [System.Net.WebUtility]::HtmlEncode([string]$record.SourceFile)

        $profileCell = if (-not [string]::IsNullOrWhiteSpace($url)) {
            "<a href=""$url"" target=""_blank"" rel=""noopener noreferrer"">Abrir perfil pelo ID</a>"
        }
        else {
            '<span>Link indisponível: ID inválido</span>'
        }

        $archiveCell = if (-not [string]::IsNullOrWhiteSpace($archiveLink)) {
            "<a href=""$archiveLink"" target=""_blank"" rel=""noopener noreferrer"">Link do arquivo</a>"
        }
        else {
            '<span>Não consta</span>'
        }

        "<tr><td><code>$id</code></td><td>$profileCell</td><td>$archiveCell</td><td>$hint</td><td>$source</td></tr>"
    }

    $countComparison = 'Não informado.'
    if ($PSBoundParameters.ContainsKey('DisplayedFollowingCount')) {
        $difference = $DisplayedFollowingCount - $uniqueRecords.Count
        $countComparison = "Contador informado no X: $DisplayedFollowingCount. IDs únicos no arquivo: $($uniqueRecords.Count). Diferença: $difference."
    }

    $safeGeneratedAt = [System.Net.WebUtility]::HtmlEncode((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
    $rows = $rowHtml -join [Environment]::NewLine

    $html = @"
<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>TwitterClean - Relatório de contas seguidas</title>
<style>
:root { color-scheme: light dark; font-family: system-ui,Segoe UI,Arial,sans-serif; }
body { max-width: 1500px; margin: 32px auto; padding: 0 20px; line-height: 1.5; }
h1 { margin-bottom: 6px; }
.muted { opacity: .75; }
.summary { display: flex; flex-wrap: wrap; gap: 12px; margin: 20px 0; }
.card { border: 1px solid #8886; border-radius: 10px; padding: 12px 16px; min-width: 160px; }
.card strong { display: block; font-size: 1.5rem; }
.warning { border-left: 4px solid #d69a25; padding: 12px 16px; background: #d69a2518; margin: 18px 0; }
table { border-collapse: collapse; width: 100%; font-size: .92rem; }
th, td { text-align: left; padding: 10px; border-bottom: 1px solid #8885; vertical-align: top; overflow-wrap: anywhere; }
th { position: sticky; top: 0; background: Canvas; }
code { font-family: ui-monospace,Consolas,monospace; }
a { color: LinkText; }
</style>
</head>
<body>
<h1>TwitterClean</h1>
<p class="muted">Relatório local gerado em $safeGeneratedAt. Nenhuma conexão foi feita com o X.</p>
<div class="summary">
<div class="card"><span>Registros lidos</span><strong>$($records.Count)</strong></div>
<div class="card"><span>IDs únicos</span><strong>$($uniqueRecords.Count)</strong></div>
<div class="card"><span>IDs sem userLink</span><strong>$missingLinks</strong></div>
<div class="card"><span>Registros duplicados</span><strong>$duplicateRecords</strong></div>
</div>
<div class="warning">
<strong>Comparação de contagem:</strong> $([System.Net.WebUtility]::HtmlEncode($countComparison))
<br><strong>Limitação:</strong> este relatório não consegue confirmar sozinho se uma conta foi suspensa, desativada, protegida ou se o vínculo ainda está ativo. Ausência de userLink é apenas um indício para revisão, não uma classificação definitiva.
</div>
<p>Abra os perfis individualmente pelo ID e confira o estado exibido pelo próprio X. Nenhuma ação de seguir/deixar de seguir é executada por esta ferramenta.</p>
<table>
<thead><tr><th>ID da conta</th><th>Perfil</th><th>Link no arquivo</th><th>Indício</th><th>Origem</th></tr></thead>
<tbody>
$rows
</tbody>
</table>
</body>
</html>
"@

    Set-Content -LiteralPath $htmlPath -Value $html -Encoding UTF8

    return [pscustomobject]@{
        ArchiveRecords    = $records.Count
        UniqueFollowing   = $uniqueRecords.Count
        DuplicateRecords  = $duplicateRecords
        MissingArchiveLinks = $missingLinks
        CsvPath           = $csvPath
        HtmlPath          = $htmlPath
        JsonPath          = $jsonPath
        OutputDirectory   = (Resolve-Path -LiteralPath $OutputDirectory).Path
    }
}

Export-ModuleMember -Function New-TwitterCleanReport, Get-TwitterFollowingRecords
