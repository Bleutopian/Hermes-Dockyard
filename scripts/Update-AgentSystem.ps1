[CmdletBinding()]
param(
    [string]$DistroName,
    [string]$WslUser,
    [string]$InstallRoot,
    [string]$ProgramRoot,
    [string]$ClawPanelAssetUrl,
    [switch]$SkipClawPanel,
    [switch]$SkipDocker,
    [switch]$SkipHermes,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repoRoot 'scripts\lib\AgentSystem.psm1') -Force -DisableNameChecking

Update-AgentSystem `
    -DistroName $DistroName `
    -WslUser $WslUser `
    -InstallRoot $InstallRoot `
    -ProgramRoot $ProgramRoot `
    -ClawPanelAssetUrl $ClawPanelAssetUrl `
    -SkipClawPanel:$SkipClawPanel `
    -SkipDocker:$SkipDocker `
    -SkipHermes:$SkipHermes `
    -Force:$Force
