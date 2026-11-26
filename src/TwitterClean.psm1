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
        return (ConvertFrom-Json -InputObject $jsonText -ErrorAction Stop)
    }
    catch {
        throw "Não foi possível interpretar o JSON do arquivo do X: $($_.Exception.Message)"
    }
}

function Test-TwitterCleanSafeArchiveLink {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$Url
    )

    if ([string]::IsNullOrWhiteSpace($Url)) {
        return $false
    }

    $parsedUri = $null
    if (-not [System.Uri]::TryCreate($Url, [System.UriKind]::Absolute, [ref]$parsedUri)) {
        return $false
    }

    return ($parsedUri.Scheme -in @('http', 'https')) -and
        ($parsedUri.Host -in @('twitter.com', 'www.twitter.com', 'x.com', 'www.x.com'))
}

function Get-TwitterFollowingSourceFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ArchivePath
    )

    $sources = @()

    foreach ($inputPath in $ArchivePath) {
        if (-not (Test-Path -LiteralPath $inputPath)) {
            throw "O caminho informado não existe: $inputPath"
        }

        $resolvedPath = (Resolve-Path -LiteralPath $inputPath).Path

        if (Test-Path -LiteralPath $resolvedPath -PathType Container) {
            $files = @(Get-ChildItem -LiteralPath $resolvedPath -Recurse -File -ErrorAction Stop |
                Where-Object { $_.Name -match '^following(?:[-_].*)?\.js$' } |
                Sort-Object FullName)

            foreach ($file in $files) {
                $sources += [pscustomobject]@{
                    SnapshotPath = $resolvedPath
                    SourceFile   = $file.FullName
                    Content      = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
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
                        SnapshotPath = $resolvedPath
                        SourceFile   = $entry.FullName
                        Content      = $sourceContent
                    }
                }
            }
            finally {
                $archive.Dispose()
            }
        }
        elseif ([System.IO.Path]::GetExtension($resolvedPath) -ieq '.js' -and
            [System.IO.Path]::GetFileName($resolvedPath) -match '^following(?:[-_].*)?\.js$') {
            $sources += [pscustomobject]@{
                SnapshotPath = $resolvedPath
                SourceFile   = $resolvedPath
                Content      = [System.IO.File]::ReadAllText($resolvedPath, [System.Text.Encoding]::UTF8)
            }
        }
        else {
            throw "Formato não reconhecido: $inputPath. Informe um ZIP, uma pasta extraída ou um arquivo following.js."
        }
    }

    if ($sources.Count -eq 0) {
        throw 'Nenhum arquivo following.js foi encontrado. No arquivo do X, procure os arquivos dentro da pasta data.'
    }

    return $sources
}

function Get-TwitterFollowingRecords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ArchivePath
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

            $hint = 'O arquivo contém o ID, mas não informa o estado atual da conta.'
            if ([string]::IsNullOrWhiteSpace($archiveLink)) {
                $hint = 'Sem userLink neste registro. Pode ser dado incompleto ou conta indisponível; isso não comprova suspensão.'
            }
            elseif (-not (Test-TwitterCleanSafeArchiveLink -Url $archiveLink)) {
                $hint = 'O userLink do arquivo não é um endereço reconhecido do X; use o link gerado pelo ID para revisar.'
            }

            $records += [pscustomobject]@{
                AccountId        = $accountId
                ProfileUrl       = $profileUrl
                ArchiveUserLink  = $archiveLink
                AvailabilityHint = $hint
                SnapshotPath     = $source.SnapshotPath
                SourceFile       = $source.SourceFile
            }
        }
    }

    return $records
}

function New-TwitterCleanReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ArchivePath,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 2147483647)]
        [Nullable[int]]$DisplayedFollowingCount,

        [Parameter(Mandatory = $false)]
        [string]$OutputDirectory
    )

    $records = @(Get-TwitterFollowingRecords -ArchivePath $ArchivePath)

    # Merge repeated IDs across files and snapshots. Prefer a valid X profile link
    # when at least one source contains it; keep every source for traceability.
    $seen = @{}
    $uniqueRecords = @()
    foreach ($record in $records) {
        $accountId = [string]$record.AccountId

        if ($seen.ContainsKey($accountId)) {
            $existing = $uniqueRecords[$seen[$accountId]]
            $existing.DuplicateOccurrences = [int]$existing.DuplicateOccurrences + 1

            if ((-not (Test-TwitterCleanSafeArchiveLink -Url $existing.ArchiveUserLink)) -and
                (Test-TwitterCleanSafeArchiveLink -Url $record.ArchiveUserLink)) {
                $existing.ArchiveUserLink = [string]$record.ArchiveUserLink
                $existing.ArchiveLinkStatus = 'Link válido encontrado em outro arquivo'
                $existing.AvailabilityHint = 'Link encontrado em pelo menos um arquivo. Isso não confirma o estado atual da conta.'
            }
            elseif ([string]::IsNullOrWhiteSpace([string]$existing.ArchiveUserLink) -and
                -not [string]::IsNullOrWhiteSpace([string]$record.ArchiveUserLink)) {
                $existing.ArchiveUserLink = [string]$record.ArchiveUserLink
                $existing.ArchiveLinkStatus = 'Link não reconhecido; revisão manual'
            }

            $sourceList = @($existing.ArchiveSources + @([string]$record.SnapshotPath) | Sort-Object -Unique)
            $fileList = @($existing.SourceFiles + @([string]$record.SourceFile) | Sort-Object -Unique)
            $existing.ArchiveSources = $sourceList
            $existing.SourceFiles = $fileList
            continue
        }

        $linkStatus = 'Sem link no arquivo'
        if (Test-TwitterCleanSafeArchiveLink -Url $record.ArchiveUserLink) {
            $linkStatus = 'Link válido no arquivo'
        }
        elseif (-not [string]::IsNullOrWhiteSpace([string]$record.ArchiveUserLink)) {
            $linkStatus = 'Link não reconhecido; revisão manual'
        }

        $uniqueRecords += [pscustomobject]@{
            AccountId           = $accountId
            ProfileUrl          = [string]$record.ProfileUrl
            ArchiveUserLink     = [string]$record.ArchiveUserLink
            ArchiveLinkStatus   = $linkStatus
            AvailabilityHint    = [string]$record.AvailabilityHint
            ArchiveSources      = @([string]$record.SnapshotPath)
            SourceFiles         = @([string]$record.SourceFile)
            DuplicateOccurrences = 0
        }
        $seen[$accountId] = $uniqueRecords.Count - 1
    }

    $duplicateRecords = $records.Count - $uniqueRecords.Count
    $missingLinks = @($uniqueRecords | Where-Object {
        -not (Test-TwitterCleanSafeArchiveLink -Url $_.ArchiveUserLink)
    }).Count

    # Build a per-input comparison so the user can see what each old backup adds.
    $sourceMap = @{}
    foreach ($record in $records) {
        $sourceKey = [string]$record.SnapshotPath
        if (-not $sourceMap.ContainsKey($sourceKey)) {
            $sourceMap[$sourceKey] = [pscustomobject]@{
                SnapshotPath = $sourceKey
                RawRecords   = 0
                IdSet        = @{}
                MissingLinks = 0
            }
        }

        $sourceEntry = $sourceMap[$sourceKey]
        $sourceEntry.RawRecords++
        $sourceEntry.IdSet[[string]$record.AccountId] = $true
        if (-not (Test-TwitterCleanSafeArchiveLink -Url $record.ArchiveUserLink)) {
            $sourceEntry.MissingLinks++
        }
    }

    $sourceSummary = @()
    foreach ($sourceKey in @($sourceMap.Keys | Sort-Object)) {
        $sourceEntry = $sourceMap[$sourceKey]
        $sourceUnique = $sourceEntry.IdSet.Count
        $exclusiveCount = 0

        foreach ($id in $sourceEntry.IdSet.Keys) {
            $globalRecord = $uniqueRecords[$seen[[string]$id]]
            if (@($globalRecord.ArchiveSources).Count -eq 1) {
                $exclusiveCount++
            }
        }

        $sourceSummary += [pscustomobject]@{
            ArchiveSource            = [string]$sourceEntry.SnapshotPath
            RawRecords               = [int]$sourceEntry.RawRecords
            UniqueAccounts           = [int]$sourceUnique
            DuplicateRecords         = [int]($sourceEntry.RawRecords - $sourceUnique)
            IDsExclusiveToThisSource = [int]$exclusiveCount
            RecordsWithoutValidLink  = [int]$sourceEntry.MissingLinks
        }
    }

    $exclusiveRecords = @($uniqueRecords | Where-Object { @($_.ArchiveSources).Count -eq 1 })
    $unmatchedCount = $null
    $archiveExcessCount = $null
    $countComparison = 'O contador atual não foi informado.'
    if ($PSBoundParameters.ContainsKey('DisplayedFollowingCount') -and $null -ne $DisplayedFollowingCount) {
        $delta = [int]$DisplayedFollowingCount - $uniqueRecords.Count
        $unmatchedCount = [Math]::Max(0, $delta)
        $archiveExcessCount = [Math]::Max(0, -$delta)

        if ($delta -gt 0) {
            $countComparison = "O contador informado excede em $delta a quantidade de IDs únicos encontrada nos arquivos. Os IDs ausentes não podem ser deduzidos a partir dessa diferença."
        }
        elseif ($delta -lt 0) {
            $countComparison = "Os arquivos contêm $(-$delta) IDs únicos a mais que o contador atual. Isso pode refletir datas diferentes ou vínculos removidos depois do backup."
        }
        else {
            $countComparison = 'O contador informado coincide numericamente com a quantidade de IDs únicos encontrada. Isso não confirma que todos os vínculos ainda estejam ativos.'
        }
    }

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
    $comparisonCsvPath = Join-Path $OutputDirectory 'archive-comparison.csv'
    $exclusiveCsvPath = Join-Path $OutputDirectory 'archive-exclusive-ids.csv'

    $accountCsvRows = foreach ($record in $uniqueRecords) {
        [pscustomobject]@{
            AccountId         = $record.AccountId
            ProfileUrl        = $record.ProfileUrl
            ArchiveUserLink   = $record.ArchiveUserLink
            ArchiveLinkStatus = $record.ArchiveLinkStatus
            AvailabilityHint  = $record.AvailabilityHint
            ArchiveSources    = (@($record.ArchiveSources) -join ' | ')
            SourceFiles       = (@($record.SourceFiles) -join ' | ')
            DuplicateCount    = $record.DuplicateOccurrences
        }
    }

    $accountCsvContent = @($accountCsvRows | ConvertTo-Csv -NoTypeInformation)
    if ($accountCsvContent.Count -eq 0) {
        $accountCsvContent = @('"AccountId","ProfileUrl","ArchiveUserLink","ArchiveLinkStatus","AvailabilityHint","ArchiveSources","SourceFiles","DuplicateCount"')
    }
    Set-Content -LiteralPath $csvPath -Value $accountCsvContent -Encoding UTF8

    $sourceCsvContent = @($sourceSummary | ConvertTo-Csv -NoTypeInformation)
    if ($sourceCsvContent.Count -eq 0) {
        $sourceCsvContent = @('"ArchiveSource","RawRecords","UniqueAccounts","DuplicateRecords","IDsExclusiveToThisSource","RecordsWithoutValidLink"')
    }
    Set-Content -LiteralPath $comparisonCsvPath -Value $sourceCsvContent -Encoding UTF8

    $exclusiveCsvRows = foreach ($record in $exclusiveRecords) {
        [pscustomobject]@{
            AccountId       = $record.AccountId
            ProfileUrl      = $record.ProfileUrl
            ArchiveSource   = (@($record.ArchiveSources) -join ' | ')
            ArchiveUserLink = $record.ArchiveUserLink
        }
    }
    $exclusiveCsvContent = @($exclusiveCsvRows | ConvertTo-Csv -NoTypeInformation)
    if ($exclusiveCsvContent.Count -eq 0) {
        $exclusiveCsvContent = @('"AccountId","ProfileUrl","ArchiveSource","ArchiveUserLink"')
    }
    Set-Content -LiteralPath $exclusiveCsvPath -Value $exclusiveCsvContent -Encoding UTF8

    $summary = [pscustomobject]@{
        InputSources                = @($ArchivePath).Count
        FollowingFilesFound         = $sources.Count
        ArchiveRecords              = $records.Count
        UniqueFollowing              = $uniqueRecords.Count
        DuplicateRecords             = $duplicateRecords
        MissingArchiveLinks          = $missingLinks
        DisplayedFollowingCount      = $DisplayedFollowingCount
        UnmatchedFollowingCount      = $unmatchedCount
        ArchiveCountExcess           = $archiveExcessCount
        ArchiveSourceOnlyAccounts   = $exclusiveRecords.Count
        CountComparison              = $countComparison
        GeneratedAt                  = (Get-Date).ToString('o')
        NetworkRequests               = 0
        PasswordOrTokenRequested      = $false
        Notes = @(
            'Todos os dados são lidos de arquivos locais. Nenhuma conexão ou autenticação no X é realizada.',
            'A união reúne IDs encontrados nos arquivos fornecidos; backups incompletos podem continuar sem alguns IDs.',
            'A diferença entre o contador atual e os IDs encontrados não revela a identidade dos IDs ausentes.',
            'A ausência de userLink não confirma suspensão, desativação nem que o vínculo continue ativo.',
            'Nenhuma ação de seguir ou deixar de seguir é executada.'
        )
    }

    $json = [pscustomobject]@{
        Summary          = $summary
        Sources          = @($sourceSummary)
        Accounts         = @($uniqueRecords)
        SourceOnlyIds    = @($exclusiveRecords)
    }
    $json | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

    $safeGeneratedAt = [System.Net.WebUtility]::HtmlEncode((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
    $safeCountComparison = [System.Net.WebUtility]::HtmlEncode($countComparison)

    $rowHtml = foreach ($record in $uniqueRecords) {
        $id = [System.Net.WebUtility]::HtmlEncode([string]$record.AccountId)
        $url = [System.Net.WebUtility]::HtmlEncode([string]$record.ProfileUrl)
        $archiveLink = [System.Net.WebUtility]::HtmlEncode([string]$record.ArchiveUserLink)
        $hint = [System.Net.WebUtility]::HtmlEncode([string]$record.AvailabilityHint)
        $status = [System.Net.WebUtility]::HtmlEncode([string]$record.ArchiveLinkStatus)
        $source = [System.Net.WebUtility]::HtmlEncode((@($record.ArchiveSources) -join ' | '))

        $profileCell = if (-not [string]::IsNullOrWhiteSpace([string]$record.ProfileUrl)) {
            "<a href=""$url"" target=""_blank"" rel=""noopener noreferrer"">Abrir perfil pelo ID</a>"
        }
        else {
            '<span>ID sem formato numérico; não foi gerado link</span>'
        }

        $archiveCell = if (Test-TwitterCleanSafeArchiveLink -Url $record.ArchiveUserLink) {
            "<a href=""$archiveLink"" target=""_blank"" rel=""noopener noreferrer"">Link do arquivo</a>"
        }
        elseif ([string]::IsNullOrWhiteSpace([string]$record.ArchiveUserLink)) {
            '<span>Não consta</span>'
        }
        else {
            '<span>Link não reconhecido</span>'
        }

        "<tr><td><code>$id</code></td><td>$profileCell</td><td>$archiveCell</td><td>$status</td><td>$hint</td><td>$source</td></tr>"
    }

    $sourceRowsHtml = foreach ($source in $sourceSummary) {
        $path = [System.Net.WebUtility]::HtmlEncode([string]$source.ArchiveSource)
        "<tr><td>$path</td><td>$($source.RawRecords)</td><td>$($source.UniqueAccounts)</td><td>$($source.DuplicateRecords)</td><td>$($source.IDsExclusiveToThisSource)</td><td>$($source.RecordsWithoutValidLink)</td></tr>"
    }

    $exclusiveRowsHtml = foreach ($record in $exclusiveRecords) {
        $id = [System.Net.WebUtility]::HtmlEncode([string]$record.AccountId)
        $url = [System.Net.WebUtility]::HtmlEncode([string]$record.ProfileUrl)
        $source = [System.Net.WebUtility]::HtmlEncode((@($record.ArchiveSources) -join ' | '))
        $profileCell = if (-not [string]::IsNullOrWhiteSpace([string]$record.ProfileUrl)) {
            "<a href=""$url"" target=""_blank"" rel=""noopener noreferrer"">Abrir perfil</a>"
        }
        else {
            'Sem link gerado'
        }
        "<tr><td><code>$id</code></td><td>$profileCell</td><td>$source</td></tr>"
    }

    $accountRowsText = [string]::Join([Environment]::NewLine, @($rowHtml))
    $sourceRowsText = [string]::Join([Environment]::NewLine, @($sourceRowsHtml))
    $exclusiveRowsText = [string]::Join([Environment]::NewLine, @($exclusiveRowsHtml))

    $displayedCountText = if ($null -eq $DisplayedFollowingCount) { 'Não informado' } else { [string]$DisplayedFollowingCount }
    $unmatchedText = if ($null -eq $unmatchedCount) { 'Não calculado' } else { [string]$unmatchedCount }
    $excessText = if ($null -eq $archiveExcessCount) { 'Não calculado' } else { [string]$archiveExcessCount }

    $html = @"
<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>TwitterClean - análise local</title>
<style>
:root { color-scheme: light dark; font-family: system-ui,Segoe UI,Arial,sans-serif; }
body { max-width: 1550px; margin: 30px auto; padding: 0 18px; line-height: 1.5; }
.cards { display:flex; flex-wrap:wrap; gap:12px; margin:20px 0; }
.card { border:1px solid #8886; border-radius:9px; padding:12px 16px; min-width:150px; }
.card strong { display:block; font-size:1.45rem; }
.notice { border-left:4px solid #c7922c; padding:12px 15px; background:#c7922c18; margin:18px 0; }
table { width:100%; border-collapse:collapse; margin:12px 0 28px; }
th,td { text-align:left; padding:9px; border-bottom:1px solid #8885; overflow-wrap:anywhere; vertical-align:top; }
th { position:sticky; top:0; background:Canvas; }
code { font-family:ui-monospace,Consolas,monospace; }
.small { opacity:.78; font-size:.92rem; }
</style>
</head>
<body>
<h1>TwitterClean - análise local</h1>
<p class="small">Relatório gerado em $safeGeneratedAt. Nenhuma conexão foi feita com o X e nenhuma credencial foi solicitada.</p>
<div class="cards">
<div class="card"><span>Registros lidos</span><strong>$($records.Count)</strong></div>
<div class="card"><span>IDs únicos reunidos</span><strong>$($uniqueRecords.Count)</strong></div>
<div class="card"><span>Registros duplicados</span><strong>$duplicateRecords</strong></div>
<div class="card"><span>Sem link válido</span><strong>$missingLinks</strong></div>
<div class="card"><span>Contador informado</span><strong>$displayedCountText</strong></div>
<div class="card"><span>Contagem sem ID correspondente</span><strong>$unmatchedText</strong></div>
<div class="card"><span>IDs acima do contador</span><strong>$excessText</strong></div>
</div>
<div class="notice">
<strong>Comparação:</strong> $safeCountComparison
<br><br><strong>Limite técnico:</strong> o programa só pode reunir IDs que existam nos arquivos escolhidos. Se o backup não contiver os IDs, a diferença numérica não permite reconstruí-los nem determinar quais contas estão suspensas, desativadas ou ocultas.
<br><br><strong>Revisão manual:</strong> os links abrem perfis individualmente no X. O campo “sem link válido” descreve o conteúdo do arquivo, não o estado atual da conta.
</div>
<h2>Comparação entre arquivos e backups</h2>
<table><thead><tr><th>Origem</th><th>Registros</th><th>IDs únicos</th><th>Duplicados</th><th>IDs exclusivos desta origem</th><th>Registros sem link válido</th></tr></thead><tbody>
$sourceRowsText
</tbody></table>
<h2>IDs encontrados somente em uma origem</h2>
<p class="small">Estes IDs foram encontrados em apenas um dos arquivos/locais informados. Isso ajuda a identificar o que cada backup acrescenta à união.</p>
<table><thead><tr><th>ID</th><th>Perfil</th><th>Origem</th></tr></thead><tbody>
$exclusiveRowsText
</tbody></table>
<h2>Lista consolidada de contas</h2>
<table><thead><tr><th>ID</th><th>Perfil pelo ID</th><th>Link do arquivo</th><th>Estado do link</th><th>Observação</th><th>Origens</th></tr></thead><tbody>
$accountRowsText
</tbody></table>
<p class="small">Arquivos gerados: following-report.csv, archive-comparison.csv, archive-exclusive-ids.csv e following-report.json. Mantenha-os privados: contêm IDs e informações da sua rede de contatos.</p>
</body>
</html>
"@

    Set-Content -LiteralPath $htmlPath -Value $html -Encoding UTF8

    return [pscustomobject]@{
        InputSources              = @($ArchivePath).Count
        FollowingFilesFound       = $sources.Count
        ArchiveRecords            = $records.Count
        UniqueFollowing           = $uniqueRecords.Count
        DuplicateRecords          = $duplicateRecords
        MissingArchiveLinks       = $missingLinks
        UnmatchedFollowingCount   = $unmatchedCount
        ArchiveCountExcess        = $archiveExcessCount
        ArchiveSourceOnlyAccounts = $exclusiveRecords.Count
        CsvPath                   = $csvPath
        ComparisonCsvPath         = $comparisonCsvPath
        ExclusiveIdsCsvPath       = $exclusiveCsvPath
        HtmlPath                  = $htmlPath
        JsonPath                  = $jsonPath
        OutputDirectory            = (Resolve-Path -LiteralPath $OutputDirectory).Path
    }
}

Export-ModuleMember -Function New-TwitterCleanReport, Get-TwitterFollowingRecords
