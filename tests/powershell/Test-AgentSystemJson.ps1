[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Equal {
    param(
        [Parameter(Mandatory)]$Expected,
        [Parameter(Mandatory)]$Actual,
        [Parameter(Mandatory)][string]$Message
    )

    if ($Expected -ne $Actual) {
        throw "$Message`nExpected: $Expected`nActual:   $Actual"
    }
}

function Invoke-AgentJsonAction {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][string]$ProbePath
    )

    $previousConfig = $env:AGENT_SYSTEM_CONFIG_PATH
    $previousProbe = $env:AGENT_SYSTEM_TEST_PROBE_PATH

    try {
        $env:AGENT_SYSTEM_CONFIG_PATH = $ConfigPath
        $env:AGENT_SYSTEM_TEST_PROBE_PATH = $ProbePath
        $json = & (Join-Path $RepoRoot 'bin\agent-system.ps1') $Action -OutputFormat json
        return ($json | ConvertFrom-Json)
    }
    finally {
        $env:AGENT_SYSTEM_CONFIG_PATH = $previousConfig
        $env:AGENT_SYSTEM_TEST_PROBE_PATH = $previousProbe
    }
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tempRoot = Join-Path $env:TEMP ("agent-system-json-tests-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
    $configPath = Join-Path $tempRoot 'agent-system.json'
    $config = [ordered]@{
        distroName       = 'Ubuntu-24.04'
        wslUser          = 'agent'
        installRoot      = 'C:\Temp\AgentSystem'
        programRoot      = 'C:\Program Files\AgentSystem'
        taskName         = 'AgentSystem-WSL-Startup'
        clawPanelRepo    = 'qingchencloud/clawpanel'
        hermesInstallUrl = 'https://example.invalid/install.sh'
    }
    $config | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $configPath -Encoding UTF8

    $probeDir = Join-Path $tempRoot 'probes'
    New-Item -ItemType Directory -Path $probeDir -Force | Out-Null

    $noWslPath = Join-Path $probeDir 'no-wsl.json'
    [ordered]@{
        wslDistros        = @()
        distroPresent     = $false
        payloadInstalled  = $false
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $noWslPath -Encoding UTF8

    $payloadMissingPath = Join-Path $probeDir 'payload-missing.json'
    [ordered]@{
        wslDistros        = @('Ubuntu-24.04')
        distroPresent     = $true
        payloadInstalled  = $false
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $payloadMissingPath -Encoding UTF8

    $partialPayloadPath = Join-Path $probeDir 'payload-partial.json'
    [ordered]@{
        wslDistros           = @('Ubuntu-24.04')
        distroPresent        = $true
        payloadInstalled     = $true
        restartRequired      = $false
        systemdActive        = $true
        ubuntuDescription    = 'Ubuntu 24.04.1 LTS'
        dockerInstalled      = $true
        dockerDaemonRunning  = $false
        hermesInstalled      = $true
        hermesGatewayRunning = $false
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $partialPayloadPath -Encoding UTF8

    $statusNoWsl = Invoke-AgentJsonAction -RepoRoot $repoRoot -Action 'status' -ConfigPath $configPath -ProbePath $noWslPath
    Assert-Equal -Expected 'status' -Actual $statusNoWsl.operation -Message 'status JSON should identify the operation.'
    Assert-Equal -Expected 'blocked' -Actual $statusNoWsl.state -Message 'No-WSL status should be blocked.'
    Assert-True -Condition ($statusNoWsl.error_codes -contains 'WSL_MISSING') -Message 'No-WSL status should include WSL_MISSING.'

    $preflightNoWsl = Invoke-AgentJsonAction -RepoRoot $repoRoot -Action 'preflight' -ConfigPath $configPath -ProbePath $noWslPath
    Assert-Equal -Expected 'preflight' -Actual $preflightNoWsl.operation -Message 'preflight JSON should identify the operation.'
    Assert-True -Condition (-not $preflightNoWsl.mutates_system) -Message 'Preflight must remain non-mutating.'
    Assert-Equal -Expected 'install' -Actual $preflightNoWsl.recommended_actions[0].label -Message 'No-WSL preflight should recommend install.'

    $statusPayloadMissing = Invoke-AgentJsonAction -RepoRoot $repoRoot -Action 'status' -ConfigPath $configPath -ProbePath $payloadMissingPath
    Assert-Equal -Expected 'blocked' -Actual $statusPayloadMissing.state -Message 'Payload-missing status should be blocked.'
    Assert-True -Condition ($statusPayloadMissing.error_codes -contains 'PAYLOAD_NOT_INSTALLED') -Message 'Payload-missing status should include PAYLOAD_NOT_INSTALLED.'

    $statusPartial = Invoke-AgentJsonAction -RepoRoot $repoRoot -Action 'status' -ConfigPath $configPath -ProbePath $partialPayloadPath
    Assert-Equal -Expected 'warning' -Actual $statusPartial.state -Message 'Partial payload status should degrade to warning.'
    Assert-True -Condition ($statusPartial.error_codes -contains 'DOCKER_DAEMON_FAILED') -Message 'Partial payload status should include DOCKER_DAEMON_FAILED when Docker is down.'
    Assert-True -Condition ($statusPartial.environment.hermes_installed) -Message 'Partial payload status should preserve Hermes probe data.'

    $preflightPartial = Invoke-AgentJsonAction -RepoRoot $repoRoot -Action 'preflight' -ConfigPath $configPath -ProbePath $partialPayloadPath
    Assert-True -Condition $preflightPartial.ready_for.start -Message 'Partial payload preflight should still allow start guidance.'
    Assert-Equal -Expected 'start' -Actual $preflightPartial.recommended_actions[0].label -Message 'Partial payload preflight should recommend start when not blocked.'

    $schemaPath = Join-Path $repoRoot 'schemas\operation.schema.json'
    $schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
    $eventEnum = @($schema.'$defs'.eventType.enum)
    $errorEnum = @($schema.'$defs'.errorCode.enum)
    Assert-True -Condition ($eventEnum -contains 'operation_started') -Message 'Schema should declare operation_started.'
    Assert-True -Condition ($eventEnum -contains 'operation_completed') -Message 'Schema should declare operation_completed.'
    Assert-True -Condition ($errorEnum -contains 'WSL_MISSING') -Message 'Schema should declare WSL_MISSING.'
    Assert-True -Condition ($errorEnum -contains 'PAYLOAD_NOT_INSTALLED') -Message 'Schema should declare PAYLOAD_NOT_INSTALLED.'

    Write-Host 'Test-AgentSystemJson passed.'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
