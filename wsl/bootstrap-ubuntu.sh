#!/usr/bin/env bash
set -Eeuo pipefail

AGENT_USER="${AGENT_USER:-agent}"
HERMES_INSTALL_URL="${HERMES_INSTALL_URL:-https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh}"
SKIP_DOCKER="${SKIP_DOCKER:-0}"
SKIP_HERMES="${SKIP_HERMES:-0}"
FORCE_UPDATE="${FORCE_UPDATE:-0}"

STATE_DIR="/var/lib/agent-system"
CONFIG_DIR="/etc/agent-system"
INSTALL_DIR="/opt/agent-system"
RESTART_FLAG="$STATE_DIR/restart-required"

log() {
  printf '[agent-system] %s\n' "$*"
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    printf 'bootstrap-ubuntu.sh must run as root\n' >&2
    exit 1
  fi
}

is_systemd() {
  [ "$(ps -p 1 -o comm= | tr -d ' ')" = "systemd" ]
}

write_wsl_conf() {
  cat >/etc/wsl.conf <<EOF
[boot]
systemd=true

[user]
default=$AGENT_USER
EOF

  if ! is_systemd; then
    touch "$RESTART_FLAG"
  else
    rm -f "$RESTART_FLAG"
  fi
}

install_base_packages() {
  log "Installing base Ubuntu packages"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    git \
    jq \
    lsb-release \
    sudo \
    tmux \
    unzip
}

ensure_user() {
  if ! id "$AGENT_USER" >/dev/null 2>&1; then
    log "Creating WSL user $AGENT_USER"
    useradd -m -s /bin/bash "$AGENT_USER"
  fi

  usermod -aG sudo "$AGENT_USER"
  install -m 0750 -d "/home/$AGENT_USER/.local/bin"
  chown -R "$AGENT_USER:$AGENT_USER" "/home/$AGENT_USER/.local"
}

install_docker() {
  if [ "$SKIP_DOCKER" = "1" ]; then
    log "Skipping Docker install"
    return
  fi

  if ! command -v docker >/dev/null 2>&1 || [ "$FORCE_UPDATE" = "1" ]; then
    log "Installing Docker Engine from Docker apt repository"
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    cat >/etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      docker-ce \
      docker-ce-cli \
      containerd.io \
      docker-buildx-plugin \
      docker-compose-plugin
  fi

  usermod -aG docker "$AGENT_USER"

  if is_systemd; then
    systemctl enable docker >/dev/null 2>&1 || true
    systemctl start docker || true
  else
    service docker start || true
  fi
}

install_hermes() {
  if [ "$SKIP_HERMES" = "1" ]; then
    log "Skipping Hermes install"
    return
  fi

  log "Installing Hermes Agent for $AGENT_USER"
  sudo -H -u "$AGENT_USER" bash -lc "
    set -Eeuo pipefail
    export PATH=\"\$HOME/.local/bin:\$PATH\"
    if ! command -v hermes >/dev/null 2>&1 || [ '$FORCE_UPDATE' = '1' ]; then
      curl -fsSL '$HERMES_INSTALL_URL' | bash
    fi
    grep -q '.local/bin' \"\$HOME/.bashrc\" || printf '\nexport PATH=\"\$HOME/.local/bin:\$PATH\"\n' >> \"\$HOME/.bashrc\"
  "
}

install_compose_payload() {
  if [ "$SKIP_DOCKER" = "1" ]; then
    return
  fi

  log "Installing Docker compose payload"
  install -d "$INSTALL_DIR"
  cp /tmp/agent-system/docker/docker-compose.yml "$INSTALL_DIR/docker-compose.yml"
  cp /tmp/agent-system/docker/Dockerfile.hermes-runtime "$INSTALL_DIR/Dockerfile.hermes-runtime"

  if command -v docker >/dev/null 2>&1; then
    docker compose -f "$INSTALL_DIR/docker-compose.yml" up -d --build || true
  fi
}

write_agent_env() {
  install -d "$CONFIG_DIR"
  {
    printf 'AGENT_USER=%q\n' "$AGENT_USER"
    printf 'HERMES_INSTALL_URL=%q\n' "$HERMES_INSTALL_URL"
    printf 'COMPOSE_FILE=%q\n' "$INSTALL_DIR/docker-compose.yml"
    printf 'HERMES_TMUX_SESSION=%q\n' "hermes-gateway"
  } >"$CONFIG_DIR/env"
  chmod 0644 "$CONFIG_DIR/env"
}

write_runtime_scripts() {
  cat >/usr/local/bin/agent-system-start <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

[ -f /etc/agent-system/env ] && . /etc/agent-system/env
AGENT_USER="${AGENT_USER:-agent}"
COMPOSE_FILE="${COMPOSE_FILE:-/opt/agent-system/docker-compose.yml}"
HERMES_TMUX_SESSION="${HERMES_TMUX_SESSION:-hermes-gateway}"

log() {
  printf '[agent-system] %s\n' "$*"
}

is_systemd() {
  [ "$(ps -p 1 -o comm= | tr -d ' ')" = "systemd" ]
}

start_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    log "Docker is not installed"
    return 0
  fi

  if ! docker info >/dev/null 2>&1; then
    if is_systemd; then
      systemctl start docker || true
    else
      service docker start || true
    fi
  fi
}

start_compose() {
  if command -v docker >/dev/null 2>&1 && [ -f "$COMPOSE_FILE" ]; then
    docker compose -f "$COMPOSE_FILE" up -d --build || true
  fi
}

start_hermes_gateway() {
  if ! id "$AGENT_USER" >/dev/null 2>&1; then
    log "WSL user $AGENT_USER does not exist"
    return 0
  fi

  sudo -H -u "$AGENT_USER" bash -lc "
    export PATH=\"\$HOME/.local/bin:\$PATH\"
    if ! command -v hermes >/dev/null 2>&1; then
      echo '[agent-system] Hermes is not installed'
      exit 0
    fi
    if tmux has-session -t '$HERMES_TMUX_SESSION' 2>/dev/null; then
      echo '[agent-system] Hermes gateway tmux session already running'
    else
      tmux new-session -d -s '$HERMES_TMUX_SESSION' 'bash -lc \"export PATH=\$HOME/.local/bin:\$PATH; hermes gateway run\"'
      echo '[agent-system] Started Hermes gateway tmux session'
    fi
  "
}

start_docker
start_compose
start_hermes_gateway
EOF

  cat >/usr/local/bin/agent-system-stop <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

[ -f /etc/agent-system/env ] && . /etc/agent-system/env
AGENT_USER="${AGENT_USER:-agent}"
COMPOSE_FILE="${COMPOSE_FILE:-/opt/agent-system/docker-compose.yml}"
HERMES_TMUX_SESSION="${HERMES_TMUX_SESSION:-hermes-gateway}"

if id "$AGENT_USER" >/dev/null 2>&1; then
  sudo -H -u "$AGENT_USER" bash -lc "tmux kill-session -t '$HERMES_TMUX_SESSION' 2>/dev/null || true"
fi

if command -v docker >/dev/null 2>&1 && [ -f "$COMPOSE_FILE" ]; then
  docker compose -f "$COMPOSE_FILE" down || true
fi
EOF

  cat >/usr/local/bin/agent-system-status <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

[ -f /etc/agent-system/env ] && . /etc/agent-system/env
AGENT_USER="${AGENT_USER:-agent}"
COMPOSE_FILE="${COMPOSE_FILE:-/opt/agent-system/docker-compose.yml}"
HERMES_TMUX_SESSION="${HERMES_TMUX_SESSION:-hermes-gateway}"

printf 'Ubuntu:  '
lsb_release -ds 2>/dev/null || cat /etc/os-release

printf 'systemd: '
if [ "$(ps -p 1 -o comm= | tr -d ' ')" = "systemd" ]; then
  printf 'enabled\n'
else
  printf 'not active\n'
fi

printf 'Docker:  '
if command -v docker >/dev/null 2>&1; then
  docker --version
  if docker info >/dev/null 2>&1; then
    printf 'Docker daemon: running\n'
  else
    printf 'Docker daemon: stopped\n'
  fi
else
  printf 'not installed\n'
fi

if command -v docker >/dev/null 2>&1 && [ -f "$COMPOSE_FILE" ]; then
  docker compose -f "$COMPOSE_FILE" ps || true
fi

printf 'Hermes:  '
if id "$AGENT_USER" >/dev/null 2>&1; then
  sudo -H -u "$AGENT_USER" bash -lc "
    export PATH=\"\$HOME/.local/bin:\$PATH\"
    if command -v hermes >/dev/null 2>&1; then
      hermes version 2>/dev/null || hermes --version 2>/dev/null || true
      if tmux has-session -t '$HERMES_TMUX_SESSION' 2>/dev/null; then
        echo 'Hermes gateway: tmux session running'
      else
        echo 'Hermes gateway: tmux session stopped'
      fi
      hermes gateway status 2>/dev/null || true
    else
      echo 'not installed'
    fi
  "
else
  printf 'user %s not found\n' "$AGENT_USER"
fi
EOF

  cat >/usr/local/bin/agent-system-logs <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

[ -f /etc/agent-system/env ] && . /etc/agent-system/env
AGENT_USER="${AGENT_USER:-agent}"
HERMES_TMUX_SESSION="${HERMES_TMUX_SESSION:-hermes-gateway}"

if id "$AGENT_USER" >/dev/null 2>&1; then
  sudo -H -u "$AGENT_USER" bash -lc "
    export PATH=\"\$HOME/.local/bin:\$PATH\"
    echo '--- tmux:$HERMES_TMUX_SESSION ---'
    tmux capture-pane -pt '$HERMES_TMUX_SESSION' -S -200 2>/dev/null || true
    echo '--- hermes logs ---'
    if command -v hermes >/dev/null 2>&1; then
      hermes logs --tail 100 2>/dev/null || true
    fi
  "
fi
EOF

  cat >/usr/local/bin/agent-system-update <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

[ -f /etc/agent-system/env ] && . /etc/agent-system/env
AGENT_USER="${AGENT_USER:-agent}"
HERMES_INSTALL_URL="${HERMES_INSTALL_URL:-https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh}"
COMPOSE_FILE="${COMPOSE_FILE:-/opt/agent-system/docker-compose.yml}"

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --only-upgrade \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin || true

if id "$AGENT_USER" >/dev/null 2>&1; then
  sudo -H -u "$AGENT_USER" bash -lc "
    set -Eeuo pipefail
    export PATH=\"\$HOME/.local/bin:\$PATH\"
    if command -v hermes >/dev/null 2>&1; then
      hermes update --backup || true
    else
      curl -fsSL '$HERMES_INSTALL_URL' | bash
    fi
  "
fi

if command -v docker >/dev/null 2>&1 && [ -f "$COMPOSE_FILE" ]; then
  docker compose -f "$COMPOSE_FILE" build --pull || true
fi

/usr/local/bin/agent-system-start
EOF

  chmod 0755 \
    /usr/local/bin/agent-system-start \
    /usr/local/bin/agent-system-stop \
    /usr/local/bin/agent-system-status \
    /usr/local/bin/agent-system-logs \
    /usr/local/bin/agent-system-update
}

main() {
  require_root
  install -d "$STATE_DIR"
  write_wsl_conf
  install_base_packages
  ensure_user
  install_docker
  install_hermes
  install_compose_payload
  write_agent_env
  write_runtime_scripts

  log "Bootstrap complete"
  if [ -f "$RESTART_FLAG" ]; then
    log "WSL restart is required to activate systemd. Windows installer will restart WSL and rerun bootstrap."
  fi
}

main "$@"
