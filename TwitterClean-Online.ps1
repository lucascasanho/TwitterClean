#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ClientId,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 10000)]
    [int]$MaxAccounts = 100,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 2147483647)]
    [int]$DisplayedFollowingCount,

    [Parameter(Mandatory = $false)]
    [string]$ArchivePath,

    [Parameter(Mandatory = $false)]
    [string]$OutputDirectory,

    [Parameter(Mandatory = $false)]
    [switch]$NoOpenReport
)

$ErrorActionPreference = 'Stop'

try {
    $modulePath = Join-Path $PSScriptRoot 'src\TwitterClean.Api.psm1'
    if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
        throw "Módulo da API não encontrado: $modulePath"
    }
    Import-Module -Name $modulePath -Force

    Write-Host ''
    Write-Host 'TwitterClean 0.2 - diagnóstico online do X' -ForegroundColor Cyan
    Write-Host 'Modo somente leitura. Nenhum unfollow será executado.' -ForegroundColor Gray
    Write-Host ''

    if ([string]::IsNullOrWhiteSpace($ClientId)) {
        $ClientId = Read-Host 'Cole o Client ID do aplicativo X Developer'
    }
    if ([string]::IsNullOrWhiteSpace($ClientId)) {
        throw 'O Client ID é obrigatório.'
    }

    if (-not $PSBoundParameters.ContainsKey('DisplayedFollowingCount')) {
        $countText = Read-Host 'Quantas contas o contador do seu perfil diz que você segue? (ex.: 50; Enter para ignorar)'
        if (-not [string]::IsNullOrWhiteSpace($countText)) {
            $parsedCount = 0
            if (-not [int]::TryParse($countText, [ref]$parsedCount) -or $parsedCount -lt 0) {
                throw 'Informe um número inteiro válido para o contador.'
            }
            $DisplayedFollowingCount = $parsedCount
        }
    }

    $ownedMax = [Math]::Round(($MaxAccounts * 0.001) + 0.01, 2)
    $standardMax = [Math]::Round(($MaxAccounts * 0.01) + 0.01, 2)

    Write-Host ''
    Write-Host 'Antes de continuar, confira os custos oficiais do X:' -ForegroundColor Yellow
    Write-Host ('- Limite de contas nesta execução: {0}' -f $MaxAccounts)
    Write-Host ('- Estimativa máxima se Owned Reads se aplicar: aproximadamente US$ {0:N2}, incluindo uma consulta de usuário.' -f $ownedMax)
    Write-Host ('- Estimativa máxima pela tarifa normal: aproximadamente US$ {0:N2}, incluindo uma consulta de usuário.' -f $standardMax)
    Write-Host 'O preço efetivo depende de o aplicativo ser do mesmo desenvolvedor da conta autenticada e das tarifas vigentes no Developer Console.'
    Write-Host 'A ferramenta não compra créditos nem ativa recarga automática.'
    Write-Host ''

    $confirmation = Read-Host 'Para autorizar a consulta somente de leitura, digite CONTINUAR'
    if ($confirmation -cne 'CONTINUAR') {
        Write-Host 'Consulta cancelada. Nenhuma chamada à API foi feita.' -ForegroundColor Yellow
        exit 0
    }

    $parameters = @{
        ClientId = $ClientId
        MaxAccounts = $MaxAccounts
    }

    if ($PSBoundParameters.ContainsKey('DisplayedFollowingCount') -and $null -ne $DisplayedFollowingCount) {
        $parameters.DisplayedFollowingCount = $DisplayedFollowingCount
    }
    if (-not [string]::IsNullOrWhiteSpace($ArchivePath)) {
        $parameters.ArchivePath = $ArchivePath
    }
    if (-not [string]::IsNullOrWhiteSpace($OutputDirectory)) {
        $parameters.OutputDirectory = $OutputDirectory
    }

    $result = Invoke-TwitterCleanOnlineDiagnostic @parameters

    Write-Host ''
    Write-Host 'Diagnóstico concluído.' -ForegroundColor Green
    Write-Host "Conta autenticada:       @$($result.Username)"
    Write-Host "Contas retornadas pela API: $($result.ReturnedAccounts)"
    Write-Host "Contador following da API: $($result.ApiFollowingCount)"
    Write-Host "Erros informados pela API: $($result.ApiErrorCount)"
    Write-Host "Candidatos do arquivo antigo: $($result.ArchiveOnlyCandidates)"
    Write-Host "Consulta limitada?       $($result.Truncated)"
    Write-Host ''
    Write-Host "Relatório HTML: $($result.HtmlPath)" -ForegroundColor Cyan
    Write-Host "CSV:            $($result.CsvPath)"
    Write-Host "JSON:           $($result.JsonPath)"

    if (-not $NoOpenReport) {
        Start-Process -FilePath $result.HtmlPath
    }
}
catch {
    Write-Error $_
    exit 1
}
