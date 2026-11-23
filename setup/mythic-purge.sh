#!/bin/sh
# Compatibility bootstrap: this script intentionally uses Bash features.
# When launched using `sh mythic-purge.sh`, switch to Bash first.
if [ -z "${BASH_VERSION:-}" ]; then
  command -v bash >/dev/null 2>&1 || { echo '[ERROR] Bash is required.' >&2; exit 1; }
  exec bash "$0" "$@"
fi
# Mythic purge v2 - complete, syntax-checked edition.
# Purge an existing Mythic installation and put a clean checkout at /opt/Mythic.
# Intentionally DOES NOT start Mythic after cloning/building.
set -Eeuo pipefail

MYTHIC_DIR='/opt/Mythic'
REPO_URL='https://github.com/its-a-feature/Mythic.git'
PROJECT='mythic'
STAGE=''

die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }
info() { printf '[+] %s\n' "$*"; }
cleanup() { if [[ -n "$STAGE" && -d "$STAGE" ]]; then rm -rf -- "$STAGE"; fi; }
trap cleanup EXIT
trap 'printf "[ERROR] Reset interrupted at line %s. Check Docker resources before retrying.\n" "$LINENO" >&2' ERR

[[ $EUID -eq 0 ]] || die 'Run with sudo: sudo bash mythic-purge-fixed.sh'
for command in git docker make mktemp; do
  command -v "$command" >/dev/null 2>&1 || die "Missing command: $command"
done
docker info >/dev/null 2>&1 || die 'Docker daemon is not reachable.'
docker compose version >/dev/null 2>&1 || die 'Docker Compose plugin is required.'
[[ -d /opt ]] || die '/opt is missing.'
[[ ! -L "$MYTHIC_DIR" ]] || die 'Refusing to delete a symlink at /opt/Mythic.'
if [[ -e "$MYTHIC_DIR" ]]; then
  [[ -d "$MYTHIC_DIR" ]] || die '/opt/Mythic exists but is not a directory.'
  if [[ -n "$(ls -A "$MYTHIC_DIR")" ]]; then
    [[ -d "$MYTHIC_DIR/.git" || -f "$MYTHIC_DIR/mythic-cli" || -f "$MYTHIC_DIR/Makefile" ]] || \
      die '/opt/Mythic does not appear to be a Mythic checkout; refusing to delete it.'
  fi
fi

# Read the project name without executing the old .env as shell code.
if [[ -f "$MYTHIC_DIR/.env" ]]; then
  configured="$(sed -n 's/^[[:space:]]*COMPOSE_PROJECT_NAME[[:space:]]*=[[:space:]]*//p' "$MYTHIC_DIR/.env" | tail -n 1 | tr -d '\r\"\047')"
  if [[ -n "$configured" ]]; then PROJECT="$configured"; fi
fi
[[ "$PROJECT" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] || die "Unsafe Compose project name: $PROJECT"

printf '\nThis will PERMANENTLY DELETE:\n'
printf '  - %s and everything in it (including .env, agents, and downloaded files)\n' "$MYTHIC_DIR"
printf '  - Docker containers/networks/volumes belonging to project: %s\n' "$PROJECT"
printf '  - Leftover Docker resources named mythic_* or mythic-*\n'
printf '  - Mythic database, users, operations, payloads, and callbacks\n'
printf '\nOther Docker projects and their volumes will not be pruned.\n'
read -r -p 'Type DELETE-MYTHIC to continue: ' answer
[[ "$answer" == 'DELETE-MYTHIC' ]] || die 'Cancelled.'

# Prepare the new checkout FIRST. An unreachable GitHub won't destroy the old installation.
info 'Cloning a fresh Mythic checkout into a temporary staging directory...'
STAGE="$(mktemp -d /opt/.mythic-reinstall.XXXXXXXX)"
git clone --depth 1 "$REPO_URL" "$STAGE/Mythic"

# Find only Mythic containers: project label OR familiar Mythic container prefix.
declare -A containers=()
while IFS= read -r id; do [[ -n "$id" ]] && containers["$id"]=1; done < <(
  docker ps -aq --filter "label=com.docker.compose.project=$PROJECT"
)
while IFS='|' read -r id name; do
  case "$name" in
    mythic_*|mythic-* ) [[ -n "$id" ]] && containers["$id"]=1 ;;
  esac
done < <(docker ps -a --format '{{.ID}}|{{.Names}}')

# Capture attached named/anonymous volumes BEFORE deleting containers.
declare -A volumes=()
for id in "${!containers[@]}"; do
  while IFS= read -r volume; do
    [[ -n "$volume" ]] && volumes["$volume"]=1
  done < <(docker inspect --format '{{range .Mounts}}{{if eq .Type "volume"}}{{println .Name}}{{end}}{{end}}' "$id")

  # External host bind-mounted PostgreSQL data is dangerous to wipe automatically.
  while IFS='|' read -r source destination; do
    [[ -n "$source" ]] || continue
    if [[ "$destination" == /var/lib/postgresql* && "$source" != "$MYTHIC_DIR"/* ]]; then
      die "PostgreSQL is bind-mounted outside /opt/Mythic at: $source. Review and remove that data manually; no resources have been deleted."
    fi
  done < <(docker inspect --format '{{range .Mounts}}{{if eq .Type "bind"}}{{printf "%s|%s\n" .Source .Destination}}{{end}}{{end}}' "$id")
done

# Capture Compose-labeled and plainly named orphan volumes even if no containers exist.
while IFS= read -r volume; do [[ -n "$volume" ]] && volumes["$volume"]=1; done < <(
  docker volume ls -q --filter "label=com.docker.compose.project=$PROJECT"
)
while IFS= read -r volume; do
  case "$volume" in
    mythic_*|mythic-* ) volumes["$volume"]=1 ;;
    "$PROJECT"_*|"$PROJECT"-* ) volumes["$volume"]=1 ;;
  esac
done < <(docker volume ls --format '{{.Name}}')

info 'Stopping and removing the old Mythic Compose stack, where available...'
if [[ -d "$MYTHIC_DIR" ]]; then
  (
    cd "$MYTHIC_DIR"
    if [[ -f docker-compose.yml || -f docker-compose.yaml || -f compose.yml || -f compose.yaml ]]; then
      docker compose -p "$PROJECT" down --volumes --remove-orphans || \
        info 'Compose down could not finish; cleaning up containers and volumes directly.'
    fi
  )
fi

info 'Removing leftover Mythic containers...'
for id in "${!containers[@]}"; do
  if docker container inspect "$id" >/dev/null 2>&1; then
    docker rm -f -v "$id"
  fi
done

info 'Removing Mythic named volumes, including previously orphaned volumes...'
for volume in "${!volumes[@]}"; do
  if docker volume inspect "$volume" >/dev/null 2>&1; then
    docker volume rm "$volume" || die "Could not remove volume '$volume'; refusing to claim a clean install."
  fi
done

info 'Removing leftover Mythic networks...'
declare -A networks=()
while IFS= read -r id; do [[ -n "$id" ]] && networks["$id"]=1; done < <(
  docker network ls -q --filter "label=com.docker.compose.project=$PROJECT"
)
while IFS='|' read -r id name; do
  case "$name" in
    mythic_*|mythic-*|"$PROJECT"_*|"$PROJECT"-* ) [[ -n "$id" ]] && networks["$id"]=1 ;;
  esac
done < <(docker network ls --format '{{.ID}}|{{.Name}}')
for id in "${!networks[@]}"; do
  if docker network inspect "$id" >/dev/null 2>&1; then
    docker network rm "$id" || die "Could not remove network $id."
  fi
done

# Confirm there are no remaining Mythic containers/volumes before overwriting the checkout.
if docker ps -aq --filter "label=com.docker.compose.project=$PROJECT" | grep -q .; then
  die "Compose project '$PROJECT' still has containers."
fi
for volume in "${!volumes[@]}"; do
  if docker volume inspect "$volume" >/dev/null 2>&1; then
    die "Volume '$volume' still exists."
  fi
done

info 'Deleting the old /opt/Mythic directory...'
rm -rf -- "$MYTHIC_DIR"
info 'Moving the clean checkout into /opt/Mythic...'
mv -- "$STAGE/Mythic" "$MYTHIC_DIR"

info 'Building mythic-cli (does not start Mythic services)...'
make -C "$MYTHIC_DIR"

printf '\n[SUCCESS] Mythic was purged and freshly cloned at %s\n' "$MYTHIC_DIR"
printf '[SUCCESS] Mythic services were NOT started.\n\n'
printf 'When you are ready to initialize a NEW database and start:\n'
printf '  cd /opt/Mythic && sudo ./mythic-cli start\n'
printf '\nNote: Docker images may remain cached, but they do not preserve Mythic database state.\n'
