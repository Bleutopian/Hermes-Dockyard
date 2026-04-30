# Windows Agent System

这是一套面向 Windows 10/11 的 Agent 服务安装与维护程序：

- Windows 侧安装并维护 ClawPanel 桌面版。
- WSL2 侧安装 Ubuntu 24.04 LTS、Docker Engine、Hermes Agent。
- Docker 侧提供一个 Ubuntu 24.04 的 Hermes 工作沙箱容器。
- 运维侧提供统一的 `agent-system` 命令：安装、更新、启动、停止、状态、日志、卸载、打包。

## 依据

- Hermes Agent 原生 Windows 不支持，官方路径是在 WSL2 内安装运行。
- Hermes gateway 在 WSL/Docker/Termux 场景官方推荐 `hermes gateway run`，本项目用 tmux 做常驻。
- Docker Engine 通过 Docker 官方 Ubuntu apt 源安装。
- ClawPanel 桌面版使用 GitHub Releases 的 Windows MSI/EXE 安装包，Windows 桌面版也支持内置自动更新。

## 快速开始

以管理员身份打开 PowerShell：

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\scripts\Install-AgentSystem.ps1
```

安装完成后：

```powershell
.\bin\agent-system.ps1 status
.\bin\agent-system.ps1 logs
```

如果需要配置模型、API Key 或消息平台：

```powershell
.\bin\agent-system.ps1 hermes-setup
```

## 常用维护命令

```powershell
# 更新 WSL 内 Docker/Hermes、重装/覆盖 ClawPanel 最新版
.\bin\agent-system.ps1 update

# 启动 WSL 内 Docker compose 沙箱与 Hermes gateway tmux 会话
.\bin\agent-system.ps1 start

# 停止 Hermes gateway 和 Docker compose 沙箱
.\bin\agent-system.ps1 stop

# 查看 WSL、Docker、Hermes、tmux 状态
.\bin\agent-system.ps1 status

# 打包当前仓库为可分发 zip
.\bin\agent-system.ps1 package

# 卸载计划任务和本管理程序；默认保留 WSL distro 与用户数据
.\bin\agent-system.ps1 uninstall
```

彻底删除 WSL distro 是破坏性操作，需要显式传参：

```powershell
.\scripts\Uninstall-AgentSystem.ps1 -RemoveDistro -RemoveProgramFiles
```

## 默认安装内容

- 管理程序：`%ProgramFiles%\AgentSystem`
- 状态与下载缓存：`%ProgramData%\AgentSystem`
- WSL distro：`Ubuntu-24.04`
- WSL 用户：`agent`
- Windows 计划任务：`AgentSystem-WSL-Startup`
- Docker compose：`/opt/agent-system/docker-compose.yml`
- WSL 运维脚本：
  - `/usr/local/bin/agent-system-start`
  - `/usr/local/bin/agent-system-stop`
  - `/usr/local/bin/agent-system-status`
  - `/usr/local/bin/agent-system-logs`
  - `/usr/local/bin/agent-system-update`

## 配置

默认配置位于 `config/agent-system.json`。常用覆盖参数：

```powershell
.\scripts\Install-AgentSystem.ps1 `
  -DistroName Ubuntu-24.04 `
  -WslUser agent `
  -SkipClawPanel:$false
```

如果 GitHub API 被代理或镜像限制，可以直接指定 ClawPanel 安装包：

```powershell
.\scripts\Install-AgentSystem.ps1 -ClawPanelAssetUrl "https://example.com/ClawPanel_x.x.x_x64_en-US.msi"
```

## 运行模型

1. Windows 计划任务在当前用户登录时调用 WSL。
2. WSL 启动 Docker daemon，并执行 `/opt/agent-system/docker-compose.yml`。
3. Hermes 安装在 WSL 用户 `agent` 下。
4. Hermes gateway 通过 tmux 会话 `hermes-gateway` 常驻：

```bash
tmux attach -t hermes-gateway
```

## 验证

本仓库自带基础静态验证：

```powershell
.\scripts\Test-AgentSystem.ps1
```

该验证解析 PowerShell 文件语法，并检查关键文件是否存在。真正的端到端验证需要在管理员 PowerShell 下运行安装脚本，因为 WSL、Docker、ClawPanel 都涉及系统级安装。

## 外部参考

- Hermes Agent 文档：https://hermes-agent.nousresearch.com/docs/installation/
- Hermes CLI 命令参考：https://hermes-agent.nousresearch.com/docs/reference/cli-commands/
- Docker Engine Ubuntu 安装文档：https://docs.docker.com/engine/install/ubuntu/
- Microsoft WSL 安装文档：https://learn.microsoft.com/en-us/windows/wsl/install
- ClawPanel 仓库与 Release：https://github.com/qingchencloud/clawpanel
