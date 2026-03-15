#!/usr/bin/env bash
# login.sh — Renueva la autenticacion OAuth de Claude Code en el sandbox
# Usar cuando expire la sesion o para el primer login si no se hizo en setup
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OS="$(uname -s)"

GREEN='\033[0;32m'
BOLD='\033[1m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}>>>${NC} $*"; }
error() { echo -e "${RED}>>>${NC} $*"; exit 1; }

echo ""
echo -e "${BOLD}  Dentro del sandbox ejecuta:${NC}"
echo "    claude login"
echo ""
echo -e "${BOLD}  Cuando termines:${NC}"
echo "    exit"
echo ""

case "$OS" in
  Darwin)
    if ! shuru checkpoint list 2>/dev/null | grep -q "claude-ready"; then
      error "Checkpoint 'claude-ready' no existe. Ejecuta: ./setup.sh"
    fi

    # Eliminar checkpoint anterior si existe
    shuru checkpoint delete claude-authed 2>/dev/null || true

    cd "$SCRIPT_DIR"
    shuru checkpoint create claude-authed \
      --from claude-ready \
      --allow-net \
      --cpus 8 \
      --memory 8192 \
      -- bash -l

    info "Checkpoint 'claude-authed' actualizado."
    ;;

  Linux)
    docker volume create claude-sandbox-auth &>/dev/null || true
    docker run -it --rm \
      --name claude-sandbox-login \
      -v claude-sandbox-auth:/root/.claude \
      claude-sandbox \
      bash -l

    info "Volumen de autenticacion actualizado."
    ;;

  *) error "Sistema operativo no soportado: $OS" ;;
esac
