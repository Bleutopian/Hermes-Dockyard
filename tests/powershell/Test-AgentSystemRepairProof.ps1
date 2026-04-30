[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$bin = Join-Path $repoRoot 'bin\agent-system.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("AgentSystem-RepairProof-" + [Guid]::NewGuid().ToString('N'))
$installRoot = Join-Path $tempRoot 'ProgramData'
$programRoot = Join-Path $tempRoot 'ProgramFiles'
$operationId = 'repair-proof-001'

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function ConvertFrom-JsonLines {
    param([string[]]$Lines)

    @($Lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
        $_ | ConvertFrom-Json
    })
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    $rootRejected = $false
    try {
        $null = & $bin repair-local-resources `
            -InstallRoot $installRoot `
            -ProgramRoot $programRoot `
            -OutputFormat json `
            -OperationId 'repair-proof-root-reject' 2>&1
    }
    catch {
        $rootRejected = $true
        Assert-True ($_.Exception.Message -match 'AllowTestRootOverride') 'Custom repair roots should require an explicit test override.'
    }
    Assert-True $rootRejected 'Expected custom repair roots to be rejected without test override.'

    $interrupted = $false
    try {
        $null = & $bin repair-local-resources `
            -InstallRoot $installRoot `
            -ProgramRoot $programRoot `
            -OutputFormat json `
            -OperationId $operationId `
            -AllowTestRootOverride `
            -SimulateInterruptAfterPhase copy-bundled-resources 2>&1
    }
    catch {
        $interrupted = $true
        Assert-True ($_.Exception.Message -match 'Simulated interruption') 'Expected simulated interruption to be reported.'
    }
    Assert-True $interrupted 'Expected repair-local-resources to stop during simulated interruption.'

    $checkpointPath = Join-Path $installRoot "state\operations\$operationId.json"
    $auditLogPath = Join-Path $installRoot 'logs\operations.jsonl'
    $manifestPath = Join-Path $installRoot 'state\resource-manifest.json'

    Assert-True (Test-Path -LiteralPath $checkpointPath) 'Interrupted operation should write a checkpoint.'
    $interruptedCheckpoint = Get-Content -LiteralPath $checkpointPath -Raw | ConvertFrom-Json
    Assert-True ($interruptedCheckpoint.status -eq 'failed') 'Interrupted checkpoint should be failed.'
    Assert-True ($interruptedCheckpoint.phase.name -eq 'copy-bundled-resources') 'Interrupted checkpoint should preserve the last completed phase.'
    Assert-True ($interruptedCheckpoint.phase.status -eq 'completed') 'Interrupted checkpoint should mark copy-bundled-resources as completed.'
    Assert-True ($interruptedCheckpoint.last_error_code -eq 'OPERATION_INTERRUPTED') 'Interrupted checkpoint should use a stable interruption code.'
    Assert-True ($interruptedCheckpoint.recovery_action.action -eq 'resume') 'Interrupted checkpoint should recommend resume.'
    Assert-True ($interruptedCheckpoint.resume_command -match $operationId) 'Checkpoint resume command should include the operation id.'

    $resumeOutput = & $bin repair-local-resources `
        -InstallRoot $installRoot `
        -ProgramRoot $programRoot `
        -OutputFormat json `
        -OperationId $operationId `
        -AllowTestRootOverride `
        -Resume

    $events = ConvertFrom-JsonLines -Lines $resumeOutput
    Assert-True (@($events | Where-Object { $_.event -eq 'operation_completed' }).Count -eq 1) 'Resume should emit one operation_completed event.'
    Assert-True (@($events | Where-Object { $_.phase -eq 'copy-bundled-resources' -and $_.status -eq 'skipped' }).Count -eq 1) 'Resume should skip the already completed copy-bundled-resources phase.'
    Assert-True (@($events | Where-Object { $_.message -match '^Copied ' }).Count -eq 0) 'Resume should not rerun the copy phase after a completed copy checkpoint.'

    foreach ($path in @(
            'bin\agent-system.ps1',
            'config\agent-system.json',
            'config\release-metadata.json',
            'schemas\operation.schema.json',
            'schemas\checkpoint.schema.json',
            'scripts\lib\AgentSystem.psm1',
            'wsl\bootstrap-ubuntu.sh',
            'agent-system.cmd'
        )) {
        Assert-True (Test-Path -LiteralPath (Join-Path $programRoot $path)) "Expected repaired resource: $path"
    }

    Assert-True (Test-Path -LiteralPath $manifestPath) 'Repair should write resource manifest.'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    Assert-True ($manifest.operation_id -eq $operationId) 'Manifest should preserve operation id.'
    Assert-True ($manifest.release.signing_status -eq 'unsigned-internal-only') 'Manifest should include unsigned internal alpha status.'
    Assert-True (@($manifest.resources | Where-Object { $_.relative_path -eq 'bin/agent-system.ps1' }).Count -eq 1) 'Manifest should include bin/agent-system.ps1.'
    Assert-True (@($manifest.resources | Where-Object { "$($_.relative_path)" -match '^//wsl|wsl\.localhost|ext4\.vhdx' }).Count -eq 0) 'Manifest should not include WSL distro data paths.'

    $completedCheckpoint = Get-Content -LiteralPath $checkpointPath -Raw | ConvertFrom-Json
    Assert-True ($completedCheckpoint.status -eq 'completed') 'Resume should complete the checkpoint.'
    Assert-True ($completedCheckpoint.phase.name -eq 'finalize-operation') 'Completed checkpoint should be on finalize-operation phase.'
    Assert-True ($completedCheckpoint.requires_elevation -eq $false) 'Temporary repair proof should not require elevation.'
    Assert-True ($completedCheckpoint.reboot_required -eq $false) 'Repair proof should not require reboot.'

    Assert-True (Test-Path -LiteralPath $auditLogPath) 'Repair should write audit log.'
    $auditEvents = @(Get-Content -LiteralPath $auditLogPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json })
    foreach ($phase in @('copy-bundled-resources', 'write-resource-manifest', 'verify-target-layout', 'finalize-operation')) {
        Assert-True (@($auditEvents | Where-Object { $_.phase -eq $phase }).Count -ge 1) "Audit log should include phase: $phase"
    }
    Assert-True (@($auditEvents | Where-Object { $_.operation_id -eq $operationId -and $_.caller -eq 'cli' -and $_.elapsed_ms -ge 0 -and $null -ne $_.requires_elevation }).Count -ge 1) 'Audit log should include operation id, caller, elevation, result, and elapsed time.'
    Assert-True (@($auditEvents | Where-Object { $_.phase -eq 'copy-bundled-resources' -and $_.result -eq 'completed' }).Count -eq 1) 'Copy phase should complete exactly once across interrupt and resume.'
    Assert-True (@($auditEvents | Where-Object { $_.result -eq 'failed' -and $_.error_code -eq 'OPERATION_INTERRUPTED' }).Count -eq 1) 'Failure audit row should include stable error code.'
    Assert-True (@($auditEvents | Where-Object { $_.phase -eq 'finalize-operation' -and $_.resource_manifest_path -eq $manifestPath -and $_.target_root -eq $programRoot }).Count -eq 1) 'Completion audit should include final artifact paths.'

    $tauriConfig = Get-Content -LiteralPath (Join-Path $repoRoot 'apps\desktop\src-tauri\tauri.conf.json') -Raw | ConvertFrom-Json
    Assert-True ($tauriConfig.bundle.targets -contains 'nsis') 'Tauri alpha bundle should target NSIS.'
    foreach ($target in @('resources/bin', 'resources/config', 'resources/schemas', 'resources/scripts', 'resources/wsl')) {
        $resourceTargets = @($tauriConfig.bundle.resources.PSObject.Properties | ForEach-Object { $_.Value })
        Assert-True ($resourceTargets -contains $target) "Tauri resources should include target: $target"
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Write-Host 'Test-AgentSystemRepairProof passed.'
