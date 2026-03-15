#!/usr/bin/env bash
# start.sh — Levanta el sandbox de Claude Code
# Uso: ./start.sh [directorio-a-montar]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MOUNT_DIR="${1:-}"
OS="$(uname -s)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${GREEN}>>>${NC} $*"; }
warn()  { echo -e "${YELLOW}>>>${NC} $*"; }
error() { echo -e "${RED}>>>${NC} $*"; exit 1; }

# ------------------------------------------------------------------
# macOS: Shuru
# ------------------------------------------------------------------
start_macos() {
  if ! command -v shuru &>/dev/null; then
    error "Shuru no esta instalado. Ejecuta: ./setup.sh"
  fi

  # Elegir checkpoint
  CHECKPOINT="claude-authed"
  if ! shuru checkpoint list 2>/dev/null | grep -q "$CHECKPOINT"; then
    CHECKPOINT="claude-ready"
    if ! shuru checkpoint list 2>/dev/null | grep -q "$CHECKPOINT"; then
      error "No hay checkpoints. Ejecuta: ./setup.sh"
    fi
    warn "No se encontro 'claude-authed'. Usando 'claude-ready'."
    warn "Necesitaras hacer 'claude login' manualmente."
    warn "Para persistir el login: ./login.sh"
  fi

  MOUNT_FLAG=""
  if [ -n "$MOUNT_DIR" ]; then
    MOUNT_DIR="$(cd "$MOUNT_DIR" && pwd)"
    MOUNT_FLAG="--mount $MOUNT_DIR:/workspace"
    info "Montando: $MOUNT_DIR -> /workspace"
  fi

  info "Levantando VM desde checkpoint '$CHECKPOINT'..."

  cd "$SCRIPT_DIR"

  # shellcheck disable=SC2086
  shuru run --allow-net --from "$CHECKPOINT" \
    --cpus 8 \
    --memory 8192 \
    $MOUNT_FLAG \
    -- bash -c '
    cd /workspace 2>/dev/null || cd ~/workspace
    echo ""
    echo "=== Claude Code Sandbox (Shuru VM) ==="
    echo "Dir:    $(pwd)"
    echo "Claude: $(claude --version 2>/dev/null || echo "no encontrado")"
    echo "Node:   $(node --version 2>/dev/null)"
    echo ""
    echo "  claude --dangerously-skip-permissions    # modo autonomo"
    echo "  claude                                   # modo interactivo"
    echo ""
    exec bash -l
  '
}

# ------------------------------------------------------------------
# Linux: Docker
# ------------------------------------------------------------------
start_linux() {
  if ! command -v docker &>/dev/null; then
    error "Docker no esta instalado. Ejecuta: ./setup.sh"
  fi

  if ! docker image inspect claude-sandbox &>/dev/null 2>&1; then
    error "Imagen 'claude-sandbox' no encontrada. Ejecuta: ./setup.sh"
  fi

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
    -v claude-sandbox-auth:/root/.claude \
    $MOUNT_FLAG \
    claude-sandbox \
    bash -c '
    cd /workspace 2>/dev/null || cd ~/workspace
    echo ""
    echo "=== Claude Code Sandbox (Docker) ==="
    echo "Dir:    $(pwd)"
    echo "Claude: $(claude --version 2>/dev/null || echo "no encontrado")"
    echo "Node:   $(node --version 2>/dev/null)"
    echo ""
    echo "  claude --dangerously-skip-permissions    # modo autonomo"
    echo "  claude                                   # modo interactivo"
    echo ""
    exec bash -l
  '
}

# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------
case "$OS" in
  Darwin) start_macos ;;
  Linux)  start_linux ;;
  *)      error "Sistema operativo no soportado: $OS" ;;
esac
