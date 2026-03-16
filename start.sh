#!/usr/bin/env bash
# start.sh — Levanta el sandbox de Claude Code
# Si no hay setup o login, los ejecuta automaticamente
# Uso: ./start.sh [directorio-a-montar] [--claude]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OS="$(uname -s)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${GREEN}>>>${NC} $*"; }
warn()  { echo -e "${YELLOW}>>>${NC} $*"; }
error() { echo -e "${RED}>>>${NC} $*"; exit 1; }

# Parse args
MOUNT_DIR=""
AUTO_CLAUDE=false
for arg in "$@"; do
  case "$arg" in
    --claude) AUTO_CLAUDE=true ;;
    *) MOUNT_DIR="$arg" ;;
  esac
done

# Comando que se ejecuta dentro del sandbox
INNER_CMD='
  cd /workspace 2>/dev/null || cd ~/workspace
  echo ""
  echo "=== Claude Code Sandbox ==="
  echo "Dir:    $(pwd)"
  echo "Claude: $(claude --version 2>/dev/null || echo "no encontrado")"
  echo "Node:   $(node --version 2>/dev/null)"
  echo ""
  echo "  claude --dangerously-skip-permissions    # modo autonomo"
  echo "  claude                                   # modo interactivo"
  echo ""
  exec bash -l
'

if [ "$AUTO_CLAUDE" = true ]; then
  INNER_CMD='
    cd /workspace 2>/dev/null || cd ~/workspace
    echo ""
    echo "=== Claude Code Sandbox ==="
    echo "Dir: $(pwd)"
    echo ""
    exec claude --dangerously-skip-permissions
  '
fi

# ------------------------------------------------------------------
# macOS: Shuru
# ------------------------------------------------------------------
ensure_shuru() {
  if ! command -v shuru &>/dev/null; then
    info "Shuru no esta instalado. Instalando..."
    if [[ "$(uname -m)" != "arm64" ]]; then
      error "Shuru requiere Apple Silicon (M1/M2/M3/M4)."
    fi
    if command -v brew &>/dev/null; then
      brew tap superhq-ai/tap && brew install shuru
    else
      curl -fsSL https://shuru.run/install.sh | sh
    fi
  fi
}

ensure_checkpoint_base() {
  if shuru checkpoint list 2>/dev/null | grep -q "claude-ready"; then
    return 0
  fi

  info "Primera ejecucion: creando entorno base..."
  info "Esto puede tardar unos minutos..."
  echo ""

  shuru checkpoint create claude-ready \
    --allow-net \
    --cpus 8 \
    --memory 8192 \
    --disk-size 4096 \
    -- sh -c '
    set -eu
    apk update
    apk add --no-cache \
      ca-certificates curl wget git bash openssh sudo \
      nodejs npm \
      python3 py3-pip \
      build-base linux-headers

    npm install -g @anthropic-ai/claude-code

    # Crear usuario no-root para Claude
    adduser -D -s /bin/bash -h /home/coder coder
    echo "coder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

    mkdir -p /home/coder/workspace
    chown -R coder:coder /home/coder

    echo ""
    echo ">>> Node.js $(node --version)"
    echo ">>> npm $(npm --version)"
    echo ">>> Claude Code $(claude --version)"
  '

  info "Entorno base creado."
}

ensure_checkpoint_auth() {
  if shuru checkpoint list 2>/dev/null | grep -q "claude-authed"; then
    return 0
  fi

  echo ""
  info "Necesitas autenticarte con Claude (solo la primera vez)."
  echo ""
  echo -e "${BOLD}  Dentro de la VM ejecuta:${NC}"
  echo "    claude login"
  echo ""
  echo -e "${BOLD}  Cuando termines, escribe:${NC}"
  echo "    exit"
  echo ""

  shuru checkpoint create claude-authed \
    --from claude-ready \
    --allow-net \
    --cpus 8 \
    --memory 8192 \
    -- su - coder -c "bash -l"

  info "Autenticacion guardada."
}

start_macos() {
  ensure_shuru
  ensure_checkpoint_base
  ensure_checkpoint_auth

  MOUNT_FLAG=""
  if [ -n "$MOUNT_DIR" ]; then
    MOUNT_DIR="$(cd "$MOUNT_DIR" && pwd)"
    MOUNT_FLAG="--mount $MOUNT_DIR:/workspace"
    info "Montando: $MOUNT_DIR -> /workspace"
  fi

  info "Levantando VM..."

  cd "$SCRIPT_DIR"

  # shellcheck disable=SC2086
  shuru run --allow-net --from "claude-authed" \
    --cpus 8 \
    --memory 8192 \
    $MOUNT_FLAG \
    -- su - coder -c "$INNER_CMD"
}

# ------------------------------------------------------------------
# Linux: Docker
# ------------------------------------------------------------------
ensure_docker() {
  if ! command -v docker &>/dev/null; then
    error "Docker no esta instalado. Instalalo desde https://docs.docker.com/engine/install/"
  fi
  if ! docker info &>/dev/null; then
    error "Docker no esta corriendo. Prueba: sudo systemctl start docker"
  fi
}

ensure_image() {
  if docker image inspect claude-sandbox &>/dev/null 2>&1; then
    return 0
  fi

  info "Primera ejecucion: construyendo imagen..."
  docker build -t claude-sandbox "$SCRIPT_DIR"
  info "Imagen creada."
}

ensure_auth_volume() {
  docker volume create claude-sandbox-auth &>/dev/null || true

  AUTH_CHECK=$(docker run --rm -v claude-sandbox-auth:/home/coder/.claude claude-sandbox \
    sh -c 'test -f /home/coder/.claude.json && echo "HAS_AUTH" || echo "NO_AUTH"' 2>/dev/null || echo "NO_AUTH")

  if [ "$AUTH_CHECK" = "HAS_AUTH" ]; then
    return 0
  fi

  echo ""
  info "Necesitas autenticarte con Claude (solo la primera vez)."
  echo ""
  echo -e "${BOLD}  Dentro del contenedor ejecuta:${NC}"
  echo "    claude login"
  echo ""
  echo -e "${BOLD}  Cuando termines, escribe:${NC}"
  echo "    exit"
  echo ""

  docker run -it --rm \
    --name claude-sandbox-login \
    -u coder \
    -v claude-sandbox-auth:/home/coder/.claude \
    claude-sandbox \
    bash -l

  info "Autenticacion guardada."
}

start_linux() {
  ensure_docker
  ensure_image
  ensure_auth_volume

  MOUNT_FLAG=""
  if [ -n "$MOUNT_DIR" ]; then
    MOUNT_DIR="$(cd "$MOUNT_DIR" && pwd)"
    MOUNT_FLAG="-v $MOUNT_DIR:/workspace:rw"
    info "Montando: $MOUNT_DIR -> /workspace"
  fi

  info "Levantando contenedor..."

  # shellcheck disable=SC2086
  docker run -it --rm \
    --name claude-sandbox \
    -u coder \
    -v claude-sandbox-auth:/home/coder/.claude \
    $MOUNT_FLAG \
    claude-sandbox \
    bash -c "$INNER_CMD"
}

# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------
case "$OS" in
  Darwin) start_macos ;;
  Linux)  start_linux ;;
  *)      error "Sistema operativo no soportado: $OS" ;;
esac
