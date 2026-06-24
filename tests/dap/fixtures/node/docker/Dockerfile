FROM node:24-slim

ADD https://github.com/microsoft/vscode-js-debug/releases/download/v1.117.0/js-debug-dap-v1.117.0.tar.gz /tmp/js-debug-dap.tar.gz

RUN mkdir -p /opt/js-debug \
  && tar -xzf /tmp/js-debug-dap.tar.gz -C /opt/js-debug \
  && rm /tmp/js-debug-dap.tar.gz \
  && printf '%s\n' '#!/bin/sh' 'exec node /opt/js-debug/js-debug/src/dapDebugServer.js "$@"' > /usr/local/bin/js-debug-adapter \
  && chmod +x /usr/local/bin/js-debug-adapter

WORKDIR /workspace
