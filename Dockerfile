FROM alpine:3.21

RUN apk update && apk add --no-cache \
    ca-certificates curl wget git bash openssh \
    nodejs npm \
    python3 py3-pip \
    build-base linux-headers \
    sudo

RUN npm install -g @anthropic-ai/claude-code

RUN sed -i 's|/bin/ash|/bin/bash|' /etc/passwd \
    && mkdir -p /root/workspace

WORKDIR /root/workspace

CMD ["bash", "-l"]
