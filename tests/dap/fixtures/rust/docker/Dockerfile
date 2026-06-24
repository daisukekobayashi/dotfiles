FROM rust:1.91-slim

ADD https://github.com/vadimcn/vscode-lldb/releases/download/v1.12.2/codelldb-linux-x64.vsix /tmp/codelldb.vsix

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    unzip \
  && rm -rf /var/lib/apt/lists/* \
  && mkdir -p /opt/codelldb \
  && unzip -q /tmp/codelldb.vsix -d /opt/codelldb \
  && rm /tmp/codelldb.vsix \
  && printf '%s\n' '#!/bin/sh' 'exec /opt/codelldb/extension/adapter/codelldb "$@"' > /usr/local/bin/codelldb \
  && chmod +x /usr/local/bin/codelldb

WORKDIR /workspace
