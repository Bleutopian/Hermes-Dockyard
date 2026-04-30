# Hermes Dockyard

Hermes Dockyard 是面向 Windows 10/11 的本地 Agent 桌面程序与运维底座。目标是把 WSL2 Ubuntu 24.04 LTS、Docker、Hermes Agent、ClawPanel 和后续本机工具 Bridge 做成可安装、可更新、可诊断的开盒即用产品。

当前仓库处于 `0.1.0-alpha.1` 内部 Alpha 阶段：已经有桌面壳、结构化后端契约、只读状态检查、资源修复 proof 和 NSIS 安装包骨架，但还不是完整的一键生产安装器。

## 当前能力

- PowerShell 后端入口：`bin\agent-system.ps1`
- 只读 JSON 检查：
  - `status`
  - `preflight`
- Headless 修复 proof：
  - `repair-local-resources`
  - checkpoint: `%ProgramData%\AgentSystem\state\operations\<operation_id>.json`
  - audit log: `%ProgramData%\AgentSystem\logs\operations.jsonl`
  - manifest: `%ProgramData%\AgentSystem\state\resource-manifest.json`
- Tauri + React 桌面壳：`apps\desktop`
- 内部 Alpha NSIS bundle 配置，资源包含 `bin`、`config`、`docker`、`packaging`、`schemas`、`scripts`、`wsl`

## 快速验证

```powershell
.\scripts\Test-AgentSystem.ps1
```

桌面端验证：

```powershell
cd apps\desktop
npm ci
npm run build
cargo test --manifest-path src-tauri\Cargo.toml
```

生成内部 Alpha 安装包：

```powershell
.\packaging\Build-DesktopAlpha.ps1
```

快速构建但不产出安装包：

```powershell
.\packaging\Build-DesktopAlpha.ps1 -SkipNpmCi -SkipBundle
```

安装包输出位置：

```text
apps\desktop\src-tauri\target\release\bundle\nsis\
```

## 常用命令

```powershell
.\bin\agent-system.ps1 preflight -OutputFormat json
.\bin\agent-system.ps1 status -OutputFormat json
.\bin\agent-system.ps1 repair-local-resources -OutputFormat json
```

使用临时目录运行资源修复 proof：

```powershell
$root = Join-Path $env:TEMP "HermesDockyardProof"
.\bin\agent-system.ps1 repair-local-resources `
  -InstallRoot (Join-Path $root "ProgramData") `
  -ProgramRoot (Join-Path $root "ProgramFiles") `
  -OutputFormat json
```

## 默认布局

- App resources: Tauri `$RESOURCE\resources\*`
- 本地程序资源：`%ProgramFiles%\AgentSystem`
- 状态与下载缓存：`%ProgramData%\AgentSystem`
- WSL distro：`Ubuntu-24.04`
- WSL 用户：`agent`
- Windows 计划任务：`AgentSystem-WSL-Startup`

## 当前限制

- 内部 Alpha 未签名，公开发布前必须完成代码签名与 provenance 方案。
- 桌面程序当前只开放只读 `preflight/status` 探测；资源修复 proof 仍是 headless CLI。
- WSL/Docker/Hermes/ClawPanel 的完整首次安装与断点恢复属于后续 M4。
- Bridge、剪映/CapCut Mate、MemPalace/vector benchmark 尚未实现。
- 干净 Windows VM 上的完整安装/更新/卸载矩阵还未完成。

## 外部参考

- Hermes Agent: https://hermes-agent.nousresearch.com/docs/installation/
- Hermes CLI: https://hermes-agent.nousresearch.com/docs/reference/cli-commands/
- Docker Engine on Ubuntu: https://docs.docker.com/engine/install/ubuntu/
- Microsoft WSL: https://learn.microsoft.com/windows/wsl/install
- ClawPanel: https://github.com/qingchencloud/clawpanel
