#!/usr/bin/env bash
# setup.sh — Configura el sandbox de Claude Code
# Compatible con macOS (Shuru) y Linux (Docker)
# Uso: ./setup.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${GREEN}>>>${NC} $*"; }
warn()  { echo -e "${YELLOW}>>>${NC} $*"; }
error() { echo -e "${RED}>>>${NC} $*"; exit 1; }

OS="$(uname -s)"

# ------------------------------------------------------------------
# macOS: Shuru
# ------------------------------------------------------------------
setup_macos() {
  info "Detectado: macOS"

  # Verificar Apple Silicon
  if [[ "$(uname -m)" != "arm64" ]]; then
    error "Shuru requiere Apple Silicon (M1/M2/M3/M4). Tu Mac tiene $(uname -m)."
  fi

  # Instalar Shuru si no existe
  if ! command -v shuru &>/dev/null; then
    info "Instalando Shuru..."
    if command -v brew &>/dev/null; then
      brew tap superhq-ai/tap && brew install shuru
    else
      curl -fsSL https://shuru.run/install.sh | sh
    fi
  fi

  info "Shuru $(shuru --version)"

  # Verificar si ya existe el checkpoint
  if shuru checkpoint list 2>/dev/null | grep -q "claude-ready"; then
    warn "Checkpoint 'claude-ready' ya existe. Saltando instalacion."
    warn "Para recrearlo: shuru checkpoint delete claude-ready && ./setup.sh"
  else
    info "Creando VM con Node.js, Python y Claude Code..."
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
      echo ">>> Claude Code $(claude --version)"
    '
  fi

  echo ""
  info "Checkpoint listo. Ahora necesitas autenticarte."
  info "Abriendo VM para login..."
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

  echo ""
  info "Setup completo!"
}

# ------------------------------------------------------------------
# Linux: Docker
# ------------------------------------------------------------------
setup_linux() {
  info "Detectado: Linux"

  if ! command -v docker &>/dev/null; then
    error "Docker no esta instalado. Instalalo desde https://docs.docker.com/engine/install/"
  fi

  if ! docker info &>/dev/null; then
    error "Docker no esta corriendo o tu usuario no tiene permisos. Prueba: sudo usermod -aG docker \$USER"
  fi

  info "Docker $(docker --version | awk '{print $3}')"

  info "Construyendo imagen claude-sandbox..."
  docker build -t claude-sandbox "$SCRIPT_DIR"

  echo ""
  info "Imagen lista. Ahora necesitas autenticarte."
  info "Abriendo contenedor para login..."
  echo ""
  echo -e "${BOLD}  Dentro del contenedor ejecuta:${NC}"
  echo "    claude login"
  echo ""
  echo -e "${BOLD}  Cuando termines, escribe:${NC}"
  echo "    exit"
  echo ""

  # Crear volumen persistente para auth y ejecutar login
  docker volume create claude-sandbox-auth &>/dev/null || true
  docker run -it --rm \
    --name claude-sandbox-login \
    -u coder \
    -v claude-sandbox-auth:/home/coder/.claude \
    claude-sandbox \
    bash -l

  echo ""
  info "Setup completo!"
}

# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------
echo ""
echo -e "${BOLD}  Claude Code Sandbox — Setup${NC}"
echo "  Entorno aislado para ejecutar Claude de forma segura"
echo ""

case "$OS" in
  Darwin) setup_macos ;;
  Linux)  setup_linux ;;
  *)      error "Sistema operativo no soportado: $OS (solo macOS y Linux)" ;;
esac

echo ""
echo -e "${BOLD}  Como usar:${NC}"
echo ""
echo "    ./start.sh                         # sin proyecto"
echo "    ./start.sh ~/mi-proyecto           # con proyecto montado"
echo ""
echo "    # Dentro del sandbox:"
echo "    claude --dangerously-skip-permissions"
echo ""
