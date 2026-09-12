#!/usr/bin/env bash
# Install and start an unmodified Mythic core instance.
# Prerequisite: Docker Engine >= 20.10.22 with the Compose v2 plugin.

set -Eeuo pipefail
IFS=$'\n\t'

readonly MYTHIC_REPO="${MYTHIC_REPO:-https://github.com/its-a-feature/Mythic.git}"
if [[ -n ${MYTHIC_DIR:-} ]]; then
    readonly MYTHIC_DIR
elif [[ -d /opt/mythic/.git ]]; then
    readonly MYTHIC_DIR=/opt/mythic
elif [[ -d /opt/Mythic/.git ]]; then
    # Compatibility with installations created by older versions of these scripts.
    readonly MYTHIC_DIR=/opt/Mythic
else
    readonly MYTHIC_DIR=/opt/mythic
fi
readonly MYTHIC_REF="${MYTHIC_REF:-}"
readonly MIN_DOCKER_VERSION="20.10.22"

log() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

on_error() {
    local exit_code=$?
    printf '[ERROR] Installation failed at line %s (exit code %s).\n' "${BASH_LINENO[0]}" "$exit_code" >&2
    exit "$exit_code"
}
trap on_error ERR

usage() {
    cat <<'EOF'
Usage: sudo ./mythic-install.sh [--update]

Installs Mythic core and starts its default containers. It intentionally does
not install agents, C2 profiles, loggers, or other optional services.

Options:
  --update  Fast-forward an existing Mythic checkout before rebuilding the CLI
  -h, --help

Environment overrides:
  MYTHIC_DIR   Installation directory (default: /opt/mythic; an existing legacy
               /opt/Mythic installation is detected automatically)
  MYTHIC_REPO  Git repository URL
  MYTHIC_REF   Branch or tag to clone (default: repository default branch)
EOF
}

update_existing=false
case "${1:-}" in
    "") ;;
    --update) update_existing=true ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "Unknown option: $1" ;;
esac
[[ $# -le 1 ]] || { usage >&2; die "Too many arguments."; }

[[ ${EUID} -eq 0 ]] || die "Run this script as root (for example: sudo $0)."
[[ $(uname -s) == Linux ]] || die "Mythic must be installed on Linux."
[[ -r /etc/debian_version ]] || die "This installer supports Debian-family systems only."

for command_name in apt-get dpkg docker; do
    command -v "$command_name" >/dev/null 2>&1 || die "Required command not found: ${command_name}"
done

docker_server_version="$(docker version --format '{{.Server.Version}}' 2>/dev/null)" || \
    die "Docker is installed, but its daemon is unavailable. Run install-docker.sh or start Docker."
dpkg --compare-versions "$docker_server_version" ge "$MIN_DOCKER_VERSION" || \
    die "Docker ${docker_server_version} is too old; Mythic requires ${MIN_DOCKER_VERSION} or newer."
docker compose version >/dev/null 2>&1 || \
    die "Docker Compose v2 is required ('docker compose'). Run install-docker.sh first."

export DEBIAN_FRONTEND=noninteractive
log "Installing host prerequisites."
apt-get update
apt-get install -y --no-install-recommends ca-certificates git make
for command_name in git make; do
    command -v "$command_name" >/dev/null 2>&1 || die "Required command not found after package installation: ${command_name}"
done

if command -v nproc >/dev/null 2>&1 && (( $(nproc) < 2 )); then
    warn "Mythic recommends at least 2 CPU cores."
fi
if [[ -r /proc/meminfo ]]; then
    memory_kib="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
    (( memory_kib >= 4 * 1024 * 1024 )) || warn "Mythic recommends at least 4 GB of RAM."
fi

if [[ -d "${MYTHIC_DIR}/.git" ]]; then
    log "Using existing Mythic checkout at ${MYTHIC_DIR}."
    if [[ "$update_existing" == true ]]; then
        [[ -z "$MYTHIC_REF" ]] || die "MYTHIC_REF is only used for a new installation."
        [[ -z "$(git -C "$MYTHIC_DIR" status --porcelain)" ]] || \
            die "The existing Mythic checkout has local changes; refusing to update it."
        log "Fast-forwarding the existing checkout."
        git -C "$MYTHIC_DIR" pull --ff-only
    fi
elif [[ -e "$MYTHIC_DIR" ]]; then
    die "${MYTHIC_DIR} exists but is not a Mythic Git checkout. Move it and run again."
else
    install -d -m 0755 "$(dirname "$MYTHIC_DIR")"
    log "Cloning Mythic into ${MYTHIC_DIR}."
    clone_args=(--depth 1 --single-branch)
    if [[ -n "$MYTHIC_REF" ]]; then
        clone_args+=(--branch "$MYTHIC_REF")
    fi
    git clone "${clone_args[@]}" "$MYTHIC_REPO" "$MYTHIC_DIR"
fi

log "Building mythic-cli."
make -C "$MYTHIC_DIR"
[[ -x "${MYTHIC_DIR}/mythic-cli" ]] || die "make completed without creating mythic-cli."

log "Starting vanilla Mythic services."
(
    cd "$MYTHIC_DIR"
    ./mythic-cli start
)

printf '\n'
log "Mythic core is installed at ${MYTHIC_DIR}."
log "Web interface: https://<server-address>:7443"
log "Default username: mythic_admin"
log "The generated password is stored in ${MYTHIC_DIR}/.env; do not share that file."
printf '\nUseful commands:\n'
printf '  cd %q\n' "$MYTHIC_DIR"
printf '  sudo ./mythic-cli status\n'
printf '  sudo ./mythic-cli health\n'
