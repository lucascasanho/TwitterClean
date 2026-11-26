#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string[]]$ArchivePath,

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
    Write-Host 'TwitterClean - análise local dos arquivos do X' -ForegroundColor Cyan
    Write-Host 'Nenhuma conexão com o X será feita. Nenhuma senha ou token será solicitado.' -ForegroundColor Gray
    Write-Host "Origens informadas: $($ArchivePath.Count)"
    Write-Host ''

    $report = New-TwitterCleanReport @parameters

    Write-Host 'Análise concluída.' -ForegroundColor Green
    Write-Host "Arquivos following.js encontrados: $($report.FollowingFilesFound)"
    Write-Host "Registros lidos:                   $($report.ArchiveRecords)"
    Write-Host "IDs únicos reunidos:               $($report.UniqueFollowing)"
    Write-Host "Registros duplicados:              $($report.DuplicateRecords)"
    Write-Host "Sem link válido no arquivo:        $($report.MissingArchiveLinks)"
    Write-Host "IDs encontrados em uma origem:     $($report.ArchiveSourceOnlyAccounts)"

    if ($null -ne $report.UnmatchedFollowingCount) {
        Write-Host "Contador sem ID correspondente:     $($report.UnmatchedFollowingCount)"
        Write-Host "IDs históricos acima do contador:  $($report.ArchiveCountExcess)"
    }

    Write-Host ''
    Write-Host "Relatório HTML:       $($report.HtmlPath)" -ForegroundColor Cyan
    Write-Host "Lista consolidada:   $($report.CsvPath)"
    Write-Host "Comparação de fontes: $($report.ComparisonCsvPath)"
    Write-Host "IDs exclusivos:      $($report.ExclusiveIdsCsvPath)"
    Write-Host "Dados JSON:          $($report.JsonPath)"
    Write-Host ''

    if (-not $NoOpenReport) {
        Start-Process -FilePath $report.HtmlPath
    }
}
catch {
    Write-Error $_
    exit 1
}
