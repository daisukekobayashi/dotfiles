FROM elixir:1.18.4-otp-27-slim

ARG ELIXIR_LS_VERSION=0.29.3

RUN apt-get update \
  && apt-get install -y --no-install-recommends bash ca-certificates curl git unzip \
  && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL \
    "https://github.com/elixir-lsp/elixir-ls/releases/download/v${ELIXIR_LS_VERSION}/elixir-ls-v${ELIXIR_LS_VERSION}.zip" \
    -o /tmp/elixir-ls.zip \
  && mkdir -p /opt/elixir-ls \
  && unzip -q /tmp/elixir-ls.zip -d /opt/elixir-ls \
  && chmod +x /opt/elixir-ls/*.sh \
  && rm /tmp/elixir-ls.zip

RUN ELS_MODE=debug_adapter MIX_ENV=prod SHELL=/bin/bash \
  elixir /opt/elixir-ls/quiet_install.exs
