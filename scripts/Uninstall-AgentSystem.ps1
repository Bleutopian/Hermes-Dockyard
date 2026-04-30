[CmdletBinding()]
param(
    [string]$DistroName,
    [string]$WslUser,
    [string]$InstallRoot,
    [string]$ProgramRoot,
    [switch]$RemoveDistro,
    [switch]$RemoveProgramFiles,
    [switch]$RemoveClawPanelData
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repoRoot 'scripts\lib\AgentSystem.psm1') -Force -DisableNameChecking

Uninstall-AgentSystem `
    -DistroName $DistroName `
    -WslUser $WslUser `
    -InstallRoot $InstallRoot `
    -ProgramRoot $ProgramRoot `
    -RemoveDistro:$RemoveDistro `
    -RemoveProgramFiles:$RemoveProgramFiles `
    -RemoveClawPanelData:$RemoveClawPanelData
