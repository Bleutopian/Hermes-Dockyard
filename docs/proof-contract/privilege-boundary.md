# Privilege Boundary Contract

This document is the M1b contract for checkpointed mutating operations before the desktop installer is treated as product-valid.

## Normative References

- Checkpoint schema: `schemas/checkpoint.schema.json`
- Future operation envelope path: `schemas/operation.schema.json` (reserved for the backend lane; this document is authoritative until that schema lands)
- Optimized plan source: `.omx/plans/development-plan-optimized.md`

## Boundary Split

### Unelevated desktop shell

Allowed capabilities:

- Read-only `status`, `preflight`, logs, and diagnostics preview
- Settings inspection and non-secret configuration previews
- Read access to checkpoint and audit artifacts under `%ProgramData%\AgentSystem`
- Rendering structured operation state for resume/recovery UX

Prohibited capabilities:

- No direct WSL feature installation
- No distro creation/removal
- No writes beneath `%ProgramFiles%\AgentSystem`
- No scheduled task registration
- No ClawPanel MSI/EXE install or uninstall
- No arbitrary shell execution, script path injection, or free-form command composition

### Elevated helper

Allowed mutating operations are fixed and allowlisted. M1b defines the boundary for:

- `repair-local-resources`
- WSL feature install
- Distro install
- Program Files writes
- Scheduled task registration
- ClawPanel install/uninstall
- Destructive uninstall flows

Elevated entrypoints must accept structured request objects only and must return structured status, progress, warning, error, `reboot_required`, and completion events only.

## Invocation Rules

1. The UI may request only allowlisted operation names.
2. The helper must reject arbitrary commands, arbitrary file paths, and arbitrary executables.
3. UAC prompting is allowed only when crossing into a mutating elevated operation.
4. The unelevated shell may read artifacts and surface resume actions, but it must not mint new elevated commands.
5. Every mutating operation must emit an `operation_id` and write a checkpoint that conforms to `schemas/checkpoint.schema.json`.

## Checkpoint and Audit Artifacts

The proof workflow must keep these paths stable:

- Checkpoint: `%ProgramData%\AgentSystem\state\operations\<operation_id>.json`
- Audit log: `%ProgramData%\AgentSystem\logs\operations.jsonl`
- Resource manifest: `%ProgramData%\AgentSystem\state\resource-manifest.json`

Artifact access model:

- Elevated helper: read/write
- Unelevated shell: read-only
- UI: structured display only; no raw command synthesis from artifact contents

## Audit Record Minimum

Each audit record appended to `operations.jsonl` should include:

- `timestamp`
- `operation_id`
- `operation_name`
- `phase`
- `caller`
- `requires_elevation`
- `result`
- `elapsed_ms`
- `error_code`

## Signing and Provenance Gate

- Public release requires a code-signing and provenance plan before it can pass M1b/M3 release gates.
- Unsigned builds are internal alpha only and must be labeled as such.
- SmartScreen/trust warnings remain a public-release blocker.

## M1b Exit-Gate Tie-In

This privilege boundary is intentionally narrow so the later installer, helper, and desktop shell can consume structured contracts without broadening host-control scope.
