# Hermes Dockyard Desktop (M2 Read-Only Scaffold)

This subtree is the Lane B desktop shell for the Hermes Dockyard / Agent System plan.

## Scope

- Tauri v2 + React + TypeScript scaffold
- Read-only M2 views:
  - Welcome
  - Preflight
  - Dashboard
  - Logs
  - Settings
  - Tools
  - Video Automation
- Mock M1 backend fixtures
- Fixed allowlisted placeholders for real read-only `preflight` and `status` probing

## Commands

```powershell
npm install --prefix apps/desktop
npm run build --prefix apps/desktop
npm run tauri -- dev --no-watch
cargo test --manifest-path apps/desktop/src-tauri/Cargo.toml
```

## Notes

- The Rust bridge only exposes read-only `preflight` and `status`.
- Real integration is intentionally placeholder-grade until Lane A lands the JSON contract.
- No privileged or mutating operations are surfaced in this scaffold.