[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$cliPath = Join-Path $repoRoot 'bin\agent-system.ps1'
$operationSchemaPath = Join-Path $repoRoot 'schemas\operation.schema.json'

$failures = New-Object System.Collections.Generic.List[string]

function Add-Failure {
    param([string]$Message)
    $script:failures.Add($Message)
}

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        Add-Failure -Message $Message
    }
}

function Get-ParameterValidateSetValues {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][string]$ParameterName
    )

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        Add-Failure -Message ("Unable to parse {0}: {1}" -f $ScriptPath, (($parseErrors | ForEach-Object Message) -join '; '))
        return @()
    }

    $parameterAst = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq $ParameterName } | Select-Object -First 1
    if (-not $parameterAst) {
        return @()
    }

    $validateSet = $parameterAst.Attributes | Where-Object { $_.TypeName.FullName -eq 'ValidateSet' } | Select-Object -First 1
    if (-not $validateSet) {
        return @()
    }

    return @($validateSet.PositionalArguments | ForEach-Object { $_.Value })
}

function Get-JsonSnapshot {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $Path -Recurse -Force | ForEach-Object {
        [pscustomobject]@{
            Path = $_.FullName.Substring($Path.Length)
            Length = if ($_.PSIsContainer) { -1 } else { $_.Length }
            LastWriteTimeUtc = $_.LastWriteTimeUtc.ToString('o')
        }
    } | Sort-Object Path)
}

$actionValues = Get-ParameterValidateSetValues -ScriptPath $cliPath -ParameterName 'Action'
Assert-True ($actionValues -contains 'preflight') 'bin/agent-system.ps1 must expose a preflight action in the Action ValidateSet.'

$outputFormats = Get-ParameterValidateSetValues -ScriptPath $cliPath -ParameterName 'OutputFormat'
Assert-True ($outputFormats.Count -gt 0) 'bin/agent-system.ps1 must define an OutputFormat parameter with ValidateSet(text,json).'
if ($outputFormats.Count -gt 0) {
    Assert-True ($outputFormats -contains 'text') 'OutputFormat must allow text.'
    Assert-True ($outputFormats -contains 'json') 'OutputFormat must allow json.'
}

if (Test-Path -LiteralPath $operationSchemaPath) {
    $schemaRaw = Get-Content -LiteralPath $operationSchemaPath -Raw
    try {
        $null = $schemaRaw | ConvertFrom-Json
    }
    catch {
        Add-Failure -Message ("schemas/operation.schema.json is not valid JSON: {0}" -f $_.Exception.Message)
    }

    foreach ($token in @('operation_started', 'progress', 'status', 'warning', 'error', 'reboot_required', 'operation_completed', 'WSL_MISSING', 'REBOOT_REQUIRED', 'DOCKER_DAEMON_FAILED', 'HERMES_INSTALL_FAILED', 'CLAWPANEL_ASSET_MISSING', 'NETWORK_UNAVAILABLE', 'PAYLOAD_NOT_INSTALLED', 'PERMISSION_REQUIRED')) {
        Assert-True ($schemaRaw.Contains($token)) ("schemas/operation.schema.json must mention token: {0}" -f $token)
    }
}
else {
    Add-Failure -Message 'schemas/operation.schema.json is missing.'
}

$canRunJsonChecks = ($actionValues -contains 'preflight') -and ($outputFormats -contains 'json')
if ($canRunJsonChecks) {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('AgentSystem-JsonTest-' + [Guid]::NewGuid().ToString('N'))
    $installRoot = Join-Path $tempRoot 'install'
    $programRoot = Join-Path $tempRoot 'program'
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    try {
        $before = Get-JsonSnapshot -Path $tempRoot

        $preflightOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cliPath preflight -OutputFormat json -DistroName ('Missing-' + [Guid]::NewGuid().ToString('N')) -InstallRoot $installRoot -ProgramRoot $programRoot 2>&1
        $preflightExitCode = $LASTEXITCODE
        if ($preflightExitCode -ne 0) {
            Add-Failure -Message ("preflight JSON command failed with exit code {0}: {1}" -f $preflightExitCode, ($preflightOutput -join [Environment]::NewLine))
        }
        else {
            try {
                $null = ($preflightOutput -join [Environment]::NewLine) | ConvertFrom-Json
            }
            catch {
                Add-Failure -Message ("preflight JSON output is not valid JSON: {0}`nOutput:`n{1}" -f $_.Exception.Message, ($preflightOutput -join [Environment]::NewLine))
            }
        }

        $after = Get-JsonSnapshot -Path $tempRoot
        $beforeJson = $before | ConvertTo-Json -Depth 5
        $afterJson = $after | ConvertTo-Json -Depth 5
        Assert-True ($beforeJson -eq $afterJson) 'preflight must not mutate the temporary install/program roots during JSON validation.'

        $statusOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cliPath status -OutputFormat json -DistroName ('Missing-' + [Guid]::NewGuid().ToString('N')) -InstallRoot $installRoot -ProgramRoot $programRoot 2>&1
        $statusExitCode = $LASTEXITCODE
        if ($statusExitCode -ne 0) {
            Add-Failure -Message ("status JSON command failed with exit code {0}: {1}" -f $statusExitCode, ($statusOutput -join [Environment]::NewLine))
        }
        else {
            try {
                $statusJson = ($statusOutput -join [Environment]::NewLine) | ConvertFrom-Json
                $statusPayload = $statusJson.PSObject.Properties.Name
                Assert-True (($statusPayload -contains 'status') -or ($statusPayload -contains 'event_type')) 'status JSON output should include a status or event_type field.'
            }
            catch {
                Add-Failure -Message ("status JSON output is not valid JSON: {0}`nOutput:`n{1}" -f $_.Exception.Message, ($statusOutput -join [Environment]::NewLine))
            }
        }
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}

if ($failures.Count -gt 0) {
    throw ((@('Test-AgentSystemJson.ps1 failed:') + ($failures | ForEach-Object { "- $_" })) -join [Environment]::NewLine)
}

Write-Host 'Test-AgentSystemJson.ps1 passed.'
