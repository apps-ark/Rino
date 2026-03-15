# Claude Code Sandbox

Entorno aislado para ejecutar Claude Code con `--dangerously-skip-permissions` sin riesgo para tu maquina, credenciales ni datos personales.

## Requisitos

| | macOS | Linux |
|---|---|---|
| **Motor** | [Shuru](https://shuru.run) (microVM nativa) | [Docker](https://docs.docker.com/engine/install/) |
| **Arch** | Apple Silicon (M1+) | x86_64 / ARM64 |
| **OS** | macOS 14+ (Sonoma) | Cualquier distro con Docker |

## Setup (un solo comando)

```bash
git clone <url-del-repo> claude-sandbox
cd claude-sandbox
./setup.sh
```

El script detecta tu OS y:
- **macOS**: Instala Shuru (si no lo tienes), crea una microVM con todo instalado, y abre una sesion para que hagas `claude login`
- **Linux**: Construye una imagen Docker con todo instalado, crea un volumen persistente para auth, y abre un contenedor para que hagas `claude login`

## Uso diario

```bash
# Sin proyecto — abre un sandbox limpio
./start.sh

# Con proyecto montado
./start.sh ~/mi-proyecto

# Dentro del sandbox
claude --dangerously-skip-permissions
```

## Que incluye el sandbox

- Node.js 22 + npm
- Python 3 + pip
- Git, curl, wget, bash
- Claude Code (ultima version)

## Seguridad

### Que puede hacer

- Ejecutar codigo arbitrario dentro del sandbox
- Acceder a internet en dominios permitidos:
  - `*.anthropic.com` (API de Claude, OAuth)
  - `github.com` / `*.github.com` (repos, API)
  - `registry.npmjs.org` (paquetes npm)
  - `pypi.org` (paquetes Python)

### Que NO puede hacer

- Acceder a tu filesystem real (macOS: overlay read-only, Linux: bind mount explicito)
- Leer tu Keychain, SSH keys, o credenciales del host
- Enviar trafico a dominios no permitidos (solo macOS, via Shuru)
- Ejecutar procesos en tu host
- Persistir cambios entre sesiones (efimero por defecto)

> **Nota sobre Linux/Docker**: Docker no restringe dominios por defecto. Si necesitas restriccion de red en Linux, usa `--network none` o configura reglas de iptables.

## Agregar dominios permitidos (macOS)

Edita `shuru.json`:

```json
{
  "network": {
    "allow": [
      "...dominios existentes...",
      "api.openai.com"
    ]
  }
}
```

Luego recrea el checkpoint:

```bash
shuru checkpoint delete claude-ready
shuru checkpoint delete claude-authed
./setup.sh
```

## Comandos disponibles

| Comando | Que hace |
|---|---|
| `./setup.sh` | Setup inicial (una sola vez) |
| `./start.sh` | Levanta el sandbox |
| `./start.sh ~/proyecto` | Levanta con proyecto montado |
| `./login.sh` | Renueva la autenticacion OAuth |

## Mantenimiento

### Renovar login

```bash
./login.sh
# Dentro: claude login → exit
```

### Actualizar Claude Code

```bash
# macOS
shuru checkpoint create claude-ready \
  --from claude-ready --allow-net \
  -- npm install -g @anthropic-ai/claude-code@latest

# Linux
docker build --no-cache -t claude-sandbox .
```

### Borrar todo y empezar de cero

```bash
# macOS
shuru checkpoint delete claude-authed
shuru checkpoint delete claude-ready

# Linux
docker rmi claude-sandbox
docker volume rm claude-sandbox-auth
```
