# Hermes Dockyard Internal Alpha

Hermes Dockyard `0.1.0-alpha.1` is an unsigned internal-only build. It is intended to validate desktop packaging, bundled backend resources, read-only backend checks, and the `repair-local-resources` privileged proof before the full first-run WSL/Hermes/ClawPanel provisioning flow is exposed in the desktop app.

## Included In This Alpha

- Tauri Windows desktop shell.
- Bundled backend resources:
  - `bin`
  - `config`
  - `docker`
  - `packaging`
  - `schemas`
  - `scripts`
  - `wsl`
- Read-only backend actions: `preflight` and `status`.
- Headless `repair-local-resources` proof operation with checkpoint, audit log, and resource manifest artifacts.

## Resource Layout

- App resources: Tauri `$RESOURCE/resources/*`.
- Local program resources: `%ProgramFiles%\AgentSystem` for elevated repair, or a caller-provided `-ProgramRoot` during tests.
- Operation state: `%ProgramData%\AgentSystem\state`.
- Operation checkpoints: `%ProgramData%\AgentSystem\state\operations\<operation_id>.json`.
- Operation audit log: `%ProgramData%\AgentSystem\logs\operations.jsonl`.
- Resource manifest: `%ProgramData%\AgentSystem\state\resource-manifest.json`.

## Signing Status

This alpha is intentionally unsigned. Public release is blocked until code signing and provenance are configured. SmartScreen warnings are expected for this build and are not acceptable for a public release candidate.

## Validation

Use:

```powershell
.\packaging\Build-DesktopAlpha.ps1
```

For a faster local static pass without producing an installer:

```powershell
.\packaging\Build-DesktopAlpha.ps1 -SkipNpmCi -SkipBundle
```
