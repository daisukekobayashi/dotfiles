#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/bootstrap-e2e.sh [options]

Run the dotfiles bootstrap flow in a fresh Docker container.

Options:
  --image IMAGE       Container image: debian:bookworm-slim or ubuntu:24.04
                      (default: debian:bookworm-slim)
  --suite SUITE       Suite to run: dry-run or all (default: dry-run)
  --github-auth MODE  GitHub auth source: auto, none, or gh (default: auto)
  -h, --help          Show this help

Examples:
  scripts/bootstrap-e2e.sh --image debian:bookworm-slim --suite dry-run
  scripts/bootstrap-e2e.sh --image ubuntu:24.04 --suite all
EOF
}

log() {
  printf '[bootstrap-e2e] %s\n' "$*"
}

die() {
  printf '[bootstrap-e2e] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    die "Required command not found: $1"
  fi
}

validate_image() {
  case "$1" in
    debian:bookworm-slim | ubuntu:24.04) ;;
    *)
      die "Unsupported image: $1"
      ;;
  esac
}

validate_suite() {
  case "$1" in
    dry-run | all) ;;
    *)
      die "Unsupported suite: $1"
      ;;
  esac
}

validate_github_auth() {
  case "$1" in
    auto | none | gh) ;;
    *)
      die "Unsupported GitHub auth mode: $1"
      ;;
  esac
}

summarize_bootstrap_output() {
  local output_log="$1"
  local pattern='(^|[^[:alnum:]_])(\[WARN\]|\[ERROR\]|E[0-9]+:|warning:|error:|failed|failure)([^[:alnum:]_]|$)'

  log "Warning/error summary:"
  if ! LC_ALL=C grep -Eain -- "${pattern}" "${output_log}" | sed 's/^/[bootstrap-e2e]   /'; then
    log "  none found"
  fi
}

image="debian:bookworm-slim"
suite="dry-run"
github_auth="auto"
github_token=""
github_auth_source="none"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --image)
      [ "$#" -ge 2 ] || die "--image requires a value"
      image="$2"
      shift 2
      ;;
    --suite)
      [ "$#" -ge 2 ] || die "--suite requires a value"
      suite="$2"
      shift 2
      ;;
    --github-auth)
      [ "$#" -ge 2 ] || die "--github-auth requires a value"
      github_auth="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

validate_image "${image}"
validate_suite "${suite}"
validate_github_auth "${github_auth}"
require_cmd docker
require_cmd git
require_cmd tar
case "${github_auth}" in
  none)
    ;;
  gh)
    require_cmd gh
    github_token="$(gh auth token)" || die "Failed to read GitHub token from gh auth"
    [ -n "${github_token}" ] || die "gh auth token returned an empty token"
    github_auth_source="gh"
    ;;
  auto)
    if [ -n "${GITHUB_TOKEN:-}" ]; then
      github_token="${GITHUB_TOKEN}"
      github_auth_source="env"
    elif command -v gh >/dev/null 2>&1 && github_token="$(gh auth token 2>/dev/null)" && [ -n "${github_token}" ]; then
      github_auth_source="gh"
    else
      github_token=""
      github_auth_source="none"
    fi
    ;;
esac

repo_root="$(git rev-parse --show-toplevel)"
cd "${repo_root}"

# shellcheck disable=SC2016 # The script is evaluated inside the container.
container_script='
set -euo pipefail

case "${BOOTSTRAP_E2E_SUITE}" in
  dry-run | all) ;;
  *)
    printf "[bootstrap-e2e] ERROR: Unsupported suite in container: %s\n" "${BOOTSTRAP_E2E_SUITE}" >&2
    exit 1
    ;;
esac

export DEBIAN_FRONTEND=noninteractive
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
apt-get update
apt-get install -y --no-install-recommends \
  autoconf \
  bash \
  bison \
  build-essential \
  ca-certificates \
  cmake \
  curl \
  default-jdk-headless \
  gawk \
  git \
  gnupg \
  gzip \
  libbz2-dev \
  libclang-dev \
  libevent-dev \
  libffi-dev \
  libgdbm-dev \
  libgl1-mesa-dev \
  libglu1-mesa-dev \
  liblua5.4-dev \
  liblzma-dev \
  libncurses-dev \
  libreadline-dev \
  libsqlite3-dev \
  libssl-dev \
  libwebkit2gtk-4.1-dev \
  libwxgtk3.2-dev \
  libxml2-dev \
  libxmlsec1-dev \
  libyaml-dev \
  lua5.4 \
  make \
  passwd \
  pipx \
  pkg-config \
  sudo \
  tar \
  tk-dev \
  unixodbc-dev \
  unzip \
  vim-nox \
  wget \
  xz-utils \
  zip \
  zlib1g-dev \
  zsh
rm -rf /var/lib/apt/lists/*

useradd --create-home --shell /bin/bash bootstrap
install -d -o bootstrap -g bootstrap /work/dotfiles /work/tmp
tar -C /work/dotfiles -xf -
chown -R bootstrap:bootstrap /work/dotfiles /work/tmp

setup_dry_run=1
if [ "${BOOTSTRAP_E2E_SUITE}" = "all" ]; then
  setup_dry_run=0
fi

sudo_env=(
  HOME=/home/bootstrap
  SETUP_HOME=/home/bootstrap
  SETUP_TMPDIR=/work/tmp
  SETUP_DOTFILES_ROOT=/work/dotfiles
  SETUP_DRY_RUN="${setup_dry_run}"
  SETUP_MISE_STRICT=0
  LANG=C.UTF-8
  LC_ALL=C.UTF-8
  GIT_TERMINAL_PROMPT=0
  GIT_ASKPASS=/bin/false
)

sudo_args=(-H -u bootstrap)
if [ -n "${GITHUB_TOKEN:-}" ]; then
  sudo_args+=(--preserve-env=GITHUB_TOKEN)
fi

exec sudo "${sudo_args[@]}" env \
  "${sudo_env[@]}" \
  bash -lc "cd /work/dotfiles && ./setup.sh all"
'

log "Image: ${image}"
log "Suite: ${suite}"
log "GitHub auth: ${github_auth} (${github_auth_source})"
log "Streaming tracked files into container; the host repo is not mounted."

output_log="$(mktemp "${TMPDIR:-/tmp}/bootstrap-e2e-output.XXXXXX")"
cleanup() {
  rm -f "${output_log}"
}
trap cleanup EXIT

run_docker() {
  local docker_env_args=(--env "BOOTSTRAP_E2E_SUITE=${suite}")
  if [ -n "${github_token}" ]; then
    docker_env_args+=(--env GITHUB_TOKEN)
    GITHUB_TOKEN="${github_token}" \
      docker run --rm -i \
        "${docker_env_args[@]}" \
        "${image}" \
        bash -lc "${container_script}"
  else
    docker run --rm -i \
      "${docker_env_args[@]}" \
      "${image}" \
      bash -lc "${container_script}"
  fi
}

set +e
git ls-files -z |
  tar --null --files-from - --create --file - |
  run_docker 2>&1 |
  tee "${output_log}"
pipeline_status=("${PIPESTATUS[@]}")
set -e

summarize_bootstrap_output "${output_log}"

if [ "${pipeline_status[2]}" -ne 0 ]; then
  exit "${pipeline_status[2]}"
fi

for status_code in "${pipeline_status[@]}"; do
  if [ "${status_code}" -ne 0 ]; then
    exit "${status_code}"
  fi
done
