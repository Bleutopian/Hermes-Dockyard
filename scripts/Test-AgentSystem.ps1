[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repoRoot 'scripts\lib\AgentSystem.psm1') -Force -DisableNameChecking

Test-AgentSystemProject
& (Join-Path $repoRoot 'tests\powershell\Test-AgentSystemJson.ps1')
& (Join-Path $repoRoot 'tests\powershell\Test-AgentSystemInitialLanes.ps1')
& (Join-Path $repoRoot 'tests\powershell\Test-AgentSystemRepairProof.ps1')
