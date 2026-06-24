FROM python:3.14-slim

ARG DEBUGPY_VERSION=1.8.17

RUN python -m pip install --no-cache-dir "debugpy==${DEBUGPY_VERSION}"

WORKDIR /workspace
