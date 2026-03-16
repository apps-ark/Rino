FROM alpine:3.21

RUN apk update && apk add --no-cache \
    ca-certificates curl wget git bash openssh \
    nodejs npm \
    python3 py3-pip \
    build-base linux-headers \
    sudo

RUN npm install -g @anthropic-ai/claude-code

# Crear usuario no-root (--dangerously-skip-permissions no permite root)
RUN adduser -D -s /bin/bash -h /home/coder coder \
    && echo "coder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers \
    && mkdir -p /home/coder/workspace \
    && chown -R coder:coder /home/coder

USER coder
WORKDIR /home/coder/workspace

CMD ["bash", "-l"]
