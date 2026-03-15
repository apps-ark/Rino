#!/usr/bin/env bash
# gui.sh — Lanza la interfaz grafica de Claude Code Sandbox
# Uso: ./gui.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GUI_DIR="$SCRIPT_DIR/gui"
PUBLIC_DIR="$GUI_DIR/public"
XTERM_DIR="$PUBLIC_DIR/xterm"
PORT="${PORT:-3456}"

RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

info() { echo -e "${GREEN}>>>${NC} $*"; }
error() { echo -e "${RED}>>>${NC} $*"; exit 1; }

# 1. Verificar Node.js
if ! command -v node &>/dev/null; then
  error "Node.js no esta instalado. Instalalo desde https://nodejs.org"
fi

NODE_MAJOR=$(node -e "console.log(process.versions.node.split('.')[0])")
if [ "$NODE_MAJOR" -lt 18 ]; then
  error "Se requiere Node.js >= 18 (tienes $(node --version))"
fi

# 2. Instalar dependencias si no existen
if [ ! -d "$GUI_DIR/node_modules" ]; then
  info "Instalando dependencias..."
  cd "$GUI_DIR" && npm install --production 2>&1 | tail -3
fi

# 3. Descargar xterm.js si no existe
if [ ! -f "$XTERM_DIR/xterm.js" ]; then
  info "Descargando xterm.js..."
  mkdir -p "$XTERM_DIR"

  XTERM_VERSION="5.3.0"
  FIT_VERSION="0.8.0"

  curl -fsSL "https://cdn.jsdelivr.net/npm/xterm@${XTERM_VERSION}/lib/xterm.js" -o "$XTERM_DIR/xterm.js"
  curl -fsSL "https://cdn.jsdelivr.net/npm/xterm@${XTERM_VERSION}/css/xterm.css" -o "$XTERM_DIR/xterm.css"
  curl -fsSL "https://cdn.jsdelivr.net/npm/xterm-addon-fit@${FIT_VERSION}/lib/xterm-addon-fit.js" -o "$XTERM_DIR/xterm-addon-fit.js"

  info "xterm.js descargado"
fi

# 4. Iniciar servidor
info "Iniciando GUI en http://localhost:$PORT"

cd "$GUI_DIR"
PORT=$PORT node server.js &
SERVER_PID=$!

# Esperar a que el servidor inicie
sleep 1

# 5. Abrir navegador
OS="$(uname -s)"
if [ "$OS" = "Darwin" ]; then
  open "http://localhost:$PORT"
elif command -v xdg-open &>/dev/null; then
  xdg-open "http://localhost:$PORT"
else
  info "Abre en tu navegador: http://localhost:$PORT"
fi

echo ""
echo -e "${BOLD}Claude Code Sandbox GUI${NC}"
echo "Corriendo en http://localhost:$PORT"
echo "Presiona Ctrl+C para detener"
echo ""

# Esperar al servidor
wait $SERVER_PID
