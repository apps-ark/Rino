#!/usr/bin/env bash
# start.sh — Levanta el sandbox de Claude Code
# Uso: ./start.sh [--claude] [--setup] [--login] [directorio]
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
ONLY_SETUP=false
ONLY_LOGIN=false

for arg in "$@"; do
  case "$arg" in
    --claude) AUTO_CLAUDE=true ;;
    --setup)  ONLY_SETUP=true ;;
    --login)  ONLY_LOGIN=true ;;
    *) MOUNT_DIR="$arg" ;;
  esac
done

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

do_setup_macos() {
  ensure_shuru

  if shuru checkpoint list 2>/dev/null | grep -q "claude-ready"; then
    info "Entorno base ya existe. Saltando."
    return 0
  fi

  info "Creando entorno base (Node.js, Python, Claude Code)..."
  info "Esto tarda unos minutos la primera vez..."
  echo ""

  shuru checkpoint create claude-ready \
    --allow-net \
    --cpus 8 \
    --memory 8192 \
    --disk-size 4096 \
    -- sh -c '
    apk update
    apk add --no-cache \
      ca-certificates curl wget git bash openssh sudo \
      nodejs npm \
      python3 py3-pip \
      build-base linux-headers

    npm install -g @anthropic-ai/claude-code

    addgroup coder
    adduser -D -G coder -s /bin/bash coder
    echo "coder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
    mkdir -p /home/coder/workspace
    chown -R coder:coder /home/coder

    echo "export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" >> /home/coder/.bashrc
    echo "export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" >> /home/coder/.profile
    chown coder:coder /home/coder/.bashrc /home/coder/.profile

    echo ""
    echo ">>> Node.js $(node --version)"
    echo ">>> npm $(npm --version)"
    echo ">>> Claude $(su - coder -c "export PATH=/usr/local/bin:\$PATH && claude --version")"
  '

  info "Entorno base creado."
}

do_login_macos() {
  ensure_shuru

  if ! shuru checkpoint list 2>/dev/null | grep -q "claude-ready"; then
    info "Primero necesito crear el entorno base..."
    do_setup_macos
  fi

  # Borrar checkpoint anterior si existe
  shuru checkpoint delete claude-authed 2>/dev/null || true

  info "Iniciando login de Claude Code..."
  info "Se abrira una URL en la terminal. Copia y pegala en tu navegador."
  echo ""

  shuru checkpoint create claude-authed \
    --from claude-ready \
    --allow-net \
    --cpus 8 \
    --memory 8192 \
    -- su - coder -c '
    echo ""
    echo "========================================="
    echo "  Login de Claude Code"
    echo "========================================="
    echo ""
    echo "  Se abrira un flujo de autenticacion."
    echo "  Copia la URL y abrela en tu navegador."
    echo ""
    echo "  Cuando termine el login, esta ventana"
    echo "  se cerrara automaticamente."
    echo "========================================="
    echo ""
    claude login
    echo ""
    echo ">>> Login completado! Cerrando..."
    sleep 2
  '

  info "Login guardado en checkpoint."
}

start_macos() {
  ensure_shuru

  # Si no hay checkpoint base, crear
  if ! shuru checkpoint list 2>/dev/null | grep -q "claude-ready"; then
    do_setup_macos
  fi

  # Si no hay auth, hacer login
  if ! shuru checkpoint list 2>/dev/null | grep -q "claude-authed"; then
    do_login_macos
  fi

  MOUNT_FLAG=""
  if [ -n "$MOUNT_DIR" ]; then
    MOUNT_DIR="$(cd "$MOUNT_DIR" && pwd)"
    MOUNT_FLAG="--mount $MOUNT_DIR:/workspace"
    info "Montando: $MOUNT_DIR -> /workspace"
  fi

  INNER_CMD='
    cd /workspace 2>/dev/null || cd ~/workspace
    echo ""
    echo "=== Rino - Claude Code Sandbox ==="
    echo "Dir:    $(pwd)"
    echo "Claude: $(claude --version 2>/dev/null)"
    echo ""
    echo "  claude --dangerously-skip-permissions"
    echo ""
    exec bash -l
  '

  if [ "$AUTO_CLAUDE" = true ]; then
    INNER_CMD='
      cd /workspace 2>/dev/null || cd ~/workspace
      exec claude --dangerously-skip-permissions
    '
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

do_setup_linux() {
  ensure_docker

  if docker image inspect claude-sandbox &>/dev/null 2>&1; then
    info "Imagen ya existe. Saltando."
    return 0
  fi

  info "Construyendo imagen..."
  docker build -t claude-sandbox "$SCRIPT_DIR"
  docker volume create claude-sandbox-auth &>/dev/null || true
  info "Imagen creada."
}

do_login_linux() {
  ensure_docker

  if ! docker image inspect claude-sandbox &>/dev/null 2>&1; then
    do_setup_linux
  fi

  docker volume create claude-sandbox-auth &>/dev/null || true

  info "Iniciando login de Claude Code..."
  echo ""

  docker run -it --rm \
    --name claude-sandbox-login \
    -u coder \
    -v claude-sandbox-auth:/home/coder/.claude \
    claude-sandbox \
    bash -c '
    echo ""
    echo "========================================="
    echo "  Login de Claude Code"
    echo "========================================="
    echo ""
    claude login
    echo ""
    echo ">>> Login completado!"
    sleep 2
  '

  info "Login guardado."
}

start_linux() {
  ensure_docker

  if ! docker image inspect claude-sandbox &>/dev/null 2>&1; then
    do_setup_linux
  fi

  docker volume create claude-sandbox-auth &>/dev/null || true

  # Verificar auth
  AUTH_CHECK=$(docker run --rm -u coder -v claude-sandbox-auth:/home/coder/.claude claude-sandbox \
    sh -c 'test -d /home/coder/.claude && ls /home/coder/.claude/ 2>/dev/null | grep -q . && echo "HAS_AUTH" || echo "NO_AUTH"' 2>/dev/null || echo "NO_AUTH")

  if [ "$AUTH_CHECK" != "HAS_AUTH" ]; then
    do_login_linux
  fi

  MOUNT_FLAG=""
  if [ -n "$MOUNT_DIR" ]; then
    MOUNT_DIR="$(cd "$MOUNT_DIR" && pwd)"
    MOUNT_FLAG="-v $MOUNT_DIR:/workspace:rw"
    info "Montando: $MOUNT_DIR -> /workspace"
  fi

  INNER_CMD='
    cd /workspace 2>/dev/null || cd ~/workspace
    echo ""
    echo "=== Rino - Claude Code Sandbox ==="
    echo "Dir:    $(pwd)"
    echo "Claude: $(claude --version 2>/dev/null)"
    echo ""
    echo "  claude --dangerously-skip-permissions"
    echo ""
    exec bash -l
  '

  if [ "$AUTO_CLAUDE" = true ]; then
    INNER_CMD='
      cd /workspace 2>/dev/null || cd ~/workspace
      exec claude --dangerously-skip-permissions
    '
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
  Darwin)
    if [ "$ONLY_SETUP" = true ]; then do_setup_macos; exit 0; fi
    if [ "$ONLY_LOGIN" = true ]; then do_login_macos; exit 0; fi
    start_macos
    ;;
  Linux)
    if [ "$ONLY_SETUP" = true ]; then do_setup_linux; exit 0; fi
    if [ "$ONLY_LOGIN" = true ]; then do_login_linux; exit 0; fi
    start_linux
    ;;
  *) error "Sistema operativo no soportado: $OS" ;;
esac
