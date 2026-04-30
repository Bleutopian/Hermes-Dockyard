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
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $adminRole = [Security.Principal.WindowsBuiltInRole]::Administrator
    if (-not $principal.IsInRole($adminRole)) {
        throw "This action requires an elevated PowerShell session. Run PowerShell as Administrator."
    }
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
        $hermesCheck = "sudo -H -u $user bash -lc 'export PATH=`"$HOME/.local/bin:$PATH`"; command -v hermes >/dev/null 2>&1'"
        $hermesInstalled = Test-AgentWslCommand -DistroName $Config.DistroName -Command $hermesCheck
        if ($hermesInstalled) {
            $gatewayCheck = "sudo -H -u $user bash -lc 'tmux has-session -t ''hermes-gateway'' 2>/dev/null'"
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

    return [pscustomobject]$record
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

    return [pscustomobject][ordered]@{
        '$schema'       = './schemas/operation.schema.json'
        schema_version  = '1.0'
        operation       = 'status'
        generated_at    = ConvertTo-AgentIsoTimestamp
        state           = $state
        summary         = $summary
        error_codes     = @($errorCodes | Select-Object -Unique)
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
        checks          = @($checks)
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

    return [pscustomobject][ordered]@{
        '$schema'            = './schemas/operation.schema.json'
        schema_version       = '1.0'
        operation            = 'preflight'
        generated_at         = ConvertTo-AgentIsoTimestamp
        state                = $statusRecord.state
        summary              = $statusRecord.summary
        mutates_system       = $false
        ready_for            = [ordered]@{
            read_only_checks = $true
            install          = $true
            start            = ($statusRecord.state -ne 'blocked')
        }
        recommended_actions  = @($recommendedActions)
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

function Copy-AgentProgramFiles {
    param([Parameter(Mandatory)]$Config)

    $sourceRoot = (Resolve-Path -LiteralPath $Config.SourceRoot).Path
    $programRoot = $Config.ProgramRoot
    New-Item -ItemType Directory -Path $programRoot -Force | Out-Null

    $items = @('bin', 'config', 'docker', 'packaging', 'scripts', 'wsl', 'README.md')
    foreach ($item in $items) {
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

    $include = @('bin', 'config', 'docker', 'packaging', 'scripts', 'wsl', 'README.md')
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
        'bin\agent-system.ps1',
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
    Uninstall-AgentSystem, `
    Build-AgentSystemPackage, `
    Test-AgentSystemProject
