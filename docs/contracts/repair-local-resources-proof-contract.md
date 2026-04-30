# `repair-local-resources` proof contract

This document defines the first required privileged proof from the optimized development plan. It is intentionally narrow: prove that the product can perform one safe, rerunnable elevated mutation with structured checkpoints and audit artifacts before broader packaging work is treated as valid.

## Operation intent

- **Operation name**: `repair-local-resources`
- **Operation type**: `repair`
- **Purpose**: copy bundled scripts, schemas, config, and documentation from application resources into `%ProgramFiles%\\AgentSystem`
- **Explicit non-goals**:
  - no arbitrary command execution
  - no WSL distro mutation
  - no Docker or Hermes lifecycle changes
  - no user-content migration

## Required artifacts

- checkpoint: `%ProgramData%\\AgentSystem\\state\\operations\\<operation_id>.json`
- audit log: `%ProgramData%\\AgentSystem\\logs\\operations.jsonl`
- resource manifest: `%ProgramData%\\AgentSystem\\state\\resource-manifest.json`

The checkpoint file must validate against `schemas/checkpoint.schema.json`.

## Structured request

```json
{
  "operation_name": "repair-local-resources",
  "operation_id": "repair-local-resources-20260501-001",
  "caller": {
    "surface": "desktop",
    "session_id": "desktop-session-123"
  },
  "target_root": "%ProgramFiles%\\AgentSystem",
  "resource_roots": [
    "bin",
    "config",
    "docker",
    "docs",
    "schemas",
    "scripts",
    "wsl"
  ]
}
```

## Structured response/events

The helper must emit structured JSON events only. Recommended event names:

- `operation_started`
- `progress`
- `warning`
- `error`
- `operation_completed`

Minimum payload fields:

- `operation_id`
- `operation_name`
- `phase`
- `status`
- `requires_elevation`
- `elapsed_ms`
- `error_code` for failures

## Typed phases

| Order | Phase | Kind | Idempotency | Notes |
| --- | --- | --- | --- | --- |
| 0 | `validate-request` | `preflight` | `idempotent` | Validate allowlisted operation name, target root, and bundled resource availability. |
| 1 | `snapshot-existing-layout` | `preflight` | `idempotent` | Capture current target inventory for audit/debugging. |
| 2 | `copy-bundled-resources` | `copy` | `checkpointed` | Copy only the allowlisted roots into Program Files. |
| 3 | `write-resource-manifest` | `configure` | `checkpointed` | Persist the copied-file manifest used for later verification and repair. |
| 4 | `verify-target-layout` | `verify` | `idempotent` | Confirm target files match the manifest. |
| 5 | `finalize-operation` | `cleanup` | `idempotent` | Mark checkpoint completed and append final audit record. |

## Checkpoint rules

1. Create the checkpoint before the first mutating phase.
2. Update the checkpoint when entering and leaving each phase.
3. Store `resume_command` as the fixed helper invocation for the same `operation_id`.
4. If interruption occurs during a `checkpointed` phase, resume from the last completed phase rather than restarting blindly.
5. `last_error_code` must use stable uppercase codes, for example:
   - `PERMISSION_REQUIRED`
   - `PAYLOAD_NOT_INSTALLED`
   - `NETWORK_UNAVAILABLE`
   - `RESOURCE_COPY_FAILED`
   - `RESOURCE_VERIFY_FAILED`

## Audit requirements

Each audit row must be append-only JSON with:

```json
{
  "operation_id": "repair-local-resources-20260501-001",
  "operation_name": "repair-local-resources",
  "phase": "copy-bundled-resources",
  "caller": "desktop",
  "requires_elevation": true,
  "result": "running",
  "elapsed_ms": 241
}
```

On failure, add `error_code` and a concise `message`. On completion, include the manifest path and final target root.

## Resume proof

The proof is only complete when the team can demonstrate:

1. a run interrupted after `copy-bundled-resources`
2. the checkpoint persisted enough state to resume
3. the resumed run completes without corrupting `%ProgramFiles%\\AgentSystem`
4. the resulting layout matches `resource-manifest.json`
5. the unelevated shell can read the checkpoint and audit outputs afterward

## Review notes for downstream lanes

- **Lane A** should expose `resume_command`, stable error codes, and phase status in backend JSON without removing text-mode CLI output.
- **Lane B** should treat checkpoint and audit files as read-only contracts; the UI should request proof actions, not compose host commands.
- **Later installer work** must not expand the helper surface until this proof is stable and independently verified.
