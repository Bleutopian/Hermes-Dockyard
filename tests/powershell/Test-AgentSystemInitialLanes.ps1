[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$desktopRoot = Join-Path $repoRoot 'apps\desktop'
$checkpointSchemaPath = Join-Path $repoRoot 'schemas\checkpoint.schema.json'
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

if (Test-Path -LiteralPath $checkpointSchemaPath) {
    $checkpointRaw = Get-Content -LiteralPath $checkpointSchemaPath -Raw
    try {
        $null = $checkpointRaw | ConvertFrom-Json
    }
    catch {
        Add-Failure -Message ("schemas/checkpoint.schema.json is not valid JSON: {0}" -f $_.Exception.Message)
    }

    foreach ($token in @('operation_id', 'operation_name', 'phase', 'started_at', 'updated_at', 'requires_elevation', 'reboot_required', 'resume_command', 'last_error_code', 'recovery_action')) {
        Assert-True ($checkpointRaw.Contains($token)) ("schemas/checkpoint.schema.json must mention token: {0}" -f $token)
    }
}
else {
    Add-Failure -Message 'schemas/checkpoint.schema.json is missing.'
}

$docs = @(Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Filter *.md | Where-Object {
    $relativePath = $_.FullName.Substring($repoRoot.Length).TrimStart('\', '/')
    return -not ($relativePath -like '.omx\*' -or $relativePath -like '.omx/*')
})
$docsRaw = if ($docs.Count -gt 0) { ($docs | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join [Environment]::NewLine } else { '' }
Assert-True ($docs.Count -gt 0) 'Expected at least one Markdown document outside .omx for privilege-boundary/proof documentation.'
if ($docs.Count -gt 0) {
    foreach ($token in @('privilege boundary', 'allowlisted', 'repair-local-resources', 'code signing', 'ProgramData', 'Program Files')) {
        Assert-True ($docsRaw.IndexOf($token, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) ("Documentation must mention: {0}" -f $token)
    }
}

Assert-True (Test-Path -LiteralPath $desktopRoot) 'apps/desktop is missing.'
if (Test-Path -LiteralPath $desktopRoot) {
    $packageJsonPath = Join-Path $desktopRoot 'package.json'
    $tsConfigPath = Join-Path $desktopRoot 'tsconfig.json'
    $cargoTomlPath = Join-Path $desktopRoot 'src-tauri\Cargo.toml'

    Assert-True (Test-Path -LiteralPath $packageJsonPath) 'apps/desktop/package.json is missing.'
    Assert-True (Test-Path -LiteralPath $tsConfigPath) 'apps/desktop/tsconfig.json is missing.'
    Assert-True (Test-Path -LiteralPath $cargoTomlPath) 'apps/desktop/src-tauri/Cargo.toml is missing.'

    if (Test-Path -LiteralPath $packageJsonPath) {
        try {
            $packageJson = Get-Content -LiteralPath $packageJsonPath -Raw | ConvertFrom-Json
            $allDeps = @{}
            if ($packageJson.dependencies) {
                foreach ($prop in $packageJson.dependencies.PSObject.Properties) { $allDeps[$prop.Name] = $prop.Value }
            }
            if ($packageJson.devDependencies) {
                foreach ($prop in $packageJson.devDependencies.PSObject.Properties) { $allDeps[$prop.Name] = $prop.Value }
            }

            foreach ($dep in @('react', 'typescript', '@tauri-apps/api')) {
                Assert-True ($allDeps.ContainsKey($dep)) ("apps/desktop/package.json must declare dependency: {0}" -f $dep)
            }
        }
        catch {
            Add-Failure -Message ("apps/desktop/package.json is not valid JSON: {0}" -f $_.Exception.Message)
        }
    }

    $desktopFiles = @(Get-ChildItem -LiteralPath $desktopRoot -Recurse -File | Where-Object {
        $relativePath = $_.FullName.Substring($desktopRoot.Length).TrimStart('\', '/')
        if ($relativePath -like 'node_modules\*' -or $relativePath -like 'node_modules/*') { return $false }
        if ($relativePath -like 'dist\*' -or $relativePath -like 'dist/*') { return $false }
        if ($relativePath -like 'src-tauri\target\*' -or $relativePath -like 'src-tauri/target/*') { return $false }
        if ($relativePath -like 'src-tauri\gen\*' -or $relativePath -like 'src-tauri/gen/*') { return $false }

        return ($_.Extension -in @('.ts', '.tsx', '.js', '.jsx', '.json', '.toml', '.md', '.html', '.css'))
    })
    $desktopRaw = if ($desktopFiles.Count -gt 0) { ($desktopFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue }) -join [Environment]::NewLine } else { '' }

    foreach ($token in @('Welcome', 'Preflight', 'Dashboard', 'Logs', 'Settings', 'Tools', 'Video Automation', 'preflight', 'status')) {
        Assert-True ($desktopRaw.IndexOf($token, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) ("apps/desktop sources should mention: {0}" -f $token)
    }
}

if ($failures.Count -gt 0) {
    throw ((@('Test-AgentSystemInitialLanes.ps1 failed:') + ($failures | ForEach-Object { "- $_" })) -join [Environment]::NewLine)
}

Write-Host 'Test-AgentSystemInitialLanes.ps1 passed.'
