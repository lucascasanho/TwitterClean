#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$ArchivePath,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 2147483647)]
    [int]$DisplayedFollowingCount,

    [Parameter(Mandatory = $false)]
    [string]$OutputDirectory,

    [Parameter(Mandatory = $false)]
    [switch]$NoOpenReport
)

$ErrorActionPreference = 'Stop'

try {
    $modulePath = Join-Path $PSScriptRoot 'src\TwitterClean.psm1'
    if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
        throw "Módulo não encontrado: $modulePath"
    }

    Import-Module -Name $modulePath -Force

    $parameters = @{
        ArchivePath = $ArchivePath
    }

    if ($PSBoundParameters.ContainsKey('DisplayedFollowingCount')) {
        $parameters.DisplayedFollowingCount = $DisplayedFollowingCount
    }

    if ($PSBoundParameters.ContainsKey('OutputDirectory')) {
        $parameters.OutputDirectory = $OutputDirectory
    }

    Write-Host ''
    Write-Host 'TwitterClean - análise local do arquivo do X' -ForegroundColor Cyan
    Write-Host 'Lendo o arquivo. Nenhuma ação será executada na sua conta.' -ForegroundColor Gray
    Write-Host ''

    $report = New-TwitterCleanReport @parameters

    Write-Host 'Análise concluída.' -ForegroundColor Green
    Write-Host "Registros lidos:              $($report.ArchiveRecords)"
    Write-Host "Contas/IDs únicos:            $($report.UniqueFollowing)"
    Write-Host "Registros duplicados:         $($report.DuplicateRecords)"
    Write-Host "Sem userLink no arquivo:      $($report.MissingArchiveLinks)"
    Write-Host ''
    Write-Host "Relatório HTML: $($report.HtmlPath)" -ForegroundColor Cyan
    Write-Host "Planilha CSV:   $($report.CsvPath)"
    Write-Host "Dados JSON:     $($report.JsonPath)"
    Write-Host ''

    if (-not $NoOpenReport) {
        Start-Process -FilePath $report.HtmlPath
    }
}
catch {
    Write-Error $_
    exit 1
}
