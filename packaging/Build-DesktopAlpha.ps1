[CmdletBinding()]
param(
    [switch]$SkipNpmCi,
    [switch]$SkipBundle
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$desktopRoot = Join-Path $repoRoot 'apps\desktop'

if (-not (Test-Path -LiteralPath $desktopRoot)) {
    throw "Desktop app not found: $desktopRoot"
}

& (Join-Path $repoRoot 'scripts\Test-AgentSystem.ps1')

if (-not $SkipNpmCi) {
    npm ci --prefix $desktopRoot
}

npm run build --prefix $desktopRoot
cargo test --manifest-path (Join-Path $desktopRoot 'src-tauri\Cargo.toml')

if (-not $SkipBundle) {
    npm run tauri --prefix $desktopRoot -- build --bundles nsis
}

Write-Host 'Desktop alpha build completed. Unsigned internal-only artifacts are under apps\desktop\src-tauri\target\release\bundle.'
