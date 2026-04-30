# Agent System privilege boundary

This document records the lane-C review gates from `.omx/plans/development-plan-optimized.md` for the initial A/B/C execution slice. It defines what must stay unelevated, what may cross the UAC boundary, and what contracts downstream desktop work must consume.

## Review summary for the initial lanes

- **Lane A - backend JSON/preflight**: backend work must keep CLI text mode intact while adding structured JSON/event output. The desktop shell and future helpers may only consume structured output; they must never scrape human-readable status text.
- **Lane B - desktop shell**: the Tauri shell stays read-only until privileged mutation contracts are proven. It may render status, preflight, logs, diagnostics preview, and checkpoint/audit data, but it may not directly shell out to arbitrary host commands.
- **Lane C - privilege boundary and checkpoints**: mutating work must be modeled as allowlisted operations with typed phases, checkpoint persistence, and audit logs before packaging is treated as product-valid.

## Trust boundary

### Unelevated surfaces

The unelevated desktop app and normal CLI session may perform only read-only or preflight work:

- `status`
- `preflight`
- log viewing
- diagnostics preview/export preparation
- checkpoint/audit inspection
- settings edits that do not mutate protected system paths

These surfaces must use structured request/response contracts only. They cannot trigger arbitrary PowerShell, Bash, or `cmd.exe` execution.

### Elevated helper surface

An elevated helper is the only host surface allowed to mutate protected Windows or WSL resources. Initial allowlisted operations are:

- `repair-local-resources`
- startup task registration or repair
- WSL feature install
- WSL distro install or repair
- Program Files writes
- destructive uninstall steps
- ClawPanel installer execution

Every elevated operation must declare:

1. a fixed operation name
2. structured input with schema validation
3. structured output/events
4. typed phases with idempotency metadata
5. checkpoint persistence
6. audit-log emission

## Non-negotiable guardrails

1. **No arbitrary shell execution from UI**  
   Desktop commands must map to a fixed allowlist. Free-form command strings, path injection, or "advanced mode" shell passthrough are out of scope.

2. **Explicit UAC only on mutation**  
   Read-only status and diagnostics stay unelevated. UAC prompts are allowed only when the requested operation crosses the mutating boundary.

3. **Structured IO only**  
   Desktop and helper communication must use stable JSON payloads and stable error codes. Human text remains for CLI compatibility, not for machine parsing.

4. **Auditable operations**  
   Elevated work must append an audit record with:
   - `operation_id`
   - `operation_name`
   - `phase`
   - `caller`
   - `requires_elevation`
   - `result`
   - `elapsed_ms`
   - `error_code` when applicable

5. **Resume before polish**  
   If an operation can partially mutate state, it must checkpoint enough information to resume or fail safely before the desktop installer flow is considered product-valid.

## Checkpoint contract

`schemas/checkpoint.schema.json` is the canonical schema for mutating operation checkpoints. It intentionally carries:

- stable `operation_id`
- allowlisted `operation_name`
- typed `phase` with `kind` and `idempotency`
- `requires_elevation`
- `reboot_required`
- `resume_command`
- `last_error_code`
- structured `recovery_action`
- artifact pointers for checkpoint, audit log, and resource manifest files

This gives Lane A a structured backend target and Lane B a stable desktop contract without forcing either lane to parse host text output.

## Proof requirement for the first privileged workflow

The first required proof is `repair-local-resources`, a safe rerunnable operation that copies bundled scripts, schemas, config, and docs into `%ProgramFiles%\\AgentSystem` without touching WSL payload data. The detailed proof contract lives in `docs/contracts/repair-local-resources-proof-contract.md`.

The proof must show:

- the operation is allowlisted
- the operation emits checkpoints before/during/after mutation
- interruption can resume safely
- the unelevated app can read resulting checkpoint/audit artifacts
- the copied Program Files layout matches a resource manifest

## Release gate implications

- An installer alpha is **not** product-valid until the privileged proof exists.
- Public release remains blocked without a signing/provenance plan.
- Bridge, localhost services, and other optional tooling must remain behind this same allowlisted boundary.
