#!/usr/bin/env bash
# Install explicitly selected optional Mythic services.

set -Eeuo pipefail
IFS=$'\n\t'

if [[ -n ${MYTHIC_DIR:-} ]]; then
    readonly MYTHIC_DIR
elif [[ -x /opt/mythic/mythic-cli ]]; then
    readonly MYTHIC_DIR=/opt/mythic
elif [[ -x /opt/Mythic/mythic-cli ]]; then
    # Compatibility with installations created by older versions of these scripts.
    readonly MYTHIC_DIR=/opt/Mythic
else
    readonly MYTHIC_DIR=/opt/mythic
fi

log() { printf '[INFO] %s\n' "$*"; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

declare -Ar COMPONENT_URLS=(
    [apollo]='https://github.com/MythicAgents/Apollo.git'
    [athena]='https://github.com/MythicAgents/Athena.git'
    [hades]='https://github.com/MythicAgents/Hades.git'
    [medusa]='https://github.com/MythicAgents/Medusa.git'
    [poseidon]='https://github.com/MythicAgents/poseidon.git'
    [merlin]='https://github.com/MythicAgents/merlin.git'
    [poopsie]='https://github.com/MythicAgents/Poopsie.git'
    [forge]='https://github.com/MythicAgents/forge.git'
    [hydra]='https://github.com/MythicAgents/hydra.git'
    [thanatos]='https://github.com/MythicAgents/thanatos'
    [xenon]='https://github.com/MythicAgents/Xenon'
    [bloodhound]='https://github.com/MythicAgents/bloodhound.git'
    [dll_wrapper]='https://github.com/MythicAgents/dll_wrapper.git'
    [service_wrapper]='https://github.com/MythicAgents/service_wrapper.git'
    [http]='https://github.com/MythicC2Profiles/http.git'
    [httpx]='https://github.com/MythicC2Profiles/httpx.git'
    [dynamichttp]='https://github.com/MythicC2Profiles/dynamichttp'
    [websocket]='https://github.com/MythicC2Profiles/websocket.git'
    [smb]='https://github.com/MythicC2Profiles/smb.git'
    [tcp]='https://github.com/MythicC2Profiles/tcp.git'
    [dns]='https://github.com/MythicC2Profiles/dns.git'
    [basic_logger]='https://github.com/MythicC2Profiles/basic_logger.git'
    [registry_browser]='https://github.com/MythicC2Profiles/registry_browser.git'
    [ldap_browser]='https://github.com/MythicC2Profiles/ldap_browser.git'
)

# Associative arrays have no useful presentation order, so keep the complete
# installation order explicit and deterministic.
declare -ar ALL_COMPONENTS=(
    http httpx dynamichttp websocket smb tcp dns
    apollo athena poseidon merlin poopsie hades medusa thanatos xenon
    forge hydra bloodhound basic_logger
    registry_browser ldap_browser
    dll_wrapper service_wrapper
)

usage() {
    cat <<'EOF'
Usage:
  sudo ./mythic-components.sh COMPONENT [COMPONENT ...]
  sudo ./mythic-components.sh --all

Available components:
  Agents:       apollo athena poseidon merlin poopsie hades medusa thanatos xenon
  Profiles:     http httpx dynamichttp websocket smb tcp dns
  Extensions:   forge hydra basic_logger registry_browser ldap_browser
  Integrations: bloodhound
  Wrappers:     dll_wrapper service_wrapper

Options:
  --all       Install every component listed above
  -h, --help  Show this help

Examples:
  sudo ./mythic-components.sh apollo http
  sudo ./mythic-components.sh athena dns hydra
  sudo ./mythic-components.sh --all

Environment:
  MYTHIC_DIR  Mythic installation directory (default: /opt/mythic; an existing
              legacy /opt/Mythic installation is detected automatically)
EOF
}

[[ ${1:-} != -h && ${1:-} != --help ]] || { usage; exit 0; }
(( $# > 0 )) || { usage >&2; exit 2; }
[[ ${EUID} -eq 0 ]] || die "Run this script as root (for example: sudo $0 ...)."
[[ -x "${MYTHIC_DIR}/mythic-cli" ]] || die "mythic-cli not found in ${MYTHIC_DIR}; run mythic-install.sh first."

if [[ $1 == --all ]]; then
    (( $# == 1 )) || die "--all cannot be combined with individual component names."
    requested_components=("${ALL_COMPONENTS[@]}")
else
    requested_components=("$@")
fi

# Validate the entire request before installing anything.
for component_name in "${requested_components[@]}"; do
    [[ "$component_name" =~ ^[a-z0-9_]+$ ]] || \
        die "Invalid component name '${component_name}'. Run with --help for the catalog."
    [[ -n "${COMPONENT_URLS[$component_name]+present}" ]] || \
        die "Unknown component '${component_name}'. Run with --help for the catalog."
done

cd "$MYTHIC_DIR"
declare -a installed_components=()
declare -a failed_components=()
for component_name in "${requested_components[@]}"; do
    log "Installing ${component_name}."
    if ./mythic-cli install github "${COMPONENT_URLS[$component_name]}"; then
        installed_components+=("$component_name")
    else
        failed_components+=("$component_name")
        printf '[WARN] Failed to install %s; continuing with the remaining components.\n' \
            "$component_name" >&2
    fi
done

log "Starting/reloading Mythic services."
start_failed=false
if ! ./mythic-cli start; then
    start_failed=true
    printf '[WARN] Mythic failed to start/reload.\n' >&2
fi

if (( ${#installed_components[@]} > 0 )); then
    printf -v installed_list '%s, ' "${installed_components[@]}"
    log "Installed successfully: ${installed_list%, }"
fi
if (( ${#failed_components[@]} > 0 )); then
    printf -v failed_list '%s, ' "${failed_components[@]}"
    printf '[ERROR] Failed components: %s\n' "${failed_list%, }" >&2
fi
./mythic-cli status || true

if (( ${#failed_components[@]} > 0 )) || [[ "$start_failed" == true ]]; then
    exit 1
fi
