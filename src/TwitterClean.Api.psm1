Set-StrictMode -Version Latest

function ConvertTo-TwitterCleanBase64Url {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function New-TwitterCleanPkce {
    $random = New-Object byte[] 32
    $provider = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $provider.GetBytes($random) } finally { $provider.Dispose() }

    $verifier = ConvertTo-TwitterCleanBase64Url -Bytes $random
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $challengeBytes = $sha.ComputeHash([System.Text.Encoding]::ASCII.GetBytes($verifier))
    }
    finally {
        $sha.Dispose()
    }

    $stateBytes = New-Object byte[] 32
    $provider = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $provider.GetBytes($stateBytes) } finally { $provider.Dispose() }

    return [pscustomobject]@{
        Verifier  = $verifier
        Challenge = (ConvertTo-TwitterCleanBase64Url -Bytes $challengeBytes)
        State     = (ConvertTo-TwitterCleanBase64Url -Bytes $stateBytes)
    }
}

function ConvertTo-TwitterCleanFormBody {
    param([Parameter(Mandatory = $true)][hashtable]$Values)

    $parts = foreach ($key in $Values.Keys) {
        '{0}={1}' -f [Uri]::EscapeDataString([string]$key), [Uri]::EscapeDataString([string]$Values[$key])
    }
    return ($parts -join '&')
}

function Get-TwitterCleanQueryValue {
    param(
        [Parameter(Mandatory = $true)][string]$Query,
        [Parameter(Mandatory = $true)][string]$Name
    )

    foreach ($pair in $Query.TrimStart('?').Split('&')) {
        if ([string]::IsNullOrWhiteSpace($pair)) { continue }
        $separatorIndex = $pair.IndexOf('=')
        if ($separatorIndex -ge 0) {
            $keyPart = $pair.Substring(0, $separatorIndex)
            $valuePart = $pair.Substring($separatorIndex + 1)
        }
        else {
            $keyPart = $pair
            $valuePart = ''
        }
        $key = [Uri]::UnescapeDataString($keyPart.Replace('+', ' '))
        if ($key -ieq $Name) {
            return [Uri]::UnescapeDataString($valuePart.Replace('+', ' '))
        }
    }

    return $null
}

function Invoke-TwitterCleanOAuth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ClientId,
        [Parameter(Mandatory = $true)][string]$RedirectUri
    )

    $redirect = [Uri]$RedirectUri
    if ($redirect.Scheme -ne 'http' -or $redirect.Host -notin @('127.0.0.1', 'localhost')) {
        throw 'Por segurança, o callback OAuth deve usar HTTP somente em 127.0.0.1 ou localhost.'
    }

    $port = $redirect.Port
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
    $pkce = New-TwitterCleanPkce
    $scope = 'users.read follows.read tweet.read'
    $authValues = @{
        response_type         = 'code'
        client_id             = $ClientId
        redirect_uri          = $RedirectUri
        scope                 = $scope
        state                 = $pkce.State
        code_challenge        = $pkce.Challenge
        code_challenge_method = 'S256'
    }

    $authQuery = ConvertTo-TwitterCleanFormBody -Values $authValues
    $authorizationUrl = "https://x.com/i/oauth2/authorize?$authQuery"

    try {
        $listener.Start()
    }
    catch {
        throw "Não foi possível abrir a porta local $port. Feche outro programa que esteja usando essa porta e tente novamente. Detalhe: $($_.Exception.Message)"
    }

    $client = $null
    try {
        Write-Host ''
        Write-Host 'Abrindo a página oficial do X para autorização...' -ForegroundColor Cyan
        Write-Host 'Autorize somente as permissões de leitura solicitadas.' -ForegroundColor Gray
        Start-Process -FilePath $authorizationUrl

        $deadline = [DateTime]::UtcNow.AddMinutes(5)
        while (-not $listener.Pending()) {
            if ([DateTime]::UtcNow -gt $deadline) {
                throw 'A autorização não foi concluída em cinco minutos. Execute novamente para tentar outra vez.'
            }
            Start-Sleep -Milliseconds 200
        }

        $client = $listener.AcceptTcpClient()
        $stream = $client.GetStream()
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII, $false, 1024, $true)

        $requestLine = $reader.ReadLine()
        while ($null -ne ($headerLine = $reader.ReadLine())) {
            if ($headerLine -eq '') { break }
        }

        if ([string]::IsNullOrWhiteSpace($requestLine)) {
            throw 'O navegador enviou uma resposta de callback vazia.'
        }

        $requestParts = $requestLine.Split(' ')
        if ($requestParts.Count -lt 2) {
            throw 'Não foi possível interpretar o retorno de autorização do X.'
        }

        $callbackUri = [Uri]::new("http://127.0.0.1:$port$($requestParts[1])")
        if ($callbackUri.AbsolutePath.TrimEnd('/') -ne $redirect.AbsolutePath.TrimEnd('/')) {
            $html = '<!doctype html><html lang="pt-BR"><meta charset="utf-8"><title>TwitterClean</title><body>Callback inesperado. Feche esta aba e tente novamente.</body></html>'
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($html)
            $newline = [Environment]::NewLine
            $headerText = 'HTTP/1.1 400 Bad Request' + $newline + 'Content-Type: text/html; charset=utf-8' + $newline + 'Content-Length: ' + $bytes.Length + $newline + 'Connection: close' + $newline + $newline
            $header = [System.Text.Encoding]::ASCII.GetBytes($headerText)
            $stream.Write($header, 0, $header.Length)
            $stream.Write($bytes, 0, $bytes.Length)
            throw 'O caminho de retorno não corresponde ao Redirect URI configurado.'
        }

        $code = Get-TwitterCleanQueryValue -Query $callbackUri.Query -Name 'code'
        $returnedState = Get-TwitterCleanQueryValue -Query $callbackUri.Query -Name 'state'
        $oauthError = Get-TwitterCleanQueryValue -Query $callbackUri.Query -Name 'error'

        $html = '<!doctype html><html lang="pt-BR"><meta charset="utf-8"><title>TwitterClean</title><body><h2>Autorização recebida.</h2><p>Volte ao PowerShell para continuar. Você pode fechar esta aba.</p></body></html>'
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($html)
        $newline = [Environment]::NewLine
        $headerText = 'HTTP/1.1 200 OK' + $newline + 'Content-Type: text/html; charset=utf-8' + $newline + 'Content-Length: ' + $bytes.Length + $newline + 'Connection: close' + $newline + $newline
        $header = [System.Text.Encoding]::ASCII.GetBytes($headerText)
        $stream.Write($header, 0, $header.Length)
        $stream.Write($bytes, 0, $bytes.Length)

        if (-not [string]::IsNullOrWhiteSpace($oauthError)) {
            throw "O X recusou ou cancelou a autorização: $oauthError"
        }
        if ([string]::IsNullOrWhiteSpace($code)) {
            throw 'O X não retornou um código de autorização. Verifique a configuração OAuth do aplicativo.'
        }
        if ($returnedState -cne $pkce.State) {
            throw 'O valor state do OAuth não confere. A autorização foi cancelada por segurança.'
        }
    }
    finally {
        if ($null -ne $client) { $client.Close() }
        $listener.Stop()
    }

    $tokenValues = @{
        grant_type    = 'authorization_code'
        code          = $code
        redirect_uri  = $RedirectUri
        code_verifier = $pkce.Verifier
        client_id     = $ClientId
    }
    $body = ConvertTo-TwitterCleanFormBody -Values $tokenValues

    try {
        $tokenResponse = Invoke-RestMethod -Method Post -Uri 'https://api.x.com/2/oauth2/token' -ContentType 'application/x-www-form-urlencoded' -Body $body -ErrorAction Stop
    }
    catch {
        $detail = $_.ErrorDetails.Message
        if ([string]::IsNullOrWhiteSpace($detail)) { $detail = $_.Exception.Message }
        throw "O X não aceitou o código OAuth. Confira Client ID, Redirect URI e tipo Native App. Resposta: $detail"
    }

    $receivedAccessToken = Get-TwitterCleanPropertyValue -InputObject $tokenResponse -Name 'access_token'
    if ([string]::IsNullOrWhiteSpace([string]$receivedAccessToken)) {
        throw 'A resposta OAuth não contém access_token.'
    }

    return [string]$receivedAccessToken
}

function Invoke-TwitterCleanApiGet {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$AccessToken
    )

    try {
        return Invoke-RestMethod -Method Get -Uri $Uri -Headers @{ Authorization = "Bearer $AccessToken" } -ErrorAction Stop
    }
    catch {
        $detail = $_.ErrorDetails.Message
        if ([string]::IsNullOrWhiteSpace($detail)) { $detail = $_.Exception.Message }
        throw "Falha ao consultar a API do X ($Uri). $detail"
    }
}

function Get-TwitterCleanErrorText {
    param([Parameter(Mandatory = $true)]$ErrorObject)

    $parts = @()
    foreach ($propertyName in @('type', 'title', 'detail', 'message', 'resource_id', 'parameter')) {
        $property = $ErrorObject.PSObject.Properties[$propertyName]
        if ($null -ne $property -and $null -ne $property.Value) {
            $parts += "$propertyName=$($property.Value)"
        }
    }

    if ($parts.Count -eq 0) {
        return ($ErrorObject | ConvertTo-Json -Depth 8 -Compress)
    }

    return ($parts -join '; ')
}

function Get-TwitterCleanPropertyValue {
    param(
        [Parameter(Mandatory = $false)]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $InputObject) { return $null }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Invoke-TwitterCleanOnlineDiagnostic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ClientId,
        [Parameter(Mandatory = $false)][ValidateRange(1, 10000)][int]$MaxAccounts = 100,
        [Parameter(Mandatory = $false)][Nullable[int]]$DisplayedFollowingCount,
        [Parameter(Mandatory = $false)][string]$ArchivePath,
        [Parameter(Mandatory = $false)][string]$OutputDirectory,
        [Parameter(Mandatory = $false)][string]$RedirectUri = 'http://127.0.0.1:8787/callback/'
    )

    if ([string]::IsNullOrWhiteSpace($ClientId)) {
        throw 'Client ID vazio.'
    }

    $accessToken = Invoke-TwitterCleanOAuth -ClientId $ClientId -RedirectUri $RedirectUri
    Write-Host 'Autorização concluída. Consultando sua conta...' -ForegroundColor Green

    $meResponse = Invoke-TwitterCleanApiGet -Uri 'https://api.x.com/2/users/me?user.fields=id,name,username,public_metrics' -AccessToken $accessToken
    $me = Get-TwitterCleanPropertyValue -InputObject $meResponse -Name 'data'
    $meId = Get-TwitterCleanPropertyValue -InputObject $me -Name 'id'
    if ($null -eq $me -or [string]::IsNullOrWhiteSpace([string]$meId)) {
        throw 'A API do X não retornou os dados da conta autenticada.'
    }

    $followingFieldCount = $null
    $publicMetrics = Get-TwitterCleanPropertyValue -InputObject $me -Name 'public_metrics'
    $followingMetric = Get-TwitterCleanPropertyValue -InputObject $publicMetrics -Name 'following_count'
    if ($null -ne $followingMetric) {
        $followingFieldCount = [int]$followingMetric
    }

    $users = @()
    $apiErrors = @()
    $nextToken = $null
    $truncated = $false
    $rawResultCount = 0
    $pageNumber = 0
    $userFields = 'id,name,username,created_at,description,protected,verified,public_metrics'

    do {
        $remaining = $MaxAccounts - $users.Count
        if ($remaining -le 0) {
            $truncated = -not [string]::IsNullOrWhiteSpace([string]$nextToken)
            break
        }

        $pageSize = [Math]::Min(1000, $remaining)
        $query = "max_results=$pageSize&user.fields=$([Uri]::EscapeDataString($userFields))"
        if (-not [string]::IsNullOrWhiteSpace([string]$nextToken)) {
            $query += "&pagination_token=$([Uri]::EscapeDataString([string]$nextToken))"
        }

        $pageNumber++
        Write-Host "Consultando página $pageNumber (limite total: $MaxAccounts perfis)..." -ForegroundColor Gray
        $page = Invoke-TwitterCleanApiGet -Uri "https://api.x.com/2/users/$meId/following?$query" -AccessToken $accessToken

        $pageData = Get-TwitterCleanPropertyValue -InputObject $page -Name 'data'
        if ($null -ne $pageData) {
            foreach ($user in @($pageData)) {
                $users += $user
            }
        }

        $pageErrors = Get-TwitterCleanPropertyValue -InputObject $page -Name 'errors'
        if ($null -ne $pageErrors) {
            foreach ($apiError in @($pageErrors)) {
                $apiErrors += [pscustomobject]@{
                    ErrorText = (Get-TwitterCleanErrorText -ErrorObject $apiError)
                    Raw       = $apiError
                }
            }
        }

        $pageMeta = Get-TwitterCleanPropertyValue -InputObject $page -Name 'meta'
        $pageResultCount = Get-TwitterCleanPropertyValue -InputObject $pageMeta -Name 'result_count'
        if ($null -ne $pageResultCount) {
            $rawResultCount += [int]$pageResultCount
        }

        $nextToken = Get-TwitterCleanPropertyValue -InputObject $pageMeta -Name 'next_token'

        if ($users.Count -ge $MaxAccounts -and -not [string]::IsNullOrWhiteSpace([string]$nextToken)) {
            $truncated = $true
            break
        }
    }
    while (-not [string]::IsNullOrWhiteSpace([string]$nextToken))

    $seenIds = @{}
    $uniqueUsers = @()
    foreach ($user in $users) {
        $id = [string]$user.id
        if ([string]::IsNullOrWhiteSpace($id) -or $seenIds.ContainsKey($id)) { continue }
        $seenIds[$id] = $true
        $uniqueUsers += $user
    }

    $archiveComparison = @()
    if (-not [string]::IsNullOrWhiteSpace($ArchivePath)) {
        $offlineModule = Join-Path $PSScriptRoot 'TwitterClean.psm1'
        if (-not (Test-Path -LiteralPath $offlineModule -PathType Leaf)) {
            throw "Para comparar um arquivo antigo, o módulo local não foi encontrado: $offlineModule"
        }

        Import-Module -Name $offlineModule -Force
        $archiveRecords = @(Get-TwitterFollowingRecords -ArchivePath $ArchivePath)
        foreach ($record in $archiveRecords) {
            if (-not $seenIds.ContainsKey([string]$record.AccountId)) {
                $archiveComparison += [pscustomobject]@{
                    AccountId = [string]$record.AccountId
                    ProfileUrl = [string]$record.ProfileUrl
                    Status = 'Consta no arquivo antigo, mas não foi retornada pela consulta atual'
                    Note = 'Pode ser vínculo removido, conta indisponível ou diferença entre a data do arquivo e a consulta atual. Não confirma suspensão.'
                }
            }
        }
    }

    $returnedCount = $uniqueUsers.Count
    $apiMetricDifference = $null
    if ($null -ne $followingFieldCount) {
        $apiMetricDifference = $followingFieldCount - $returnedCount
    }

    $displayDifference = $null
    if ($PSBoundParameters.ContainsKey('DisplayedFollowingCount') -and $null -ne $DisplayedFollowingCount) {
        $displayDifference = [int]$DisplayedFollowingCount - $returnedCount
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
        $OutputDirectory = Join-Path (Get-Location).Path "TwitterClean-Online-$stamp"
    }
    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }

    $csvPath = Join-Path $OutputDirectory 'following-online.csv'
    $errorsPath = Join-Path $OutputDirectory 'api-errors.json'
    $jsonPath = Join-Path $OutputDirectory 'diagnostic.json'
    $htmlPath = Join-Path $OutputDirectory 'diagnostic.html'

    $accountRows = foreach ($user in $uniqueUsers) {
        $username = [string](Get-TwitterCleanPropertyValue -InputObject $user -Name 'username')
        $userId = [string](Get-TwitterCleanPropertyValue -InputObject $user -Name 'id')
        $profileUrl = if (-not [string]::IsNullOrWhiteSpace($username)) {
            "https://x.com/$username"
        }
        else {
            "https://x.com/i/user/$userId"
        }

        [pscustomobject]@{
            RecordType = 'Retornado pela API'
            AccountId = $userId
            Username = $username
            Name = [string](Get-TwitterCleanPropertyValue -InputObject $user -Name 'name')
            ProfileUrl = $profileUrl
            Protected = (Get-TwitterCleanPropertyValue -InputObject $user -Name 'protected')
            Verified = (Get-TwitterCleanPropertyValue -InputObject $user -Name 'verified')
            Status = 'Perfil retornado pelo endpoint de Following'
            ApiError = ''
        }
    }

    $errorRows = foreach ($apiError in $apiErrors) {
        [pscustomobject]@{
            RecordType = 'Erro retornado pela API'
            AccountId = ''
            Username = ''
            Name = ''
            ProfileUrl = ''
            Protected = ''
            Verified = ''
            Status = 'Erro da API; exige interpretação'
            ApiError = $apiError.ErrorText
        }
    }

    $archiveRows = foreach ($record in $archiveComparison) {
        [pscustomobject]@{
            RecordType = 'Comparação com arquivo antigo'
            AccountId = $record.AccountId
            Username = ''
            Name = ''
            ProfileUrl = $record.ProfileUrl
            Protected = ''
            Verified = ''
            Status = $record.Status
            ApiError = $record.Note
        }
    }

    $allRows = @()
    if ($null -ne $accountRows) { $allRows += @($accountRows) }
    if ($null -ne $errorRows) { $allRows += @($errorRows) }
    if ($null -ne $archiveRows) { $allRows += @($archiveRows) }
    $allRows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
    (ConvertTo-Json -InputObject @($apiErrors) -Depth 12) | Set-Content -LiteralPath $errorsPath -Encoding UTF8

    $authenticatedUsername = [string](Get-TwitterCleanPropertyValue -InputObject $me -Name 'username')
    $authenticatedName = [string](Get-TwitterCleanPropertyValue -InputObject $me -Name 'name')
    $summary = [pscustomobject]@{
        AuthenticatedUser = [pscustomobject]@{
            Id = [string]$meId
            Username = $authenticatedUsername
            Name = $authenticatedName
        }
        ProfileFollowingCount = $followingFieldCount
        DisplayedFollowingCount = $DisplayedFollowingCount
        ApiReturnedUniqueAccounts = $returnedCount
        ApiRawResultCount = $rawResultCount
        DifferenceFromProfileMetric = $apiMetricDifference
        DifferenceFromDisplayedCount = $displayDifference
        MaxAccountsLimit = $MaxAccounts
        ResultsTruncated = $truncated
        ApiErrorCount = $apiErrors.Count
        ArchiveOnlyCandidateCount = $archiveComparison.Count
        GeneratedAt = (Get-Date).ToString('o')
        Notes = @(
            'A consulta só mostra os usuários que o endpoint atual do X retornou.',
            'Uma diferença de contagem não revela automaticamente os IDs ausentes.',
            'Ausência de um usuário na resposta não prova, sozinha, suspensão ou desativação.',
            'Nenhuma ação de seguir ou deixar de seguir foi executada.'
        )
    }

    $json = [pscustomobject]@{
        Summary = $summary
        Users = @($uniqueUsers)
        ApiErrors = @($apiErrors)
        ArchiveOnlyCandidates = @($archiveComparison)
    }
    $json | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

    $safeUser = [System.Net.WebUtility]::HtmlEncode("@$authenticatedUsername")
    $metricText = if ($null -eq $followingFieldCount) { 'Não informado pela API' } else { [string]$followingFieldCount }
    $displayText = if ($null -eq $DisplayedFollowingCount) { 'Não informado' } else { [string]$DisplayedFollowingCount }
    $differenceText = if ($null -eq $apiMetricDifference) { 'Não calculada' } else { [string]$apiMetricDifference }
    $truncatedText = if ($truncated) { 'SIM - limite atingido; lista incompleta' } else { 'Não' }

    $userTableRows = foreach ($user in $uniqueUsers) {
        $id = [System.Net.WebUtility]::HtmlEncode([string](Get-TwitterCleanPropertyValue -InputObject $user -Name 'id'))
        $usernameValue = [string](Get-TwitterCleanPropertyValue -InputObject $user -Name 'username')
        $username = [System.Net.WebUtility]::HtmlEncode($usernameValue)
        $name = [System.Net.WebUtility]::HtmlEncode([string](Get-TwitterCleanPropertyValue -InputObject $user -Name 'name'))
        $url = if (-not [string]::IsNullOrWhiteSpace($usernameValue)) {
            "https://x.com/$([Uri]::EscapeDataString($usernameValue))"
        }
        else {
            "https://x.com/i/user/$id"
        }
        $protectedValue = Get-TwitterCleanPropertyValue -InputObject $user -Name 'protected'
        $verifiedValue = Get-TwitterCleanPropertyValue -InputObject $user -Name 'verified'
        $protectedText = if ($protectedValue) { 'Sim' } else { 'Não' }
        $verifiedText = if ($verifiedValue) { 'Sim' } else { 'Não' }
        "<tr><td><code>$id</code></td><td><a href=""$url"" target=""_blank"" rel=""noopener noreferrer"">@$username</a></td><td>$name</td><td>$protectedText</td><td>$verifiedText</td></tr>"
    }

    $errorTableRows = foreach ($apiError in $apiErrors) {
        $errorText = [System.Net.WebUtility]::HtmlEncode([string]$apiError.ErrorText)
        "<tr><td>$errorText</td></tr>"
    }

    $archiveTableRows = foreach ($record in $archiveComparison) {
        $id = [System.Net.WebUtility]::HtmlEncode([string]$record.AccountId)
        $url = [System.Net.WebUtility]::HtmlEncode([string]$record.ProfileUrl)
        $note = [System.Net.WebUtility]::HtmlEncode([string]$record.Note)
        "<tr><td><code>$id</code></td><td><a href=""$url"" target=""_blank"" rel=""noopener noreferrer"">Abrir perfil</a></td><td>$note</td></tr>"
    }

    $html = @"
<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>TwitterClean - diagnóstico online</title>
<style>
:root { color-scheme: light dark; font-family: system-ui,Segoe UI,Arial,sans-serif; }
body { max-width: 1350px; margin: 28px auto; padding: 0 18px; line-height: 1.5; }
.cards { display:flex; flex-wrap:wrap; gap:12px; margin:20px 0; }
.card { border:1px solid #8886; border-radius:9px; padding:12px 16px; min-width:170px; }
.card strong { display:block; font-size:1.45rem; }
.notice { border-left:4px solid #c7922c; padding:12px 15px; background:#c7922c18; margin:18px 0; }
table { width:100%; border-collapse:collapse; margin:12px 0 28px; }
th,td { text-align:left; padding:9px; border-bottom:1px solid #8885; overflow-wrap:anywhere; vertical-align:top; }
th { position:sticky; top:0; background:Canvas; }
code { font-family:ui-monospace,Consolas,monospace; }
</style>
</head>
<body>
<h1>TwitterClean - diagnóstico online</h1>
<p>Conta autorizada: <strong>$safeUser</strong>. Nenhuma ação de escrita foi executada.</p>
<div class="cards">
<div class="card"><span>Contas retornadas</span><strong>$returnedCount</strong></div>
<div class="card"><span>Contador na API</span><strong>$metricText</strong></div>
<div class="card"><span>Contador informado</span><strong>$displayText</strong></div>
<div class="card"><span>Diferença API</span><strong>$differenceText</strong></div>
<div class="card"><span>Erros da API</span><strong>$($apiErrors.Count)</strong></div>
<div class="card"><span>Limite atingido?</span><strong>$truncatedText</strong></div>
</div>
<div class="notice">
<strong>Interpretação:</strong> se o contador for maior que a quantidade de perfis retornados, o X não forneceu todos os vínculos como objetos de usuário nesta consulta. Isso indica uma discrepância, mas não revela os IDs ausentes nem confirma que estejam suspensos. Erros da API e candidatos do arquivo antigo aparecem em seções separadas.
<br><br><strong>Privacidade:</strong> os dados deste relatório foram salvos somente nesta pasta local.
</div>
<h2>Perfis retornados pelo X</h2>
<table><thead><tr><th>ID</th><th>Perfil</th><th>Nome</th><th>Protegida</th><th>Verificada</th></tr></thead><tbody>
$([string]::Join([Environment]::NewLine, $userTableRows))
</tbody></table>
<h2>Erros informados pela API</h2>
<table><thead><tr><th>Detalhes retornados</th></tr></thead><tbody>
$([string]::Join([Environment]::NewLine, $errorTableRows))
</tbody></table>
<h2>IDs encontrados apenas no arquivo antigo (se fornecido)</h2>
<table><thead><tr><th>ID</th><th>Perfil</th><th>Observação</th></tr></thead><tbody>
$([string]::Join([Environment]::NewLine, $archiveTableRows))
</tbody></table>
<p>Arquivos: following-online.csv, api-errors.json e diagnostic.json.</p>
</body>
</html>
"@

    Set-Content -LiteralPath $htmlPath -Value $html -Encoding UTF8

    return [pscustomobject]@{
        Username = $authenticatedUsername
        ApiFollowingCount = $followingFieldCount
        ReturnedAccounts = $returnedCount
        ApiErrorCount = $apiErrors.Count
        ArchiveOnlyCandidates = $archiveComparison.Count
        Truncated = $truncated
        HtmlPath = $htmlPath
        CsvPath = $csvPath
        JsonPath = $jsonPath
        OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
    }
}

Export-ModuleMember -Function New-TwitterCleanPkce, ConvertTo-TwitterCleanFormBody, Invoke-TwitterCleanOnlineDiagnostic
