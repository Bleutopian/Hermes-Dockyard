[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repoRoot 'scripts\lib\AgentSystem.psm1') -Force -DisableNameChecking

Test-AgentSystemProject

$testRoot = Join-Path $repoRoot 'tests\powershell'
$failures = New-Object System.Collections.Generic.List[string]
if (Test-Path -LiteralPath $testRoot) {
    Get-ChildItem -LiteralPath $testRoot -Filter 'Test-*.ps1' -File |
        Sort-Object Name |
        ForEach-Object {
            Write-Host ("Running {0}" -f $_.Name)
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $_.FullName
            if ($LASTEXITCODE -ne 0) {
                $failures.Add($_.FullName)
            }
        }
}

if ($failures.Count -gt 0) {
    throw ((@('One or more test scripts failed:') + ($failures | ForEach-Object { "- $_" })) -join [Environment]::NewLine)
}
