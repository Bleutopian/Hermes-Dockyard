# Repair Local Resources Proof Contract

`repair-local-resources` is the headless proof operation for the M1b/M2b mutation model.

## Purpose

Safely reconcile bundled app resources into `%ProgramFiles%\AgentSystem` without touching WSL distro data.

## Operation Identity

- `operation_name`: `repair-local-resources`
- `requires_elevation`: `true` when writing under `%ProgramFiles%\AgentSystem`
- Checkpoint schema: `schemas/checkpoint.schema.json`
- Reserved operation envelope path: `schemas/operation.schema.json` (documentation reference only in this lane)

## Allowed Inputs

The helper must accept a structured request with these fields only:

```json
{
  "operation_id": "<stable unique id>",
  "operation_name": "repair-local-resources",
  "caller": "desktop-shell | cli",
  "source_root": "<bundled app resources root>",
  "target_root": "%ProgramFiles%\\AgentSystem",
  "resource_manifest_path": "%ProgramData%\\AgentSystem\\state\\resource-manifest.json",
  "resume": false
}
```

Constraints:

- `source_root` must resolve to bundled application resources only.
- `target_root` is fixed to `%ProgramFiles%\AgentSystem`.
- No WSL paths, arbitrary destinations, or arbitrary executables are allowed.

## Typed Phases and Idempotency

| Phase | Intent | Idempotency rule |
| --- | --- | --- |
| `validate-bundle` | Confirm bundled scripts, schemas, config, and manifest inputs exist | Retriable; no mutation |
| `checkpoint-started` | Persist initial checkpoint before copy work begins | Write-once per `operation_id`, then reconcile on resume |
| `copy-resources` | Copy bundled scripts/schemas/config into `%ProgramFiles%\\AgentSystem` | Reconcile; reruns must overwrite only managed files |
| `write-resource-manifest` | Persist the copied-resource manifest to `%ProgramData%\\AgentSystem\\state\\resource-manifest.json` | Reconcile; last successful manifest wins |
| `checkpoint-completed` | Mark checkpoint/result complete and append final audit entry | Write-once completion record |

The helper must write checkpoint updates before, during, and after the mutating phases so interruption can resume from the last successful phase boundary.

## Required Artifacts

- Checkpoint: `%ProgramData%\AgentSystem\state\operations\<operation_id>.json`
- Audit log: `%ProgramData%\AgentSystem\logs\operations.jsonl`
- Resource manifest: `%ProgramData%\AgentSystem\state\resource-manifest.json`

The copied Program Files tree must match `resource-manifest.json` after a successful run.

## Checkpoint Expectations

Each persisted checkpoint must include at least:

- `operation_id`
- `operation_name`
- `phase`
- `started_at`
- `updated_at`
- `requires_elevation`
- `reboot_required`
- `resume_command`
- `last_error_code`
- `recovery_action`

Recommended proof values:

- `reboot_required`: `false`
- `resume_command`: `agent-system repair-local-resources --resume <operation_id>`
- `recovery_action`: `Retry the allowlisted repair-local-resources operation.`

## Audit Expectations

Every phase transition should append a structured audit record containing:

- `timestamp`
- `operation_id`
- `operation_name`
- `phase`
- `caller`
- `result`
- `elapsed_ms`
- `error_code`

## Non-Goals

- No WSL distro repair
- No Docker/Hermes mutation
- No ClawPanel install/update
- No arbitrary file copy outside AgentSystem-managed roots

## Resume Safety

If the process is interrupted:

1. The unelevated shell reads `%ProgramData%\AgentSystem\state\operations\<operation_id>.json`.
2. The shell surfaces the recorded `resume_command` verbatim.
3. The elevated helper resumes from the last completed typed phase.
4. Already-reconciled files remain safe to copy again.
