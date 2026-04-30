Set-StrictMode -Version Latest

function Get-AgentSystemSourceRoot {
    return (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
}

function Expand-AgentPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    return [Environment]::ExpandEnvironmentVariables($Path)
}

function ConvertTo-AgentIsoTimestamp {
    return (Get-Date).ToUniversalTime().ToString('o')
}

function Get-AgentObjectPropertyValue {
    param(
        [Parameter(Mandatory)]$InputObject,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )

    if ($null -eq $InputObject) {
        return $Default
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $Default
    }

    return $property.Value
}

function Get-AgentSystemConfig {
    [CmdletBinding()]
    param(
        [string]$DistroName,
        [string]$WslUser,
        [string]$InstallRoot,
        [string]$ProgramRoot
    )

    $sourceRoot = Get-AgentSystemSourceRoot
    $configPath = if ($env:AGENT_SYSTEM_CONFIG_PATH) {
        $env:AGENT_SYSTEM_CONFIG_PATH
    }
    else {
        Join-Path $sourceRoot 'config\agent-system.json'
    }
    if (-not (Test-Path -LiteralPath $configPath)) {
        throw "Missing config file: $configPath"
    }

    $raw = Get-Content -LiteralPath $configPath -Raw
    $json = $raw | ConvertFrom-Json

    $resolvedDistro = if ($DistroName) { $DistroName } else { $json.distroName }
    $resolvedUser = if ($WslUser) { $WslUser } else { $json.wslUser }
    $resolvedInstallRoot = if ($InstallRoot) { $InstallRoot } else { $json.installRoot }
    $resolvedProgramRoot = if ($ProgramRoot) { $ProgramRoot } else { $json.programRoot }

    return [pscustomobject]@{
        SourceRoot       = $sourceRoot
        DistroName      = $resolvedDistro
        WslUser         = $resolvedUser
        InstallRoot     = (Expand-AgentPath $resolvedInstallRoot)
        ProgramRoot     = (Expand-AgentPath $resolvedProgramRoot)
        TaskName        = $json.taskName
        ClawPanelRepo   = $json.clawPanelRepo
        HermesInstallUrl = $json.hermesInstallUrl
    }
}

function Assert-AgentAdministrator {
    if (-not (Test-AgentAdministrator)) {
        throw "This action requires an elevated PowerShell session. Run PowerShell as Administrator."
    }
}

function Test-AgentAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $adminRole = [Security.Principal.WindowsBuiltInRole]::Administrator
    return $principal.IsInRole($adminRole)
}

function Test-AgentPathUnderDirectory {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Directory
    )

    $fullPath = [System.IO.Path]::GetFullPath((Expand-AgentPath $Path)).TrimEnd('\', '/')
    $fullDirectory = [System.IO.Path]::GetFullPath((Expand-AgentPath $Directory)).TrimEnd('\', '/')
    return ($fullPath.Equals($fullDirectory, [StringComparison]::OrdinalIgnoreCase) -or
        $fullPath.StartsWith($fullDirectory + [System.IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
        $fullPath.StartsWith($fullDirectory + [System.IO.Path]::AltDirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase))
}

function Test-AgentProgramRootRequiresElevation {
    param([Parameter(Mandatory)][string]$ProgramRoot)

    $programFiles = [Environment]::GetFolderPath('ProgramFiles')
    $programFilesX86 = [Environment]::GetFolderPath('ProgramFilesX86')

    if ($programFiles -and (Test-AgentPathUnderDirectory -Path $ProgramRoot -Directory $programFiles)) {
        return $true
    }

    if ($programFilesX86 -and (Test-AgentPathUnderDirectory -Path $ProgramRoot -Directory $programFilesX86)) {
        return $true
    }

    return $false
}

function Invoke-AgentNative {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [string[]]$Arguments = @(),

        [switch]$AllowNonZero
    )

    Write-Host ("> {0} {1}" -f $FilePath, ($Arguments -join ' '))
    & $FilePath @Arguments
    $exitCode = $LASTEXITCODE
    if (($exitCode -ne 0) -and (-not $AllowNonZero)) {
        throw "Command failed with exit code ${exitCode}: $FilePath $($Arguments -join ' ')"
    }
    return $exitCode
}

function ConvertFrom-WslListOutput {
    param([string[]]$Lines)

    foreach ($line in $Lines) {
        $clean = ($line -replace [char]0, '').Trim()
        if (-not [string]::IsNullOrWhiteSpace($clean)) {
            $clean
        }
    }
}

function Get-WslDistros {
    $output = & wsl.exe --list --quiet 2>$null
    if ($LASTEXITCODE -ne 0) {
        return @()
    }

    return @(ConvertFrom-WslListOutput $output)
}

function Test-WslDistro {
    param([Parameter(Mandatory)][string]$DistroName)

    $distros = Get-WslDistros
    return ($distros -contains $DistroName)
}

function Invoke-AgentWsl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DistroName,
        [Parameter(Mandatory)][string]$Command,
        [string]$User = 'root',
        [switch]$AllowNonZero
    )

    $args = @('-d', $DistroName, '-u', $User, '--', 'bash', '-lc', $Command)
    Write-Host ("> wsl.exe {0}" -f ($args -join ' '))
    & wsl.exe @args
    $exitCode = $LASTEXITCODE
    if (($exitCode -ne 0) -and (-not $AllowNonZero)) {
        throw "WSL command failed with exit code ${exitCode}: $Command"
    }
    return $exitCode
}

function Test-AgentWslFile {
    param(
        [Parameter(Mandatory)][string]$DistroName,
        [Parameter(Mandatory)][string]$Path
    )

    $quoted = ConvertTo-AgentBashSingleQuoted $Path
    $args = @('-d', $DistroName, '-u', 'root', '--', 'bash', '-lc', "test -f $quoted")
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & wsl.exe @args > $null 2> $null
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    return ($exitCode -eq 0)
}

function Invoke-AgentWslCapture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DistroName,
        [Parameter(Mandatory)][string]$Command,
        [string]$User = 'root'
    )

    $args = @('-d', $DistroName, '-u', $User, '--', 'bash', '-lc', $Command)
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & wsl.exe @args 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output   = @($output | ForEach-Object { "$_" })
    }
}

function Test-AgentWslCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DistroName,
        [Parameter(Mandatory)][string]$Command,
        [string]$User = 'root'
    )

    $result = Invoke-AgentWslCapture -DistroName $DistroName -Command $Command -User $User
    return ($result.ExitCode -eq 0)
}

function Get-AgentSystemProbeState {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config)

    if ($env:AGENT_SYSTEM_TEST_PROBE_PATH) {
        $probePath = $env:AGENT_SYSTEM_TEST_PROBE_PATH
        if (-not (Test-Path -LiteralPath $probePath)) {
            throw "AGENT_SYSTEM_TEST_PROBE_PATH does not exist: $probePath"
        }

        $fixture = Get-Content -LiteralPath $probePath -Raw | ConvertFrom-Json
        $fixtureDistros = @(Get-AgentObjectPropertyValue -InputObject $fixture -Name 'wslDistros' -Default @())
        $fixtureDistroPresent = [bool](Get-AgentObjectPropertyValue -InputObject $fixture -Name 'distroPresent' -Default ($fixtureDistros -contains $Config.DistroName))

        return [pscustomobject]@{
            DistroPresent       = $fixtureDistroPresent
            WslDistros          = $fixtureDistros
            PayloadInstalled    = [bool](Get-AgentObjectPropertyValue -InputObject $fixture -Name 'payloadInstalled' -Default $false)
            RestartRequired     = [bool](Get-AgentObjectPropertyValue -InputObject $fixture -Name 'restartRequired' -Default $false)
            SystemdActive       = [bool](Get-AgentObjectPropertyValue -InputObject $fixture -Name 'systemdActive' -Default $false)
            UbuntuDescription   = [string](Get-AgentObjectPropertyValue -InputObject $fixture -Name 'ubuntuDescription' -Default $null)
            DockerInstalled     = [bool](Get-AgentObjectPropertyValue -InputObject $fixture -Name 'dockerInstalled' -Default $false)
            DockerDaemonRunning = [bool](Get-AgentObjectPropertyValue -InputObject $fixture -Name 'dockerDaemonRunning' -Default $false)
            HermesInstalled     = [bool](Get-AgentObjectPropertyValue -InputObject $fixture -Name 'hermesInstalled' -Default $false)
            HermesGatewayRunning = [bool](Get-AgentObjectPropertyValue -InputObject $fixture -Name 'hermesGatewayRunning' -Default $false)
        }
    }

    $distros = Get-WslDistros
    $distroPresent = $distros -contains $Config.DistroName
    $payloadInstalled = $false
    $restartRequired = $false
    $systemdActive = $false
    $dockerInstalled = $false
    $dockerDaemonRunning = $false
    $hermesInstalled = $false
    $hermesGatewayRunning = $false
    $ubuntuDescription = $null

    if ($distroPresent) {
        $payloadInstalled = Test-AgentWslFile -DistroName $Config.DistroName -Path '/usr/local/bin/agent-system-status'
    }

    if ($payloadInstalled) {
        $restartRequired = Test-AgentWslFile -DistroName $Config.DistroName -Path '/var/lib/agent-system/restart-required'

        $ubuntu = Invoke-AgentWslCapture -DistroName $Config.DistroName -Command 'lsb_release -ds 2>/dev/null || . /etc/os-release && printf "%s\n" "${PRETTY_NAME:-$NAME}"'
        if ($ubuntu.ExitCode -eq 0) {
            $ubuntuDescription = ($ubuntu.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
        }

        $systemdResult = Invoke-AgentWslCapture -DistroName $Config.DistroName -Command 'ps -p 1 -o comm= | tr -d " "'
        if ($systemdResult.ExitCode -eq 0) {
            $systemdActive = (($systemdResult.Output | Select-Object -First 1) -eq 'systemd')
        }

        $dockerInstalled = Test-AgentWslCommand -DistroName $Config.DistroName -Command 'command -v docker >/dev/null 2>&1'
        if ($dockerInstalled) {
            $dockerDaemonRunning = Test-AgentWslCommand -DistroName $Config.DistroName -Command 'docker info >/dev/null 2>&1'
        }

        $user = ConvertTo-AgentBashSingleQuoted $Config.WslUser
        $hermesInnerCheck = 'export PATH="$HOME/.local/bin:$PATH"; command -v hermes >/dev/null 2>&1'
        $hermesCheck = "sudo -H -u $user bash -lc $(ConvertTo-AgentBashSingleQuoted $hermesInnerCheck)"
        $hermesInstalled = Test-AgentWslCommand -DistroName $Config.DistroName -Command $hermesCheck
        if ($hermesInstalled) {
            $gatewayInnerCheck = "tmux has-session -t 'hermes-gateway' 2>/dev/null"
            $gatewayCheck = "sudo -H -u $user bash -lc $(ConvertTo-AgentBashSingleQuoted $gatewayInnerCheck)"
            $hermesGatewayRunning = Test-AgentWslCommand -DistroName $Config.DistroName -Command $gatewayCheck
        }
    }

    return [pscustomobject]@{
        DistroPresent        = $distroPresent
        WslDistros           = @($distros)
        PayloadInstalled     = $payloadInstalled
        RestartRequired      = $restartRequired
        SystemdActive        = $systemdActive
        UbuntuDescription    = $ubuntuDescription
        DockerInstalled      = $dockerInstalled
        DockerDaemonRunning  = $dockerDaemonRunning
        HermesInstalled      = $hermesInstalled
        HermesGatewayRunning = $hermesGatewayRunning
    }
}

function New-AgentSystemCheck {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][string]$Message,
        [string]$ErrorCode,
        $Details = $null
    )

    $record = [ordered]@{
        id      = $Id
        status  = $Status
        message = $Message
    }

    if ($ErrorCode) {
        $record.error_code = $ErrorCode
    }

    if ($null -ne $Details) {
        $record.details = $Details
    }

    return $record
}

function Get-AgentSystemStatusRecord {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config)

    $probe = Get-AgentSystemProbeState -Config $Config
    $checks = New-Object System.Collections.Generic.List[object]
    $errorCodes = New-Object System.Collections.Generic.List[string]
    $state = 'ready'
    $summary = 'Agent payload is installed and ready for read-only checks.'

    if (-not $probe.DistroPresent) {
        $checks.Add((New-AgentSystemCheck -Id 'wsl_distro' -Status 'fail' -Message 'WSL distro is not installed.' -ErrorCode 'WSL_MISSING' -Details @{ distro = $Config.DistroName }))
        $errorCodes.Add('WSL_MISSING')
        $state = 'blocked'
        $summary = 'WSL distro is not installed.'
    }
    else {
        $checks.Add((New-AgentSystemCheck -Id 'wsl_distro' -Status 'pass' -Message 'WSL distro is installed.' -Details @{ distro = $Config.DistroName }))

        if (-not $probe.PayloadInstalled) {
            $checks.Add((New-AgentSystemCheck -Id 'payload' -Status 'fail' -Message 'WSL distro exists, but the Agent payload is not installed yet.' -ErrorCode 'PAYLOAD_NOT_INSTALLED'))
            $errorCodes.Add('PAYLOAD_NOT_INSTALLED')
            $state = 'blocked'
            $summary = 'WSL distro exists, but the Agent payload is not installed yet.'
        }
        else {
            $checks.Add((New-AgentSystemCheck -Id 'payload' -Status 'pass' -Message 'Agent payload is installed inside the WSL distro.'))

            if ($probe.RestartRequired) {
                $checks.Add((New-AgentSystemCheck -Id 'restart_required' -Status 'warn' -Message 'A WSL restart is required before the payload is fully active.' -ErrorCode 'REBOOT_REQUIRED'))
                $errorCodes.Add('REBOOT_REQUIRED')
                if ($state -eq 'ready') {
                    $state = 'warning'
                }
                $summary = 'Agent payload is installed, but a WSL restart is still required.'
            }
            else {
                $checks.Add((New-AgentSystemCheck -Id 'restart_required' -Status 'pass' -Message 'No WSL restart is pending.'))
            }

            if ($probe.DockerInstalled) {
                if ($probe.DockerDaemonRunning) {
                    $checks.Add((New-AgentSystemCheck -Id 'docker_daemon' -Status 'pass' -Message 'Docker is installed and the daemon is reachable.'))
                }
                else {
                    $checks.Add((New-AgentSystemCheck -Id 'docker_daemon' -Status 'warn' -Message 'Docker is installed, but the daemon is not reachable.' -ErrorCode 'DOCKER_DAEMON_FAILED'))
                    $errorCodes.Add('DOCKER_DAEMON_FAILED')
                    if ($state -eq 'ready') {
                        $state = 'warning'
                    }
                    if ($summary -eq 'Agent payload is installed and ready for read-only checks.') {
                        $summary = 'Agent payload is installed, but Docker is not ready.'
                    }
                }
            }
            else {
                $checks.Add((New-AgentSystemCheck -Id 'docker_daemon' -Status 'warn' -Message 'Docker is not installed in the WSL distro.'))
                if ($state -eq 'ready') {
                    $state = 'warning'
                }
            }

            if ($probe.HermesInstalled) {
                $gatewayStatus = if ($probe.HermesGatewayRunning) { 'pass' } else { 'warn' }
                $gatewayMessage = if ($probe.HermesGatewayRunning) {
                    'Hermes is installed and the gateway tmux session is running.'
                }
                else {
                    'Hermes is installed, but the gateway tmux session is not running.'
                }
                $checks.Add((New-AgentSystemCheck -Id 'hermes_gateway' -Status $gatewayStatus -Message $gatewayMessage))
                if (($gatewayStatus -eq 'warn') -and ($state -eq 'ready')) {
                    $state = 'warning'
                }
            }
            else {
                $checks.Add((New-AgentSystemCheck -Id 'hermes_gateway' -Status 'warn' -Message 'Hermes is not installed in the WSL distro.'))
                if ($state -eq 'ready') {
                    $state = 'warning'
                }
            }
        }
    }

    $uniqueErrorCodes = [object[]]($errorCodes.ToArray() | Select-Object -Unique)
    $checkRecords = [object[]]$checks.ToArray()

    return [ordered]@{
        '$schema'       = './schemas/operation.schema.json'
        schema_version  = '1.0'
        operation       = 'status'
        generated_at    = (ConvertTo-AgentIsoTimestamp)
        state           = $state
        summary         = $summary
        error_codes     = $uniqueErrorCodes
        config          = [ordered]@{
            distro_name  = $Config.DistroName
            wsl_user     = $Config.WslUser
            install_root = $Config.InstallRoot
            program_root = $Config.ProgramRoot
            task_name    = $Config.TaskName
        }
        environment     = [ordered]@{
            ubuntu_description    = $probe.UbuntuDescription
            systemd_active        = $probe.SystemdActive
            docker_installed      = $probe.DockerInstalled
            docker_daemon_running = $probe.DockerDaemonRunning
            hermes_installed      = $probe.HermesInstalled
            hermes_gateway_running = $probe.HermesGatewayRunning
            restart_required      = $probe.RestartRequired
        }
        checks          = $checkRecords
    }
}

function Get-AgentSystemPreflightRecord {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config)

    $statusRecord = Get-AgentSystemStatusRecord -Config $Config
    $recommendedActions = New-Object System.Collections.Generic.List[object]

    if ($statusRecord.error_codes -contains 'WSL_MISSING') {
        $recommendedActions.Add([ordered]@{
            label              = 'install'
            command            = '.\scripts\Install-AgentSystem.ps1'
            requires_elevation = $true
            reason             = 'Install WSL, the Ubuntu distro, and the Agent payload.'
        })
    }
    elseif ($statusRecord.error_codes -contains 'PAYLOAD_NOT_INSTALLED') {
        $recommendedActions.Add([ordered]@{
            label              = 'install'
            command            = '.\scripts\Install-AgentSystem.ps1'
            requires_elevation = $true
            reason             = 'Install the Agent payload into the existing WSL distro.'
        })
    }
    elseif ($statusRecord.error_codes -contains 'REBOOT_REQUIRED') {
        $recommendedActions.Add([ordered]@{
            label              = 'resume_after_reboot'
            command            = '.\scripts\Install-AgentSystem.ps1'
            requires_elevation = $true
            reason             = 'Restart WSL or Windows, then rerun the installer to finish activation.'
        })
    }
    else {
        $recommendedActions.Add([ordered]@{
            label              = 'start'
            command            = '.\bin\agent-system.ps1 start'
            requires_elevation = $false
            reason             = 'The read-only checks passed; the services can be started if needed.'
        })
    }

    $recommendedActionRecords = [object[]]$recommendedActions.ToArray()

    return [ordered]@{
        '$schema'            = './schemas/operation.schema.json'
        schema_version       = '1.0'
        operation            = 'preflight'
        generated_at         = (ConvertTo-AgentIsoTimestamp)
        state                = $statusRecord.state
        summary              = $statusRecord.summary
        mutates_system       = $false
        ready_for            = [ordered]@{
            read_only_checks = $true
            install          = $true
            start            = ($statusRecord.state -ne 'blocked')
        }
        recommended_actions  = $recommendedActionRecords
        error_codes          = $statusRecord.error_codes
        config               = $statusRecord.config
        environment          = $statusRecord.environment
        checks               = $statusRecord.checks
    }
}

function Write-AgentSystemPreflightText {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Record)

    Write-Host 'Agent System Preflight'
    Write-Host "  State:   $($Record.state)"
    Write-Host "  Summary: $($Record.summary)"
    Write-Host ''
    Write-Host 'Checks:'
    foreach ($check in $Record.checks) {
        $suffix = if ($check.PSObject.Properties['error_code']) { " [$($check.error_code)]" } else { '' }
        Write-Host ("  - {0}: {1}{2}" -f $check.id, $check.message, $suffix)
    }
    Write-Host ''
    Write-Host 'Recommended actions:'
    foreach ($action in $Record.recommended_actions) {
        $elevation = if ($action.requires_elevation) { 'elevated' } else { 'standard' }
        Write-Host ("  - {0} ({1}): {2}" -f $action.command, $elevation, $action.reason)
    }
}

function ConvertTo-AgentBashSingleQuoted {
    param([Parameter(Mandatory)][string]$Value)

    return "'" + ($Value -replace "'", "'\''") + "'"
}

function Ensure-AgentDirectories {
    param([Parameter(Mandatory)]$Config)

    New-Item -ItemType Directory -Path $Config.InstallRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $Config.ProgramRoot -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Config.InstallRoot 'downloads') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Config.InstallRoot 'logs') -Force | Out-Null
}

function Get-AgentLocalResourceItems {
    return @('bin', 'config', 'docker', 'docs', 'packaging', 'schemas', 'scripts', 'wsl', 'README.md')
}

function Get-AgentRelativePath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Path
    )

    $rootPath = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if (-not $fullPath.StartsWith($rootPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside root. Path: $fullPath Root: $rootPath"
    }

    return $fullPath.Substring($rootPath.Length).Replace('\', '/')
}

function Copy-AgentResourceSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$TargetRoot
    )

    $sourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
    $programRoot = $TargetRoot
    New-Item -ItemType Directory -Path $programRoot -Force | Out-Null

    foreach ($item in (Get-AgentLocalResourceItems)) {
        $source = Join-Path $sourceRoot $item
        if (-not (Test-Path -LiteralPath $source)) {
            continue
        }

        $target = Join-Path $programRoot $item
        if (Test-Path -LiteralPath $source -PathType Container) {
            if (Test-Path -LiteralPath $target) {
                Remove-Item -LiteralPath $target -Recurse -Force
            }
            Copy-Item -LiteralPath $source -Destination $programRoot -Recurse -Force
        }
        else {
            Copy-Item -LiteralPath $source -Destination $target -Force
        }
    }

    $cmdPath = Join-Path $programRoot 'agent-system.cmd'
    $cmd = '@echo off' + [Environment]::NewLine +
        'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bin\agent-system.ps1" %*' + [Environment]::NewLine
    Set-Content -LiteralPath $cmdPath -Value $cmd -Encoding ASCII

    return (Get-AgentResourceManifestEntries -TargetRoot $programRoot)
}

function Get-AgentResourceManifestEntries {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TargetRoot)

    $target = (Resolve-Path -LiteralPath $TargetRoot).Path
    $entries = Get-ChildItem -LiteralPath $target -Recurse -File |
        Sort-Object FullName |
        ForEach-Object {
            [ordered]@{
                relative_path = (Get-AgentRelativePath -Root $target -Path $_.FullName)
                size_bytes    = $_.Length
                sha256        = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        }

    return [object[]]$entries
}

function Copy-AgentProgramFiles {
    param([Parameter(Mandatory)]$Config)

    Copy-AgentResourceSet -SourceRoot $Config.SourceRoot -TargetRoot $Config.ProgramRoot | Out-Null
}

function New-AgentOperationEventRecord {
    param(
        [Parameter(Mandatory)][string]$OperationName,
        [Parameter(Mandatory)][string]$Event,
        [Parameter(Mandatory)][string]$OperationId,
        [string]$Message,
        [string]$ErrorCode,
        [hashtable]$Data
    )

    $record = [ordered]@{
        '$schema'      = './schemas/operation.schema.json'
        schema_version = '1.0'
        operation      = $OperationName
        event          = $Event
        timestamp      = (ConvertTo-AgentIsoTimestamp)
        operation_id   = $OperationId
    }

    if ($Message) {
        $record.message = $Message
    }

    if ($ErrorCode) {
        $record.error_code = $ErrorCode
    }

    if ($Data) {
        foreach ($key in $Data.Keys) {
            $record[$key] = $Data[$key]
        }
    }

    return [pscustomobject]$record
}

function Write-AgentOperationEvent {
    param(
        [Parameter(Mandatory)]$Record,
        [ValidateSet('text', 'json')]
        [string]$OutputFormat = 'text'
    )

    if ($OutputFormat -eq 'json') {
        $Record | ConvertTo-Json -Compress -Depth 8
        return
    }

    if ($Record.PSObject.Properties['message']) {
        Write-Host $Record.message
    }
}

function Ensure-AgentOperationStore {
    param([Parameter(Mandatory)]$Config)

    $stateRoot = Join-Path $Config.InstallRoot 'state'
    $operationRoot = Join-Path $stateRoot 'operations'
    $logsRoot = Join-Path $Config.InstallRoot 'logs'

    New-Item -ItemType Directory -Path $operationRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $logsRoot -Force | Out-Null

    return [pscustomobject]@{
        StateRoot     = $stateRoot
        OperationRoot = $operationRoot
        LogsRoot      = $logsRoot
        AuditLogPath  = (Join-Path $logsRoot 'operations.jsonl')
        ManifestPath  = (Join-Path $stateRoot 'resource-manifest.json')
    }
}

function New-AgentOperationPhase {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][int]$Order,
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][string]$Kind,
        [string]$Message
    )

    return [ordered]@{
        name        = $Name
        order       = $Order
        status      = $Status
        kind        = $Kind
        idempotency = 'idempotent'
        message     = $Message
        started_at  = (ConvertTo-AgentIsoTimestamp)
        updated_at  = (ConvertTo-AgentIsoTimestamp)
    }
}

function Write-AgentOperationCheckpoint {
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)][string]$OperationId,
        [Parameter(Mandatory)][string]$OperationName,
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)]$Phase,
        [Parameter(Mandatory)][string]$StartedAt,
        [Parameter(Mandatory)][bool]$RequiresElevation,
        [string]$LastErrorCode,
        [string]$RecoveryDescription,
        [string]$Caller = 'cli'
    )

    $checkpointPath = Join-Path $Store.OperationRoot "$OperationId.json"
    $resumeCommand = ".\bin\agent-system.ps1 $OperationName -OperationId $OperationId -Resume"
    $record = [ordered]@{
        '$schema'           = './schemas/checkpoint.schema.json'
        schema_version      = '1.0'
        operation_id        = $OperationId
        operation_name      = $OperationName
        operation_type      = 'repair'
        status              = $Status
        phase               = $Phase
        started_at          = $StartedAt
        updated_at          = (ConvertTo-AgentIsoTimestamp)
        requires_elevation  = $RequiresElevation
        reboot_required     = $false
        resume_command      = $resumeCommand
        last_error_code     = if ($LastErrorCode) { $LastErrorCode } else { $null }
        recovery_action     = [ordered]@{
            action      = if ($Status -eq 'completed') { 'retry' } else { 'resume' }
            description = if ($RecoveryDescription) { $RecoveryDescription } else { 'Rerun the fixed allowlisted repair operation.' }
            command     = $resumeCommand
        }
        caller              = [ordered]@{
            surface = $Caller
        }
        artifacts           = [ordered]@{
            checkpoint_path       = $checkpointPath
            audit_log_path        = $Store.AuditLogPath
            resource_manifest_path = $Store.ManifestPath
        }
        notes               = @('repair-local-resources never writes to WSL distro data.')
    }

    $record | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $checkpointPath -Encoding UTF8
    return $checkpointPath
}

function Write-AgentOperationAudit {
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)][string]$OperationId,
        [Parameter(Mandatory)][string]$OperationName,
        [Parameter(Mandatory)][string]$Phase,
        [Parameter(Mandatory)][string]$Caller,
        [Parameter(Mandatory)][bool]$RequiresElevation,
        [Parameter(Mandatory)][string]$Result,
        [Parameter(Mandatory)][double]$ElapsedMs,
        [string]$Message,
        [string]$ErrorCode,
        [string]$CheckpointPath,
        [string]$ResourceManifestPath,
        [string]$TargetRoot
    )

    $record = [ordered]@{
        schema_version = '1.0'
        timestamp      = (ConvertTo-AgentIsoTimestamp)
        operation_id   = $OperationId
        operation_name = $OperationName
        phase          = $Phase
        caller         = $Caller
        requires_elevation = $RequiresElevation
        result         = $Result
        elapsed_ms     = [math]::Round($ElapsedMs, 2)
        error_code     = if ($ErrorCode) { $ErrorCode } else { $null }
    }

    if ($Message) {
        $record.message = $Message
    }

    if ($CheckpointPath) {
        $record.checkpoint_path = $CheckpointPath
    }

    if ($ResourceManifestPath) {
        $record.resource_manifest_path = $ResourceManifestPath
    }

    if ($TargetRoot) {
        $record.target_root = $TargetRoot
    }

    Add-Content -LiteralPath $Store.AuditLogPath -Value ($record | ConvertTo-Json -Compress -Depth 8) -Encoding UTF8
}

function Write-AgentResourceManifest {
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)][string]$OperationId,
        [Parameter(Mandatory)]$Entries
    )

    $metadataPath = Join-Path $Config.SourceRoot 'config\release-metadata.json'
    $metadata = if (Test-Path -LiteralPath $metadataPath) {
        Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    }
    else {
        [pscustomobject]@{
            version        = '0.1.0-alpha.0'
            channel        = 'internal-alpha'
            signing_status = 'unsigned-internal-only'
        }
    }

    $manifest = [ordered]@{
        schema_version = '1.0'
        generated_at   = (ConvertTo-AgentIsoTimestamp)
        operation_id   = $OperationId
        source_root    = $Config.SourceRoot
        program_root   = $Config.ProgramRoot
        release        = $metadata
        resources      = [object[]]$Entries
    }

    $manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Store.ManifestPath -Encoding UTF8
    return $manifest
}

function Invoke-AgentSystemResourceRepair {
    [CmdletBinding()]
    param(
        [string]$DistroName,
        [string]$WslUser,
        [string]$InstallRoot,
        [string]$ProgramRoot,
        [ValidateSet('text', 'json')]
        [string]$OutputFormat = 'text',
        [string]$OperationId,
        [switch]$Resume,
        [switch]$AllowTestRootOverride,
        [ValidateSet('cli', 'desktop', 'helper', 'installer', 'scheduled-task')]
        [string]$Caller = 'cli',
        [ValidateSet('', 'validate-request', 'snapshot-existing-layout', 'copy-bundled-resources', 'write-resource-manifest', 'verify-target-layout')]
        [string]$SimulateInterruptAfterPhase = ''
    )

    $defaultConfig = Get-AgentSystemConfig -DistroName $DistroName -WslUser $WslUser
    if (-not $AllowTestRootOverride) {
        if ($InstallRoot -and (-not (Test-AgentPathUnderDirectory -Path $InstallRoot -Directory $defaultConfig.InstallRoot) -or -not (Test-AgentPathUnderDirectory -Path $defaultConfig.InstallRoot -Directory $InstallRoot))) {
            throw "repair-local-resources uses the fixed InstallRoot from configuration. Test roots require -AllowTestRootOverride."
        }
        if ($ProgramRoot -and (-not (Test-AgentPathUnderDirectory -Path $ProgramRoot -Directory $defaultConfig.ProgramRoot) -or -not (Test-AgentPathUnderDirectory -Path $defaultConfig.ProgramRoot -Directory $ProgramRoot))) {
            throw "repair-local-resources uses the fixed ProgramRoot from configuration. Test roots require -AllowTestRootOverride."
        }
    }

    $config = Get-AgentSystemConfig -DistroName $DistroName -WslUser $WslUser -InstallRoot $InstallRoot -ProgramRoot $ProgramRoot
    $operationName = 'repair-local-resources'
    if (-not $OperationId) {
        $OperationId = [guid]::NewGuid().Guid.ToLowerInvariant()
    }
    if ($OperationId -notmatch '^[a-z0-9][a-z0-9-]{2,63}$') {
        throw "Invalid operation id: $OperationId"
    }

    $store = Ensure-AgentOperationStore -Config $config
    $checkpointPath = Join-Path $store.OperationRoot "$OperationId.json"
    $startedAt = ConvertTo-AgentIsoTimestamp
    $resumeAfterOrder = -1
    if ($Resume -and (Test-Path -LiteralPath $checkpointPath)) {
        $existing = Get-Content -LiteralPath $checkpointPath -Raw | ConvertFrom-Json
        $startedAt = $existing.started_at
        if ($existing.phase.status -eq 'completed') {
            $resumeAfterOrder = [int]$existing.phase.order
        }
    }

    $requiresElevation = Test-AgentProgramRootRequiresElevation -ProgramRoot $config.ProgramRoot
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $entries = @()
    $manifest = $null

    Write-AgentOperationEvent -OutputFormat $OutputFormat -Record (New-AgentOperationEventRecord -OperationName $operationName -Event 'operation_started' -OperationId $OperationId -Message "Starting repair-local-resources." -Data @{
        phase = if ($Resume) { 'resume' } else { 'validate-request' }
        status = 'running'
        requires_elevation = $requiresElevation
        elapsed_ms = [math]::Round($stopwatch.Elapsed.TotalMilliseconds, 2)
    })

    try {
        $phase = New-AgentOperationPhase -Name 'validate-request' -Order 0 -Status 'running' -Kind 'preflight' -Message 'Checking repair target and privilege boundary.'

        if ($requiresElevation -and -not (Test-AgentAdministrator)) {
            $phase.status = 'failed'
            $phase.message = 'Program Files repair requires elevation.'
            $phase.updated_at = ConvertTo-AgentIsoTimestamp
            Write-AgentOperationCheckpoint -Config $config -Store $store -OperationId $OperationId -OperationName $operationName -Status 'blocked' -Phase $phase -StartedAt $startedAt -RequiresElevation $requiresElevation -LastErrorCode 'PERMISSION_REQUIRED' -RecoveryDescription 'Rerun the allowlisted repair operation from an elevated PowerShell session.' -Caller $Caller | Out-Null
            Write-AgentOperationAudit -Store $store -OperationId $OperationId -OperationName $operationName -Phase 'validate-request' -Caller $Caller -RequiresElevation $requiresElevation -Result 'blocked' -ElapsedMs $stopwatch.Elapsed.TotalMilliseconds -Message 'Elevation required.' -ErrorCode 'PERMISSION_REQUIRED' -CheckpointPath $checkpointPath -ResourceManifestPath $store.ManifestPath -TargetRoot $config.ProgramRoot
            Write-AgentOperationEvent -OutputFormat $OutputFormat -Record (New-AgentOperationEventRecord -OperationName $operationName -Event 'error' -OperationId $OperationId -Message 'Program Files repair requires elevation.' -ErrorCode 'PERMISSION_REQUIRED' -Data @{
                phase = 'validate-request'
                status = 'blocked'
                requires_elevation = $requiresElevation
                elapsed_ms = [math]::Round($stopwatch.Elapsed.TotalMilliseconds, 2)
            })
            throw "repair-local-resources requires elevation for ProgramRoot: $($config.ProgramRoot)"
        }

        if ($resumeAfterOrder -lt 0) {
            $phase.status = 'completed'
            $phase.message = 'Repair request is valid.'
            $phase.updated_at = ConvertTo-AgentIsoTimestamp
            Write-AgentOperationCheckpoint -Config $config -Store $store -OperationId $OperationId -OperationName $operationName -Status 'running' -Phase $phase -StartedAt $startedAt -RequiresElevation $requiresElevation -Caller $Caller | Out-Null
            Write-AgentOperationAudit -Store $store -OperationId $OperationId -OperationName $operationName -Phase 'validate-request' -Caller $Caller -RequiresElevation $requiresElevation -Result 'completed' -ElapsedMs $stopwatch.Elapsed.TotalMilliseconds -Message 'Repair request is valid.' -CheckpointPath $checkpointPath -ResourceManifestPath $store.ManifestPath -TargetRoot $config.ProgramRoot
        }

        if ($SimulateInterruptAfterPhase -eq 'validate-request') {
            throw "Simulated interruption after phase validate-request for operation $OperationId."
        }

        if ($resumeAfterOrder -lt 1) {
            $phase = New-AgentOperationPhase -Name 'snapshot-existing-layout' -Order 1 -Status 'completed' -Kind 'preflight' -Message 'Captured current target inventory for audit.'
            Write-AgentOperationCheckpoint -Config $config -Store $store -OperationId $OperationId -OperationName $operationName -Status 'running' -Phase $phase -StartedAt $startedAt -RequiresElevation $requiresElevation -Caller $Caller | Out-Null
            $existingCount = if (Test-Path -LiteralPath $config.ProgramRoot) { @(Get-ChildItem -LiteralPath $config.ProgramRoot -Recurse -File -ErrorAction SilentlyContinue).Count } else { 0 }
            Write-AgentOperationAudit -Store $store -OperationId $OperationId -OperationName $operationName -Phase 'snapshot-existing-layout' -Caller $Caller -RequiresElevation $requiresElevation -Result 'completed' -ElapsedMs $stopwatch.Elapsed.TotalMilliseconds -Message ("Captured {0} existing files." -f $existingCount) -CheckpointPath $checkpointPath -ResourceManifestPath $store.ManifestPath -TargetRoot $config.ProgramRoot
        }

        if ($SimulateInterruptAfterPhase -eq 'snapshot-existing-layout') {
            throw "Simulated interruption after phase snapshot-existing-layout for operation $OperationId."
        }

        if ($resumeAfterOrder -lt 2) {
            $phase = New-AgentOperationPhase -Name 'copy-bundled-resources' -Order 2 -Status 'running' -Kind 'copy' -Message 'Copying bundled local resources into ProgramRoot.'
            Write-AgentOperationCheckpoint -Config $config -Store $store -OperationId $OperationId -OperationName $operationName -Status 'running' -Phase $phase -StartedAt $startedAt -RequiresElevation $requiresElevation -Caller $Caller | Out-Null
            $entries = Copy-AgentResourceSet -SourceRoot $config.SourceRoot -TargetRoot $config.ProgramRoot
            $phase.status = 'completed'
            $phase.message = ("Copied {0} local resources." -f $entries.Count)
            $phase.updated_at = ConvertTo-AgentIsoTimestamp
            Write-AgentOperationCheckpoint -Config $config -Store $store -OperationId $OperationId -OperationName $operationName -Status 'running' -Phase $phase -StartedAt $startedAt -RequiresElevation $requiresElevation -Caller $Caller | Out-Null
            Write-AgentOperationAudit -Store $store -OperationId $OperationId -OperationName $operationName -Phase 'copy-bundled-resources' -Caller $Caller -RequiresElevation $requiresElevation -Result 'completed' -ElapsedMs $stopwatch.Elapsed.TotalMilliseconds -Message ("Copied {0} resources." -f $entries.Count) -CheckpointPath $checkpointPath -ResourceManifestPath $store.ManifestPath -TargetRoot $config.ProgramRoot
            Write-AgentOperationEvent -OutputFormat $OutputFormat -Record (New-AgentOperationEventRecord -OperationName $operationName -Event 'progress' -OperationId $OperationId -Message ("Copied {0} local resources." -f $entries.Count) -Data @{
                phase = 'copy-bundled-resources'
                status = 'completed'
                requires_elevation = $requiresElevation
                elapsed_ms = [math]::Round($stopwatch.Elapsed.TotalMilliseconds, 2)
            })
        }
        else {
            $entries = Get-AgentResourceManifestEntries -TargetRoot $config.ProgramRoot
            Write-AgentOperationEvent -OutputFormat $OutputFormat -Record (New-AgentOperationEventRecord -OperationName $operationName -Event 'progress' -OperationId $OperationId -Message 'Resuming after completed copy-bundled-resources phase.' -Data @{
                phase = 'copy-bundled-resources'
                status = 'skipped'
                requires_elevation = $requiresElevation
                elapsed_ms = [math]::Round($stopwatch.Elapsed.TotalMilliseconds, 2)
            })
        }

        if ($SimulateInterruptAfterPhase -eq 'copy-bundled-resources') {
            throw "Simulated interruption after phase copy-bundled-resources for operation $OperationId."
        }

        if ($resumeAfterOrder -lt 3 -or -not (Test-Path -LiteralPath $store.ManifestPath)) {
            $phase = New-AgentOperationPhase -Name 'write-resource-manifest' -Order 3 -Status 'running' -Kind 'configure' -Message 'Writing deterministic resource manifest.'
            Write-AgentOperationCheckpoint -Config $config -Store $store -OperationId $OperationId -OperationName $operationName -Status 'running' -Phase $phase -StartedAt $startedAt -RequiresElevation $requiresElevation -Caller $Caller | Out-Null
            if ($entries.Count -eq 0 -and (Test-Path -LiteralPath $config.ProgramRoot)) {
                $entries = Get-AgentResourceManifestEntries -TargetRoot $config.ProgramRoot
            }
            $manifest = Write-AgentResourceManifest -Config $config -Store $store -OperationId $OperationId -Entries $entries
            $phase.status = 'completed'
            $phase.message = 'Resource manifest written.'
            $phase.updated_at = ConvertTo-AgentIsoTimestamp
            Write-AgentOperationCheckpoint -Config $config -Store $store -OperationId $OperationId -OperationName $operationName -Status 'running' -Phase $phase -StartedAt $startedAt -RequiresElevation $requiresElevation -Caller $Caller | Out-Null
            Write-AgentOperationAudit -Store $store -OperationId $OperationId -OperationName $operationName -Phase 'write-resource-manifest' -Caller $Caller -RequiresElevation $requiresElevation -Result 'completed' -ElapsedMs $stopwatch.Elapsed.TotalMilliseconds -Message 'Resource manifest written.' -CheckpointPath $checkpointPath -ResourceManifestPath $store.ManifestPath -TargetRoot $config.ProgramRoot
            Write-AgentOperationEvent -OutputFormat $OutputFormat -Record (New-AgentOperationEventRecord -OperationName $operationName -Event 'progress' -OperationId $OperationId -Message 'Resource manifest written.' -Data @{
                phase = 'write-resource-manifest'
                status = 'completed'
                requires_elevation = $requiresElevation
                elapsed_ms = [math]::Round($stopwatch.Elapsed.TotalMilliseconds, 2)
            })
        }
        else {
            $manifest = Get-Content -LiteralPath $store.ManifestPath -Raw | ConvertFrom-Json
        }

        if ($SimulateInterruptAfterPhase -eq 'write-resource-manifest') {
            throw "Simulated interruption after phase write-resource-manifest for operation $OperationId."
        }

        $phase = New-AgentOperationPhase -Name 'verify-target-layout' -Order 4 -Status 'completed' -Kind 'verify' -Message 'Target files match the resource manifest.'
        $manifestEntries = @($manifest.resources)
        foreach ($entry in $manifestEntries) {
            $targetPath = Join-Path $config.ProgramRoot ($entry.relative_path -replace '/', '\')
            if (-not (Test-Path -LiteralPath $targetPath)) {
                throw "Manifest entry is missing from ProgramRoot: $($entry.relative_path)"
            }
            $hash = (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($hash -ne $entry.sha256) {
                throw "Manifest hash mismatch for ProgramRoot entry: $($entry.relative_path)"
            }
        }
        Write-AgentOperationCheckpoint -Config $config -Store $store -OperationId $OperationId -OperationName $operationName -Status 'completed' -Phase $phase -StartedAt $startedAt -RequiresElevation $requiresElevation -Caller $Caller | Out-Null
        Write-AgentOperationAudit -Store $store -OperationId $OperationId -OperationName $operationName -Phase 'verify-target-layout' -Caller $Caller -RequiresElevation $requiresElevation -Result 'completed' -ElapsedMs $stopwatch.Elapsed.TotalMilliseconds -Message 'Target files match resource manifest.' -CheckpointPath $checkpointPath -ResourceManifestPath $store.ManifestPath -TargetRoot $config.ProgramRoot

        if ($SimulateInterruptAfterPhase -eq 'verify-target-layout') {
            throw "Simulated interruption after phase verify-target-layout for operation $OperationId."
        }

        $phase = New-AgentOperationPhase -Name 'finalize-operation' -Order 5 -Status 'completed' -Kind 'cleanup' -Message 'Local resources repaired.'
        Write-AgentOperationCheckpoint -Config $config -Store $store -OperationId $OperationId -OperationName $operationName -Status 'completed' -Phase $phase -StartedAt $startedAt -RequiresElevation $requiresElevation -Caller $Caller | Out-Null
        Write-AgentOperationAudit -Store $store -OperationId $OperationId -OperationName $operationName -Phase 'finalize-operation' -Caller $Caller -RequiresElevation $requiresElevation -Result 'completed' -ElapsedMs $stopwatch.Elapsed.TotalMilliseconds -Message 'repair-local-resources completed.' -CheckpointPath $checkpointPath -ResourceManifestPath $store.ManifestPath -TargetRoot $config.ProgramRoot

        Write-AgentOperationEvent -OutputFormat $OutputFormat -Record (New-AgentOperationEventRecord -OperationName $operationName -Event 'operation_completed' -OperationId $OperationId -Message 'repair-local-resources completed.' -Data @{
            checkpoint_path = $checkpointPath
            audit_log_path = $store.AuditLogPath
            resource_manifest_path = $store.ManifestPath
            copied_resources = $manifest.resources.Count
            phase = 'finalize-operation'
            status = 'completed'
            requires_elevation = $requiresElevation
            elapsed_ms = [math]::Round($stopwatch.Elapsed.TotalMilliseconds, 2)
        })
    }
    catch {
        if ($_.Exception.Message -notmatch 'requires elevation') {
            $errorCode = if ($_.Exception.Message -match '^Simulated interruption') { 'OPERATION_INTERRUPTED' } else { 'RESOURCE_REPAIR_FAILED' }
            $phase = if (Test-Path -LiteralPath $checkpointPath) {
                (Get-Content -LiteralPath $checkpointPath -Raw | ConvertFrom-Json).phase
            }
            else {
                New-AgentOperationPhase -Name 'validate-request' -Order 0 -Status 'failed' -Kind 'preflight' -Message $_.Exception.Message
            }
            Write-AgentOperationCheckpoint -Config $config -Store $store -OperationId $OperationId -OperationName $operationName -Status 'failed' -Phase $phase -StartedAt $startedAt -RequiresElevation $requiresElevation -LastErrorCode $errorCode -RecoveryDescription 'Resume the allowlisted repair operation with the same operation id.' -Caller $Caller | Out-Null
            Write-AgentOperationAudit -Store $store -OperationId $OperationId -OperationName $operationName -Phase $phase.name -Caller $Caller -RequiresElevation $requiresElevation -Result 'failed' -ElapsedMs $stopwatch.Elapsed.TotalMilliseconds -Message $_.Exception.Message -ErrorCode $errorCode -CheckpointPath $checkpointPath -ResourceManifestPath $store.ManifestPath -TargetRoot $config.ProgramRoot
            Write-AgentOperationEvent -OutputFormat $OutputFormat -Record (New-AgentOperationEventRecord -OperationName $operationName -Event 'error' -OperationId $OperationId -Message $_.Exception.Message -ErrorCode $errorCode -Data @{
                phase = $phase.name
                status = 'failed'
                requires_elevation = $requiresElevation
                elapsed_ms = [math]::Round($stopwatch.Elapsed.TotalMilliseconds, 2)
            })
        }

        throw
    }
}

function Ensure-AgentWslFeature {
    Assert-AgentAdministrator

    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        throw "wsl.exe was not found. This Windows build does not expose WSL commands."
    }

    $status = & wsl.exe --status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "WSL status is not healthy. Attempting to install WSL without a distribution."
        $exitCode = Invoke-AgentNative -FilePath 'wsl.exe' -Arguments @('--install', '--no-distribution') -AllowNonZero
        if ($exitCode -ne 0) {
            Write-Warning "wsl --install --no-distribution failed. Falling back to enabling optional features."
            Invoke-AgentNative -FilePath 'dism.exe' -Arguments @('/online', '/enable-feature', '/featurename:Microsoft-Windows-Subsystem-Linux', '/all', '/norestart') -AllowNonZero | Out-Null
            Invoke-AgentNative -FilePath 'dism.exe' -Arguments @('/online', '/enable-feature', '/featurename:VirtualMachinePlatform', '/all', '/norestart') -AllowNonZero | Out-Null
        }
    }

    Invoke-AgentNative -FilePath 'wsl.exe' -Arguments @('--set-default-version', '2') -AllowNonZero | Out-Null
}

function Ensure-AgentUbuntuDistro {
    param([Parameter(Mandatory)]$Config)

    if (Test-WslDistro -DistroName $Config.DistroName) {
        Invoke-AgentNative -FilePath 'wsl.exe' -Arguments @('--set-version', $Config.DistroName, '2') -AllowNonZero | Out-Null
        return
    }

    Write-Host "Installing WSL distribution $($Config.DistroName). This can take several minutes."
    $exitCode = Invoke-AgentNative -FilePath 'wsl.exe' -Arguments @('--install', '--web-download', '-d', $Config.DistroName, '--no-launch') -AllowNonZero
    if ($exitCode -ne 0) {
        Write-Warning "wsl --install --web-download did not complete. Retrying without --web-download."
        $exitCode = Invoke-AgentNative -FilePath 'wsl.exe' -Arguments @('--install', '-d', $Config.DistroName, '--no-launch') -AllowNonZero
    }

    if ($exitCode -ne 0 -or -not (Test-WslDistro -DistroName $Config.DistroName)) {
        throw "Ubuntu distro is not ready yet. If Windows requested a reboot, reboot and rerun this installer."
    }

    Invoke-AgentNative -FilePath 'wsl.exe' -Arguments @('--set-version', $Config.DistroName, '2') -AllowNonZero | Out-Null
}

function Get-AgentWslSharePath {
    param(
        [Parameter(Mandatory)][string]$DistroName,
        [Parameter(Mandatory)][string]$LinuxPath
    )

    $relative = $LinuxPath.TrimStart('/') -replace '/', '\'
    $candidates = @(
        "\\wsl.localhost\$DistroName\$relative",
        "\\wsl$\$DistroName\$relative"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return $candidates[0]
}

function Copy-AgentPayloadToWsl {
    param([Parameter(Mandatory)]$Config)

    Invoke-AgentWsl -DistroName $Config.DistroName -Command 'mkdir -p /tmp/agent-system' | Out-Null

    $unc = Get-AgentWslSharePath -DistroName $Config.DistroName -LinuxPath '/tmp/agent-system'
    if (-not (Test-Path -LiteralPath $unc)) {
        throw "Cannot access WSL share path: $unc"
    }

    Get-ChildItem -LiteralPath (Join-Path $Config.SourceRoot 'wsl') | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $unc -Recurse -Force
    }

    $dockerTarget = Join-Path $unc 'docker'
    if (Test-Path -LiteralPath $dockerTarget) {
        Remove-Item -LiteralPath $dockerTarget -Recurse -Force
    }
    Copy-Item -LiteralPath (Join-Path $Config.SourceRoot 'docker') -Destination $dockerTarget -Recurse -Force
}

function Install-AgentWslComponents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [switch]$SkipDocker,
        [switch]$SkipHermes,
        [switch]$Force
    )

    Copy-AgentPayloadToWsl -Config $Config

    $user = ConvertTo-AgentBashSingleQuoted $Config.WslUser
    $installUrl = ConvertTo-AgentBashSingleQuoted $Config.HermesInstallUrl
    $skipDockerValue = if ($SkipDocker) { '1' } else { '0' }
    $skipHermesValue = if ($SkipHermes) { '1' } else { '0' }
    $forceValue = if ($Force) { '1' } else { '0' }
    $bootstrap = "AGENT_USER=$user HERMES_INSTALL_URL=$installUrl SKIP_DOCKER=$skipDockerValue SKIP_HERMES=$skipHermesValue FORCE_UPDATE=$forceValue bash /tmp/agent-system/bootstrap-ubuntu.sh"

    Invoke-AgentWsl -DistroName $Config.DistroName -Command "chmod +x /tmp/agent-system/*.sh && $bootstrap" | Out-Null

    if (Test-AgentWslFile -DistroName $Config.DistroName -Path '/var/lib/agent-system/restart-required') {
        Write-Host "Restarting WSL once to activate systemd settings."
        Invoke-AgentNative -FilePath 'wsl.exe' -Arguments @('--shutdown') -AllowNonZero | Out-Null
        Start-Sleep -Seconds 5
        Invoke-AgentWsl -DistroName $Config.DistroName -Command $bootstrap | Out-Null
    }
}

function Register-AgentStartupTask {
    param([Parameter(Mandatory)]$Config)

    $action = New-ScheduledTaskAction `
        -Execute "$env:WINDIR\System32\wsl.exe" `
        -Argument "-d $($Config.DistroName) -u root -- /usr/local/bin/agent-system-start"
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Hours 12)
    $principal = New-ScheduledTaskPrincipal `
        -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) `
        -LogonType Interactive `
        -RunLevel Highest

    Register-ScheduledTask `
        -TaskName $Config.TaskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Description 'Starts the WSL2 Agent System services for Docker and Hermes Agent.' `
        -Force | Out-Null
}

function Install-AgentClawPanel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [string]$ClawPanelAssetUrl,
        [switch]$Force
    )

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $downloads = Join-Path $Config.InstallRoot 'downloads'
    New-Item -ItemType Directory -Path $downloads -Force | Out-Null

    if (-not $ClawPanelAssetUrl) {
        $apiUrl = "https://api.github.com/repos/$($Config.ClawPanelRepo)/releases/latest"
        Write-Host "Resolving latest ClawPanel release from $apiUrl"
        $headers = @{
            'User-Agent' = 'agent-system-installer'
            'Accept'     = 'application/vnd.github+json'
        }
        $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers
        $assets = @($release.assets)
        $asset = $assets |
            Where-Object { $_.name -match '^ClawPanel_.*_x64_en-US\.msi$' } |
            Select-Object -First 1
        if (-not $asset) {
            $asset = $assets |
                Where-Object { $_.name -match '^ClawPanel_.*_x64-setup\.exe$' } |
                Select-Object -First 1
        }
        if (-not $asset) {
            throw "No Windows x64 MSI/EXE ClawPanel asset was found in latest release $($release.tag_name)."
        }
        $ClawPanelAssetUrl = $asset.browser_download_url
        $fileName = $asset.name
    }
    else {
        $fileName = Split-Path -Leaf ([Uri]$ClawPanelAssetUrl).AbsolutePath
    }

    $downloadPath = Join-Path $downloads $fileName
    if ($Force -or -not (Test-Path -LiteralPath $downloadPath)) {
        Write-Host "Downloading ClawPanel: $ClawPanelAssetUrl"
        Invoke-WebRequest -Uri $ClawPanelAssetUrl -OutFile $downloadPath
    }

    if ($downloadPath -match '\.msi$') {
        Invoke-AgentNative -FilePath 'msiexec.exe' -Arguments @('/i', $downloadPath, '/qn', '/norestart') | Out-Null
    }
    elseif ($downloadPath -match '\.exe$') {
        $process = Start-Process -FilePath $downloadPath -ArgumentList '/S' -Wait -PassThru -WindowStyle Hidden
        if ($process.ExitCode -ne 0) {
            throw "ClawPanel EXE installer failed with exit code $($process.ExitCode)."
        }
    }
    else {
        throw "Unsupported ClawPanel installer file: $downloadPath"
    }
}

function Install-AgentSystem {
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
        [switch]$NoStartupTask,
        [switch]$Force
    )

    $config = Get-AgentSystemConfig -DistroName $DistroName -WslUser $WslUser -InstallRoot $InstallRoot -ProgramRoot $ProgramRoot
    Assert-AgentAdministrator
    Ensure-AgentDirectories -Config $config
    Copy-AgentProgramFiles -Config $config
    Ensure-AgentWslFeature
    Ensure-AgentUbuntuDistro -Config $config
    Install-AgentWslComponents -Config $config -SkipDocker:$SkipDocker -SkipHermes:$SkipHermes -Force:$Force

    if (-not $NoStartupTask) {
        Register-AgentStartupTask -Config $config
    }

    if (-not $SkipClawPanel) {
        Install-AgentClawPanel -Config $config -ClawPanelAssetUrl $ClawPanelAssetUrl -Force:$Force
    }

    Start-AgentSystem -DistroName $config.DistroName -WslUser $config.WslUser -InstallRoot $config.InstallRoot -ProgramRoot $config.ProgramRoot
}

function Update-AgentSystem {
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

    $config = Get-AgentSystemConfig -DistroName $DistroName -WslUser $WslUser -InstallRoot $InstallRoot -ProgramRoot $ProgramRoot
    Assert-AgentAdministrator
    Ensure-AgentDirectories -Config $config
    Copy-AgentProgramFiles -Config $config
    Ensure-AgentUbuntuDistro -Config $config
    Install-AgentWslComponents -Config $config -SkipDocker:$SkipDocker -SkipHermes:$SkipHermes -Force:$Force

    if (-not $SkipHermes -or -not $SkipDocker) {
        Invoke-AgentWsl -DistroName $config.DistroName -Command '/usr/local/bin/agent-system-update' | Out-Null
    }

    if (-not $SkipClawPanel) {
        Install-AgentClawPanel -Config $config -ClawPanelAssetUrl $ClawPanelAssetUrl -Force:$true
    }

    Start-AgentSystem -DistroName $config.DistroName -WslUser $config.WslUser -InstallRoot $config.InstallRoot -ProgramRoot $config.ProgramRoot
}

function Start-AgentSystem {
    [CmdletBinding()]
    param(
        [string]$DistroName,
        [string]$WslUser,
        [string]$InstallRoot,
        [string]$ProgramRoot
    )

    $config = Get-AgentSystemConfig -DistroName $DistroName -WslUser $WslUser -InstallRoot $InstallRoot -ProgramRoot $ProgramRoot
    if (-not (Test-AgentWslFile -DistroName $config.DistroName -Path '/usr/local/bin/agent-system-start')) {
        throw "Agent payload is not installed in WSL. Run scripts\Install-AgentSystem.ps1 first."
    }
    Invoke-AgentWsl -DistroName $config.DistroName -Command '/usr/local/bin/agent-system-start' | Out-Null
}

function Stop-AgentSystem {
    [CmdletBinding()]
    param(
        [string]$DistroName,
        [string]$WslUser,
        [string]$InstallRoot,
        [string]$ProgramRoot
    )

    $config = Get-AgentSystemConfig -DistroName $DistroName -WslUser $WslUser -InstallRoot $InstallRoot -ProgramRoot $ProgramRoot
    if (-not (Test-AgentWslFile -DistroName $config.DistroName -Path '/usr/local/bin/agent-system-stop')) {
        Write-Host "Agent payload is not installed in WSL."
        return
    }
    Invoke-AgentWsl -DistroName $config.DistroName -Command '/usr/local/bin/agent-system-stop' -AllowNonZero | Out-Null
}

function Get-AgentSystemStatus {
    [CmdletBinding()]
    param(
        [string]$DistroName,
        [string]$WslUser,
        [string]$InstallRoot,
        [string]$ProgramRoot,
        [ValidateSet('text', 'json')]
        [string]$OutputFormat = 'text'
    )

    $config = Get-AgentSystemConfig -DistroName $DistroName -WslUser $WslUser -InstallRoot $InstallRoot -ProgramRoot $ProgramRoot

    if ($OutputFormat -eq 'json') {
        $record = Get-AgentSystemStatusRecord -Config $config
        $record | ConvertTo-Json -Depth 8
        return
    }

    Write-Host "Agent System"
    Write-Host "  ProgramRoot: $($config.ProgramRoot)"
    Write-Host "  InstallRoot: $($config.InstallRoot)"
    Write-Host "  Distro:      $($config.DistroName)"
    Write-Host "  WSL user:    $($config.WslUser)"
    Write-Host "  Task:        $($config.TaskName)"
    Write-Host ""

    if (-not (Test-WslDistro -DistroName $config.DistroName)) {
        Write-Host "WSL distro is not installed."
        return
    }

    if (-not (Test-AgentWslFile -DistroName $config.DistroName -Path '/usr/local/bin/agent-system-status')) {
        Write-Host "WSL distro exists, but the Agent payload is not installed yet."
        Write-Host "Run: .\scripts\Install-AgentSystem.ps1"
        return
    }

    Invoke-AgentWsl -DistroName $config.DistroName -Command '/usr/local/bin/agent-system-status' -AllowNonZero | Out-Null
}

function Invoke-AgentSystemPreflight {
    [CmdletBinding()]
    param(
        [string]$DistroName,
        [string]$WslUser,
        [string]$InstallRoot,
        [string]$ProgramRoot,
        [ValidateSet('text', 'json')]
        [string]$OutputFormat = 'text'
    )

    $config = Get-AgentSystemConfig -DistroName $DistroName -WslUser $WslUser -InstallRoot $InstallRoot -ProgramRoot $ProgramRoot
    $record = Get-AgentSystemPreflightRecord -Config $config

    if ($OutputFormat -eq 'json') {
        $record | ConvertTo-Json -Depth 8
        return
    }

    Write-AgentSystemPreflightText -Record $record
}

function Get-AgentSystemLogs {
    [CmdletBinding()]
    param(
        [string]$DistroName,
        [string]$WslUser,
        [string]$InstallRoot,
        [string]$ProgramRoot
    )

    $config = Get-AgentSystemConfig -DistroName $DistroName -WslUser $WslUser -InstallRoot $InstallRoot -ProgramRoot $ProgramRoot
    if (-not (Test-AgentWslFile -DistroName $config.DistroName -Path '/usr/local/bin/agent-system-logs')) {
        Write-Host "Agent payload is not installed in WSL."
        return
    }
    Invoke-AgentWsl -DistroName $config.DistroName -Command '/usr/local/bin/agent-system-logs' -AllowNonZero | Out-Null
}

function Invoke-HermesSetup {
    [CmdletBinding()]
    param(
        [string]$DistroName,
        [string]$WslUser,
        [string]$InstallRoot,
        [string]$ProgramRoot
    )

    $config = Get-AgentSystemConfig -DistroName $DistroName -WslUser $WslUser -InstallRoot $InstallRoot -ProgramRoot $ProgramRoot
    $user = ConvertTo-AgentBashSingleQuoted $config.WslUser
    $inner = 'export PATH="$HOME/.local/bin:$PATH"; hermes setup'
    $innerQuoted = ConvertTo-AgentBashSingleQuoted $inner
    $command = "sudo -H -u $user bash -lc $innerQuoted"
    Invoke-AgentWsl -DistroName $config.DistroName -Command $command | Out-Null
}

function Uninstall-AgentSystem {
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

    $config = Get-AgentSystemConfig -DistroName $DistroName -WslUser $WslUser -InstallRoot $InstallRoot -ProgramRoot $ProgramRoot
    Assert-AgentAdministrator

    if (Get-ScheduledTask -TaskName $config.TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $config.TaskName -Confirm:$false
    }

    if (Test-WslDistro -DistroName $config.DistroName) {
        Invoke-AgentWsl -DistroName $config.DistroName -Command '/usr/local/bin/agent-system-stop' -AllowNonZero | Out-Null
    }

    if ($RemoveDistro) {
        Invoke-AgentNative -FilePath 'wsl.exe' -Arguments @('--unregister', $config.DistroName) | Out-Null
    }

    if ($RemoveClawPanelData) {
        $paths = @(
            (Join-Path $env:APPDATA 'com.clawpanel.app'),
            (Join-Path $env:LOCALAPPDATA 'com.clawpanel.app'),
            (Join-Path $env:USERPROFILE '.openclaw\clawpanel\web-update')
        )
        foreach ($path in $paths) {
            if (Test-Path -LiteralPath $path) {
                Remove-Item -LiteralPath $path -Recurse -Force
            }
        }
    }

    if ($RemoveProgramFiles -and (Test-Path -LiteralPath $config.ProgramRoot)) {
        $resolved = (Resolve-Path -LiteralPath $config.ProgramRoot).Path
        $programFiles = [Environment]::GetFolderPath('ProgramFiles')
        if ($resolved.StartsWith($programFiles, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
        else {
            throw "Refusing to remove ProgramRoot outside Program Files: $resolved"
        }
    }
}

function Build-AgentSystemPackage {
    [CmdletBinding()]
    param([string]$OutputPath)

    $sourceRoot = Get-AgentSystemSourceRoot
    $dist = Join-Path $sourceRoot 'dist'
    New-Item -ItemType Directory -Path $dist -Force | Out-Null

    if (-not $OutputPath) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $OutputPath = Join-Path $dist "AgentSystem-$stamp.zip"
    }

    if (Test-Path -LiteralPath $OutputPath) {
        Remove-Item -LiteralPath $OutputPath -Force
    }

    $include = Get-AgentLocalResourceItems
    $temp = Join-Path $env:TEMP ("AgentSystem-Package-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temp -Force | Out-Null

    try {
        foreach ($item in $include) {
            $source = Join-Path $sourceRoot $item
            if (Test-Path -LiteralPath $source) {
                Copy-Item -LiteralPath $source -Destination $temp -Recurse -Force
            }
        }
        Compress-Archive -Path (Join-Path $temp '*') -DestinationPath $OutputPath -Force
    }
    finally {
        if (Test-Path -LiteralPath $temp) {
            Remove-Item -LiteralPath $temp -Recurse -Force
        }
    }

    Write-Host "Package written: $OutputPath"
}

function Test-AgentSystemProject {
    [CmdletBinding()]
    param()

    $sourceRoot = Get-AgentSystemSourceRoot
    $required = @(
        'README.md',
        'config\agent-system.json',
        'config\release-metadata.json',
        'bin\agent-system.ps1',
        'schemas\operation.schema.json',
        'schemas\checkpoint.schema.json',
        'scripts\lib\AgentSystem.psm1',
        'wsl\bootstrap-ubuntu.sh',
        'docker\docker-compose.yml',
        'docker\Dockerfile.hermes-runtime'
    )

    foreach ($path in $required) {
        $fullPath = Join-Path $sourceRoot $path
        if (-not (Test-Path -LiteralPath $fullPath)) {
            throw "Missing required file: $fullPath"
        }
    }

    Get-ChildItem -LiteralPath $sourceRoot -Recurse -File |
        Where-Object { $_.Extension -in @('.ps1', '.psm1') } |
        ForEach-Object {
        $parseErrors = $null
        $tokens = $null
        [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
        if ($parseErrors.Count -gt 0) {
            $message = ($parseErrors | ForEach-Object { $_.Message }) -join '; '
            throw "PowerShell parse errors in $($_.FullName): $message"
        }
    }

    $jsonPath = Join-Path $sourceRoot 'config\agent-system.json'
    Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json | Out-Null

    Write-Host "Project validation passed."
}

Export-ModuleMember -Function `
    Install-AgentSystem, `
    Update-AgentSystem, `
    Start-AgentSystem, `
    Stop-AgentSystem, `
    Get-AgentSystemStatus, `
    Invoke-AgentSystemPreflight, `
    Get-AgentSystemLogs, `
    Invoke-HermesSetup, `
    Invoke-AgentSystemResourceRepair, `
    Uninstall-AgentSystem, `
    Build-AgentSystemPackage, `
    Test-AgentSystemProject
