[CmdletBinding()]
param(
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repoRoot 'scripts\lib\AgentSystem.psm1') -Force -DisableNameChecking

Build-AgentSystemPackage -OutputPath $OutputPath
