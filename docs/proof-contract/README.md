# Proof Contract Index

M1b proof-contract artifacts live here.

- `privilege-boundary.md` defines the unelevated vs elevated helper split, allowlisting rules, artifact access, and signing/provenance gate.
- `repair-local-resources.md` defines the headless proof operation, typed phases, idempotency rules, and checkpoint/audit artifact expectations.
- `../../schemas/checkpoint.schema.json` is the checkpoint contract consumed by resumable mutating operations.

These documents are the documentation-first contract until the backend lane lands the reserved `schemas/operation.schema.json` envelope.
