[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('install', 'update', 'status', 'start', 'stop', 'logs', 'hermes-setup', 'uninstall', 'package')]
    [string]$Action = 'status',

    [string]$DistroName,
    [string]$WslUser,
    [string]$InstallRoot,
    [string]$ProgramRoot,
    [string]$ClawPanelAssetUrl,
    [string]$PackageOutput,

    [switch]$SkipClawPanel,
    [switch]$SkipDocker,
    [switch]$SkipHermes,
    [switch]$NoStartupTask,
    [switch]$RemoveDistro,
    [switch]$RemoveProgramFiles,
    [switch]$RemoveClawPanelData,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repoRoot 'scripts\lib\AgentSystem.psm1'
Import-Module $modulePath -Force -DisableNameChecking

$common = @{
    DistroName  = $DistroName
    WslUser     = $WslUser
    InstallRoot = $InstallRoot
    ProgramRoot = $ProgramRoot
}

switch ($Action) {
    'install' {
        Install-AgentSystem @common `
            -ClawPanelAssetUrl $ClawPanelAssetUrl `
            -SkipClawPanel:$SkipClawPanel `
            -SkipDocker:$SkipDocker `
            -SkipHermes:$SkipHermes `
            -NoStartupTask:$NoStartupTask `
            -Force:$Force
    }
    'update' {
        Update-AgentSystem @common `
            -ClawPanelAssetUrl $ClawPanelAssetUrl `
            -SkipClawPanel:$SkipClawPanel `
            -SkipDocker:$SkipDocker `
            -SkipHermes:$SkipHermes `
            -Force:$Force
    }
    'status' {
        Get-AgentSystemStatus @common
    }
    'start' {
        Start-AgentSystem @common
    }
    'stop' {
        Stop-AgentSystem @common
    }
    'logs' {
        Get-AgentSystemLogs @common
    }
    'hermes-setup' {
        Invoke-HermesSetup @common
    }
    'uninstall' {
        Uninstall-AgentSystem @common `
            -RemoveDistro:$RemoveDistro `
            -RemoveProgramFiles:$RemoveProgramFiles `
            -RemoveClawPanelData:$RemoveClawPanelData
    }
    'package' {
        Build-AgentSystemPackage -OutputPath $PackageOutput
    }
}
