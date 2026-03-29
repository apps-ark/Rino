FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl wget git bash openssh-client \
    nodejs npm \
    python3 python3-pip \
    build-essential linux-headers-generic \
    sudo procps less iproute2 jq xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code

# Crear usuario no-root (--dangerously-skip-permissions no permite root)
RUN useradd -m -s /bin/bash coder \
    && echo "coder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers \
    && mkdir -p /home/coder/workspace \
    && chown -R coder:coder /home/coder

# Shell profile: env vars en .bashrc, init en .bash_profile
RUN cat >> /home/coder/.bashrc << 'BASHRC'
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export TERM=xterm-256color
BASHRC

RUN cat > /home/coder/.bash_profile << 'PROFILE'
[ -f ~/.bashrc ] && . ~/.bashrc
eval $(stty size 2>/dev/null | awk '{printf "stty rows %s cols %s", $1, $2}') 2>/dev/null

if [ "$SANDBOX_AUTO_CLAUDE" = "1" ]; then
  cd /workspace 2>/dev/null || cd ~/workspace
  exec claude --dangerously-skip-permissions
fi

if [ -t 1 ]; then
  cd /workspace 2>/dev/null || cd ~/workspace
  echo ""
  echo "=== Rino - Claude Code Sandbox ==="
  echo "Dir:    $(pwd)"
  echo "Claude: $(claude --version 2>/dev/null)"
  echo ""
  echo "  claude --dangerously-skip-permissions"
  echo ""
fi
PROFILE

RUN chown coder:coder /home/coder/.bashrc /home/coder/.bash_profile

USER coder
WORKDIR /home/coder/workspace

CMD ["bash", "--login"]
