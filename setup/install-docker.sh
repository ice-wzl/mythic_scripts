#!/usr/bin/env bash
# Install Docker Engine from Docker's official apt repository.

set -Eeuo pipefail
IFS=$'\n\t'

readonly MIN_DOCKER_VERSION="20.10.22"

log() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

on_error() {
    local exit_code=$?
    printf '[ERROR] Docker installation failed at line %s (exit code %s).\n' "${BASH_LINENO[0]}" "$exit_code" >&2
    exit "$exit_code"
}
trap on_error ERR

usage() {
    cat <<'EOF'
Usage: sudo ./install-docker.sh

Installs Docker Engine and the Compose v2 plugin on a Debian-family system.

Derivative distributions are resolved to their Debian or Ubuntu upstream when
possible. Set both variables below if automatic detection is incorrect:

  DOCKER_BASE_DISTRO=debian DOCKER_BASE_CODENAME=trixie sudo -E ./install-docker.sh
  DOCKER_BASE_DISTRO=ubuntu DOCKER_BASE_CODENAME=noble sudo -E ./install-docker.sh
EOF
}

case "${1:-}" in
    "") ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "Unknown option: $1" ;;
esac
[[ $# -le 1 ]] || { usage >&2; die "Too many arguments."; }

[[ ${EUID} -eq 0 ]] || die "Run this script as root (for example: sudo $0)."
[[ $(uname -s) == Linux ]] || die "Docker Engine must be installed on Linux."
[[ -r /etc/debian_version ]] || die "This installer supports Debian-family systems only."
[[ -r /etc/os-release ]] || die "Cannot read /etc/os-release."

for command_name in apt-get dpkg; do
    command -v "$command_name" >/dev/null 2>&1 || die "Required command not found: ${command_name}"
done

# Leave a working, sufficiently new Docker installation untouched.
if command -v docker >/dev/null 2>&1; then
    installed_version="$(docker version --format '{{.Server.Version}}' 2>/dev/null || true)"
    if [[ -n "$installed_version" ]] && \
       dpkg --compare-versions "$installed_version" ge "$MIN_DOCKER_VERSION" && \
       docker compose version >/dev/null 2>&1; then
        log "Docker ${installed_version} and Compose v2 are already available; no changes made."
        exit 0
    fi
    warn "The existing Docker installation is incomplete or too old and will be replaced."
fi

# shellcheck disable=SC1091
source /etc/os-release

base_distro="${DOCKER_BASE_DISTRO:-}"
base_codename="${DOCKER_BASE_CODENAME:-}"

if [[ -z "$base_distro" || -z "$base_codename" ]]; then
    upstream_id=""
    upstream_codename=""
    if command -v lsb_release >/dev/null 2>&1 && lsb_release -u -si >/dev/null 2>&1; then
        upstream_id="$(lsb_release -u -si | tr '[:upper:]' '[:lower:]')"
        upstream_codename="$(lsb_release -u -sc | tr '[:upper:]' '[:lower:]')"
    fi

    case "${ID:-}" in
        ubuntu)
            detected_distro=ubuntu
            detected_codename="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
            ;;
        debian)
            detected_distro=debian
            detected_codename="${VERSION_CODENAME:-}"
            ;;
        *)
            case "$upstream_id" in
                ubuntu|debian)
                    detected_distro="$upstream_id"
                    detected_codename="$upstream_codename"
                    ;;
                *)
                    if [[ " ${ID_LIKE:-} " == *" ubuntu "* ]]; then
                        detected_distro=ubuntu
                        detected_codename="${UBUNTU_CODENAME:-}"
                    else
                        detected_distro=debian
                        detected_codename=""
                    fi
                    ;;
            esac
            ;;
    esac

    base_distro="${base_distro:-$detected_distro}"
    base_codename="${base_codename:-$detected_codename}"
fi

# /etc/debian_version gives a reliable upstream major version on many forks.
if [[ "$base_distro" == debian && -z "$base_codename" ]]; then
    debian_version="$(cut -d/ -f1 /etc/debian_version)"
    case "${debian_version%%.*}" in
        11) base_codename=bullseye ;;
        12) base_codename=bookworm ;;
        13|14) base_codename=trixie ;;
    esac
fi

# Kali rolling tracks Debian testing. Docker documents using the corresponding
# Debian release rather than the kali-rolling suite.
if [[ "${ID:-}" == kali && -z "$base_codename" ]]; then
    base_codename=trixie
fi

[[ "$base_distro" == debian || "$base_distro" == ubuntu ]] || \
    die "DOCKER_BASE_DISTRO must be either 'debian' or 'ubuntu'."
[[ "$base_codename" =~ ^[a-z0-9][a-z0-9.-]*$ ]] || \
    die "Could not determine the upstream release. Set DOCKER_BASE_DISTRO and DOCKER_BASE_CODENAME; see --help."

readonly repo_url="https://download.docker.com/linux/${base_distro}"
readonly architecture="$(dpkg --print-architecture)"

log "Detected ${PRETTY_NAME:-Debian-family Linux}."
log "Using Docker's ${base_distro}/${base_codename} repository for ${architecture}."

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl
command -v curl >/dev/null 2>&1 || die "curl was not installed successfully."

# Validate the selected suite before changing apt configuration.
curl -fsI "${repo_url}/dists/${base_codename}/Release" >/dev/null || \
    die "Docker does not publish ${base_distro}/${base_codename}. Override the upstream values shown in --help."

conflicting_packages=(
    docker.io docker-compose docker-compose-v2 docker-doc docker-buildx
    podman-docker containerd runc
)
installed_conflicts=()
for package_name in "${conflicting_packages[@]}"; do
    if dpkg-query -W -f='${db:Status-Abbrev}' "$package_name" 2>/dev/null | grep -q '^ii'; then
        installed_conflicts+=("$package_name")
    fi
done
if (( ${#installed_conflicts[@]} )); then
    log "Removing packages that conflict with Docker CE: ${installed_conflicts[*]}"
    apt-get remove -y "${installed_conflicts[@]}"
fi

install -m 0755 -d /etc/apt/keyrings
curl -fsSL "${repo_url}/gpg" -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

cat >/etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: ${repo_url}
Suites: ${base_codename}
Components: stable
Architectures: ${architecture}
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

if command -v systemctl >/dev/null 2>&1; then
    systemctl enable --now docker
elif command -v service >/dev/null 2>&1; then
    service docker start
fi

docker info >/dev/null 2>&1 || die "Docker was installed, but the daemon is not reachable."
docker compose version >/dev/null 2>&1 || die "Docker Compose v2 was not installed correctly."
installed_version="$(docker version --format '{{.Server.Version}}')"
dpkg --compare-versions "$installed_version" ge "$MIN_DOCKER_VERSION" || \
    die "Docker ${installed_version} is older than Mythic's minimum ${MIN_DOCKER_VERSION}."

log "Docker ${installed_version} installed successfully."
docker compose version
