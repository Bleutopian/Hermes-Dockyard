[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('install', 'update', 'status', 'preflight', 'start', 'stop', 'logs', 'hermes-setup', 'uninstall', 'package')]
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
    [switch]$Force,

    [ValidateSet('text', 'json')]
    [string]$OutputFormat = 'text'
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

function New-AgentCliEvent {
    param(
        [Parameter(Mandatory)][string]$Type,
        [Parameter(Mandatory)][string]$ActionName,
        [string]$OperationId,
        [string]$Message,
        [string]$ErrorCode
    )

    $record = [ordered]@{
        '$schema'      = './schemas/operation.schema.json'
        schema_version = '1.0'
        operation      = $ActionName
        event          = $Type
        timestamp      = (Get-Date).ToUniversalTime().ToString('o')
    }

    if ($OperationId) {
        $record.operation_id = $OperationId
    }

    if ($Message) {
        $record.message = $Message
    }

    if ($ErrorCode) {
        $record.error_code = $ErrorCode
    }

    return [pscustomobject]$record
}

function Write-AgentCliJsonEvent {
    param(
        [Parameter(Mandatory)][string]$Type,
        [Parameter(Mandatory)][string]$ActionName,
        [string]$OperationId,
        [string]$Message,
        [string]$ErrorCode
    )

    (New-AgentCliEvent -Type $Type -ActionName $ActionName -OperationId $OperationId -Message $Message -ErrorCode $ErrorCode) |
        ConvertTo-Json -Compress -Depth 6
}

function Get-AgentCliErrorCode {
    param([Parameter(Mandatory)]$ErrorRecord)

    $message = "$($ErrorRecord.Exception.Message)"
    if ($message -match 'elevated PowerShell session|Administrator') { return 'PERMISSION_REQUIRED' }
    if ($message -match 'reboot') { return 'REBOOT_REQUIRED' }
    if ($message -match 'WSL|wsl\.exe') { return 'WSL_MISSING' }
    if ($message -match 'Docker') { return 'DOCKER_DAEMON_FAILED' }
    if ($message -match 'payload is not installed') { return 'PAYLOAD_NOT_INSTALLED' }
    if ($message -match 'ClawPanel') { return 'CLAWPANEL_ASSET_MISSING' }
    return 'error'
}

function ConvertTo-AgentCliMessage {
    param($Record)

    if ($null -eq $Record) {
        return $null
    }

    if ($Record -is [System.Management.Automation.ErrorRecord]) {
        return $Record.Exception.Message
    }

    if ($Record -is [System.Management.Automation.InformationRecord]) {
        return "$($Record.MessageData)"
    }

    if ($Record -is [System.Management.Automation.WarningRecord]) {
        return "$($Record.Message)"
    }

    if ($Record -is [System.Management.Automation.VerboseRecord]) {
        return "$($Record.Message)"
    }

    if ($Record -is [System.Management.Automation.DebugRecord]) {
        return "$($Record.Message)"
    }

    return "$Record"
}

function Invoke-AgentCliAction {
    param(
        [Parameter(Mandatory)][string]$ActionName,
        [Parameter(Mandatory)][scriptblock]$Script
    )

    if ($OutputFormat -ne 'json') {
        & $Script
        return
    }

    $operationId = [guid]::NewGuid().Guid
    Write-Output (Write-AgentCliJsonEvent -Type 'operation_started' -ActionName $ActionName -OperationId $operationId -Message "Starting $ActionName.")
    try {
        $records = & $Script *>&1
        foreach ($record in @($records)) {
            $message = ConvertTo-AgentCliMessage -Record $record
            if (-not [string]::IsNullOrWhiteSpace($message)) {
                Write-Output (Write-AgentCliJsonEvent -Type 'progress' -ActionName $ActionName -OperationId $operationId -Message $message)
            }
        }
        Write-Output (Write-AgentCliJsonEvent -Type 'operation_completed' -ActionName $ActionName -OperationId $operationId -Message "$ActionName completed.")
    }
    catch {
        $errorCode = Get-AgentCliErrorCode -ErrorRecord $_
        Write-Output (Write-AgentCliJsonEvent -Type 'error' -ActionName $ActionName -OperationId $operationId -Message $_.Exception.Message -ErrorCode $errorCode)
        throw
    }
}

switch ($Action) {
    'install' {
        Invoke-AgentCliAction -ActionName 'install' -Script {
            Install-AgentSystem @common `
                -ClawPanelAssetUrl $ClawPanelAssetUrl `
                -SkipClawPanel:$SkipClawPanel `
                -SkipDocker:$SkipDocker `
                -SkipHermes:$SkipHermes `
                -NoStartupTask:$NoStartupTask `
                -Force:$Force
        }
    }
    'update' {
        Invoke-AgentCliAction -ActionName 'update' -Script {
            Update-AgentSystem @common `
                -ClawPanelAssetUrl $ClawPanelAssetUrl `
                -SkipClawPanel:$SkipClawPanel `
                -SkipDocker:$SkipDocker `
                -SkipHermes:$SkipHermes `
                -Force:$Force
        }
    }
    'status' {
        Get-AgentSystemStatus @common -OutputFormat $OutputFormat
    }
    'preflight' {
        Invoke-AgentSystemPreflight @common -OutputFormat $OutputFormat
    }
    'start' {
        Invoke-AgentCliAction -ActionName 'start' -Script {
            Start-AgentSystem @common
        }
    }
    'stop' {
        Invoke-AgentCliAction -ActionName 'stop' -Script {
            Stop-AgentSystem @common
        }
    }
    'logs' {
        Invoke-AgentCliAction -ActionName 'logs' -Script {
            Get-AgentSystemLogs @common
        }
    }
    'hermes-setup' {
        Invoke-AgentCliAction -ActionName 'hermes-setup' -Script {
            Invoke-HermesSetup @common
        }
    }
    'uninstall' {
        Invoke-AgentCliAction -ActionName 'uninstall' -Script {
            Uninstall-AgentSystem @common `
                -RemoveDistro:$RemoveDistro `
                -RemoveProgramFiles:$RemoveProgramFiles `
                -RemoveClawPanelData:$RemoveClawPanelData
        }
    }
    'package' {
        Invoke-AgentCliAction -ActionName 'package' -Script {
            Build-AgentSystemPackage -OutputPath $PackageOutput
        }
    }
}
