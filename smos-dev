#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKERFILE_DIR="${DOCKERFILE_DIR:-$SCRIPT_DIR}"
CONTAINERFILE_INPUT="${SMOS_DEV_CFILE:-Containerfile.ubuntu}"
CONTAINERFILE_EXPLICIT=0
CONTAINERFILE_PATH=""
HOST_USER="${USER:-$(id -un)}"
CONTAINER_USER="${SMOS_DEV_CONTAINER_USER:-$HOST_USER}"
BASE_HOST_DIR="${SMOS_DEV_HOST_ROOT:-${HOME}}"
BASE_CONTAINER_DIR="${SMOS_DEV_CONTAINER_ROOT:-/workspace}"
STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/smos-dev"
HOST_OS="$(uname -s)"

WORK_INPUT="smos-dev"   # default if not specified
NETWORK_MODE="${SMOS_DEV_NETWORK_MODE:-default}"
PROXY_URL="${SMOS_DEV_PROXY_URL:-}"
PROFILE="${SMOS_DEV_PROFILE:-}"
RUNTIME="${SMOS_DEV_RUNTIME:-auto}"
RUNTIME_CMD=""

http_proxy="${HTTP_PROXY:-${http_proxy:-}}"
https_proxy="${HTTPS_PROXY:-${https_proxy:-}}"
no_proxy="${NO_PROXY:-${no_proxy:-}}"

get_default_profile() {
  local from_image=""

  if [[ -f "$CONTAINERFILE_PATH" ]]; then
    from_image="$(awk 'toupper($1) == "FROM" { print $2; exit }' "$CONTAINERFILE_PATH")"
  fi

  if [[ -n "$from_image" ]]; then
    printf '%s\n' "$from_image"
  else
    printf 'default\n'
  fi
}

resolve_containerfile_path() {
  case "$CONTAINERFILE_INPUT" in
    /*)
      printf '%s\n' "$CONTAINERFILE_INPUT"
      ;;
    *)
      printf '%s\n' "${DOCKERFILE_DIR}/${CONTAINERFILE_INPUT}"
      ;;
  esac
}

sanitize_profile() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_.-]/-/g'
}

trim_trailing_slashes() {
  local path="$1"

  while [[ "$path" != "/" && "$path" == */ ]]; do
    path="${path%/}"
  done

  printf '%s\n' "$path"
}

resolve_work_host_path() {
  local input="$1"
  local resolved=""

  case "$input" in
    "~")
      resolved="$HOME"
      ;;
    "~/"*)
      resolved="${HOME}/${input#~/}"
      ;;
    /*)
      resolved="$input"
      ;;
    *)
      resolved="${BASE_HOST_DIR}/${input}"
      ;;
  esac

  trim_trailing_slashes "$resolved"
}

derive_container_subpath() {
  local host_path="$1"
  local subpath=""

  case "$host_path" in
    "$HOME")
      subpath="home"
      ;;
    "$HOME"/*)
      subpath="${host_path#"$HOME"/}"
      ;;
    /)
      subpath="root"
      ;;
    /*)
      subpath="${host_path#/}"
      ;;
    *)
      subpath="$host_path"
      ;;
  esac

  if [[ -z "$subpath" ]]; then
    subpath="smos-work"
  fi

  printf '%s\n' "$subpath"
}

initialize_runtime_vars() {
  CONTAINERFILE_PATH="$(resolve_containerfile_path)"
  PROFILE="${PROFILE:-$(get_default_profile)}"
  PROFILE_SLUG="$(sanitize_profile "$PROFILE")"
  WORK_HOST_PATH="$(resolve_work_host_path "$WORK_INPUT")"
  WORK_CONTAINER_SUBPATH="$(derive_container_subpath "$WORK_HOST_PATH")"
  IMAGE_NAME="${SMOS_DEV_IMAGE_NAME:-smos-dev-${PROFILE_SLUG}:latest}"
  CONTAINER_NAME="smos-dev-${PROFILE_SLUG}"
  HOST_DIR="$WORK_HOST_PATH"
  CONTAINER_DIR="${BASE_CONTAINER_DIR}/${WORK_CONTAINER_SUBPATH}"
  STATE_BASENAME="${STATE_DIR}/${PROFILE_SLUG}"
  RUNTIME_STATE_FILE="${STATE_BASENAME}.runtime"
  IMAGE_STATE_FILE=""
  WORK_STATE_FILE=""
}

set_runtime_state_paths() {
  IMAGE_STATE_FILE="${STATE_BASENAME}.${RUNTIME}.image_tag"
  WORK_STATE_FILE="${STATE_BASENAME}.${RUNTIME}.work_mount"
}

require_option_value() {
  local option_name="$1"
  local option_value="${2:-}"

  if [[ -z "$option_value" ]]; then
    echo "Missing value for $option_name"
    exit 1
  fi
}

initialize_runtime_vars

runtime_installed() {
  command -v "$1" >/dev/null 2>&1
}

runtime_exists_in_state() {
  [[ -f "$RUNTIME_STATE_FILE" ]]
}

read_runtime_state() {
  cat "$RUNTIME_STATE_FILE"
}

write_runtime_state() {
  printf '%s\n' "$RUNTIME" > "$RUNTIME_STATE_FILE"
}

write_work_state() {
  cat > "$WORK_STATE_FILE" <<EOF
${HOST_DIR}
${CONTAINER_DIR}
EOF
}

read_work_state() {
  if [[ ! -f "$WORK_STATE_FILE" ]]; then
    return 1
  fi

  mapfile -t WORK_STATE_VALUES < "$WORK_STATE_FILE"
  WORK_STATE_HOST_DIR="${WORK_STATE_VALUES[0]:-}"
  WORK_STATE_CONTAINER_DIR="${WORK_STATE_VALUES[1]:-}"
}

inspect_container_work_state() {
  local mount_line=""

  mount_line="$("$RUNTIME_CMD" inspect \
    --format '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}|{{.Destination}}{{println}}{{end}}{{end}}' \
    "$CONTAINER_NAME" 2>/dev/null | head -n1)"

  if [[ -z "$mount_line" ]]; then
    return 1
  fi

  INSPECT_WORK_HOST_DIR="${mount_line%%|*}"
  INSPECT_WORK_CONTAINER_DIR="${mount_line#*|}"
}

container_uses_requested_workdir() {
  WORK_STATE_HOST_DIR=""
  WORK_STATE_CONTAINER_DIR=""
  INSPECT_WORK_HOST_DIR=""
  INSPECT_WORK_CONTAINER_DIR=""

  if read_work_state; then
    [[ "$WORK_STATE_HOST_DIR" == "$HOST_DIR" && "$WORK_STATE_CONTAINER_DIR" == "$CONTAINER_DIR" ]]
    return
  fi

  if inspect_container_work_state; then
    [[ "$INSPECT_WORK_HOST_DIR" == "$HOST_DIR" && "$INSPECT_WORK_CONTAINER_DIR" == "$CONTAINER_DIR" ]]
    return
  fi

  return 1
}

set_runtime() {
  RUNTIME="$1"
  RUNTIME_CMD="$1"
  set_runtime_state_paths
}

prompt_for_runtime() {
  local answer=""

  while true; do
    read -r -p "Choose container runtime for new container [docker/podman]: " answer
    case "${answer,,}" in
      docker|podman)
        set_runtime "${answer,,}"
        return
        ;;
      *)
        echo "Please enter 'docker' or 'podman'."
        ;;
    esac
  done
}

select_runtime() {
  local saved_runtime=""
  local has_docker=0
  local has_podman=0

  if runtime_exists_in_state; then
    saved_runtime="$(read_runtime_state)"

    if [[ "$RUNTIME" != "auto" && "$RUNTIME" != "$saved_runtime" ]]; then
      echo "Runtime mismatch for '$CONTAINER_NAME': state says '$saved_runtime', requested '$RUNTIME'."
      exit 1
    fi

    set_runtime "$saved_runtime"
    return
  fi

  if [[ "$RUNTIME" == "docker" || "$RUNTIME" == "podman" ]]; then
    set_runtime "$RUNTIME"
    return
  fi

  if runtime_installed docker; then
    has_docker=1
  fi

  if runtime_installed podman; then
    has_podman=1
  fi

  if (( has_docker == 1 && has_podman == 0 )); then
    set_runtime docker
  elif (( has_docker == 0 && has_podman == 1 )); then
    set_runtime podman
  elif (( has_docker == 1 && has_podman == 1 )); then
    prompt_for_runtime
  else
    echo "Neither 'docker' nor 'podman' was found in PATH."
    exit 1
  fi
}

get_platform_setup_line() {
  case "$HOST_OS" in
    Darwin)
      printf '%s\n' "Install Docker Desktop or Podman Desktop, then ensure the chosen CLI works in your shell."
      ;;
    Linux)
      printf '%s\n' "Install Docker Engine or Podman, then ensure your user can run the chosen CLI."
      ;;
    *)
      printf '%s\n' "Install Docker or Podman and ensure the chosen CLI works in your shell."
      ;;
  esac
}

print_help() {
  cat <<EOF
Usage:
  $(basename "$0") [--work PATH] [--profile NAME] [--runtime NAME] [--network MODE] [--proxy URL] [--cfile FILE] [--help]

Start or attach to a development container for a named workspace.

Options:
  --work PATH       Workspace path. Default: '$WORK_INPUT'
  --profile NAME    Container profile. Default: '$PROFILE'
  --runtime NAME    docker | podman | auto. Default: '$RUNTIME'
  --network MODE    default | none | proxy-only. Default: '$NETWORK_MODE'
  --proxy URL       Required with '--network proxy-only' unless SMOS_DEV_PROXY_URL is set.
  --cfile FILE      Containerfile path. Default: '$CONTAINERFILE_INPUT'
  --help, -h        Show this help text and exit.

Environment:
  SMOS_DEV_CONTAINER_USER  In-container username. Default: USER / id -un
  SMOS_DEV_HOST_ROOT       Base directory for relative work paths. Default: '${HOME}'
  SMOS_DEV_CONTAINER_ROOT  Container workspace root. Default: '/workspace'
  SMOS_DEV_RUNTIME         Default runtime. Default: '$RUNTIME'
  SMOS_DEV_NETWORK_MODE    Default network mode. Default: '$NETWORK_MODE'
  SMOS_DEV_PROFILE         Default profile. Default: first selected container file FROM image
  SMOS_DEV_CFILE           Default container file. Default: 'Containerfile.ubuntu'
  SMOS_DEV_IMAGE_NAME      Override built image tag. Default: '$IMAGE_NAME'
  SMOS_DEV_PROXY_URL       Default proxy URL
  DOCKERFILE_DIR          Container file directory. Default: script directory
  XDG_STATE_HOME          State root. Default: '${HOME}/.local/state'

Examples:
  $(basename "$0") --work api
  $(basename "$0") --runtime podman --work ~/code/my-project
  $(basename "$0") --cfile Containerfile.debian --work api
  $(basename "$0") --profile debian:13.1 --work /srv/dev/api
  $(basename "$0") --network proxy-only --proxy http://127.0.0.1:8080 --work api

Notes:
  $(get_platform_setup_line)
  See README.md for setup, state files, platform notes, and security caveats.
EOF
}

########################################
# Parse arguments
########################################
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      print_help
      exit 0
      ;;
    --profile)
      require_option_value "--profile" "${2:-}"
      PROFILE="$2"
      shift 2
      ;;
    --runtime)
      require_option_value "--runtime" "${2:-}"
      RUNTIME="${2,,}"
      shift 2
      ;;
    --network)
      require_option_value "--network" "${2:-}"
      NETWORK_MODE="$2"
      shift 2
      ;;
    --proxy)
      require_option_value "--proxy" "${2:-}"
      PROXY_URL="$2"
      shift 2
      ;;
    --cfile)
      require_option_value "--cfile" "${2:-}"
      CONTAINERFILE_INPUT="$2"
      CONTAINERFILE_EXPLICIT=1
      shift 2
      ;;
    --work)
      require_option_value "--work" "${2:-}"
      WORK_INPUT="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

initialize_runtime_vars

require_runtime_value() {
  case "$RUNTIME" in
    auto|docker|podman)
      ;;
    *)
      echo "Invalid runtime: $RUNTIME"
      echo "Supported values: auto, docker, podman"
      exit 1
      ;;
  esac
}

########################################
# Image handling
########################################
CURRENT_IMAGE=""

load_current_image() {
  if [[ -f "$IMAGE_STATE_FILE" ]]; then
    CURRENT_IMAGE="$(cat "$IMAGE_STATE_FILE")"
  else
    CURRENT_IMAGE="$IMAGE_NAME"
  fi
}

image_exists_locally() {
  "$RUNTIME_CMD" image inspect "$1" >/dev/null 2>&1
}

require_runtime_installed() {
  if ! runtime_installed "$RUNTIME_CMD"; then
    echo "$RUNTIME_CMD is required but was not found in PATH"
    exit 1
  fi
}

runtime_ready() {
  "$RUNTIME_CMD" info >/dev/null 2>&1
}

require_runtime_ready() {
  if runtime_ready; then
    return
  fi

  case "$RUNTIME_CMD:$HOST_OS" in
    docker:Darwin)
      echo "Docker is installed but not ready. Start Docker Desktop and try again."
      ;;
    docker:Linux)
      echo "Docker is installed but not ready. Start the Docker daemon and ensure your user can access it."
      ;;
    podman:Darwin)
      echo "Podman is installed but not ready. Start the Podman machine and try again."
      ;;
    podman:Linux)
      echo "Podman is installed but not ready. Run 'podman info' to inspect the local setup."
      ;;
    *)
      echo "$RUNTIME_CMD is installed but not ready. Run '$RUNTIME_CMD info' for details."
      ;;
  esac

  exit 1
}

require_container_user() {
  if [[ -z "$CONTAINER_USER" ]]; then
    echo "Container username is required. Set SMOS_DEV_CONTAINER_USER or USER."
    exit 1
  fi
}

require_profile() {
  if [[ -z "$PROFILE" || -z "$PROFILE_SLUG" ]]; then
    echo "Profile is required and must contain at least one valid character."
    exit 1
  fi
}

require_valid_network_mode() {
  case "$NETWORK_MODE" in
    default|none|proxy-only)
      ;;
    *)
      echo "Invalid network mode: $NETWORK_MODE"
      echo "Supported values: default, none, proxy-only"
      exit 1
      ;;
  esac
}

require_proxy_config() {
  if [[ "$NETWORK_MODE" == "proxy-only" && -z "$PROXY_URL" ]]; then
    echo "Proxy URL is required when using '--network proxy-only'."
    echo "Set --proxy URL or SMOS_DEV_PROXY_URL."
    exit 1
  fi
}

print_network_enforcement_note() {
  if [[ "$NETWORK_MODE" == "proxy-only" ]]; then
    cat <<EOF
Network mode 'proxy-only' is active.
This exports proxy environment variables inside the container but does not block direct egress by itself.
To enforce "proxy and DNS only", add host firewall rules for your container runtime.
EOF
  fi
}

print_existing_container_note() {
  if [[ "$NETWORK_MODE" != "default" || -n "$PROXY_URL" ]]; then
    cat <<EOF
Container '$CONTAINER_NAME' already exists.
Requested network settings apply only when creating a new container.
Remove and recreate the container if you need to change its network mode or proxy configuration.
EOF
  fi
}

warn_ignored_containerfile() {
  if (( CONTAINERFILE_EXPLICIT == 0 )); then
    return
  fi

  cat <<EOF
Container '$CONTAINER_NAME' already exists.
Ignoring --cfile '$CONTAINERFILE_INPUT' because existing containers are started/attached, not rebuilt.
Press Enter to continue or Ctrl-C to cancel.
EOF
  read -r
}

ensure_image() {
  if image_exists_locally "$CURRENT_IMAGE"; then
    return
  fi

  echo "Image '$CURRENT_IMAGE' not found locally in $RUNTIME_CMD."
  echo "Building from container file: $CONTAINERFILE_PATH"

  "$RUNTIME_CMD" build \
    --build-arg "SMOS_DEV_USERNAME=$CONTAINER_USER" \
    -f "$CONTAINERFILE_PATH" \
    -t "$IMAGE_NAME" \
    "$DOCKERFILE_DIR"
  CURRENT_IMAGE="$IMAGE_NAME"
}

########################################
# Container helpers
########################################
container_exists() {
  "$RUNTIME_CMD" ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"
}

container_running() {
  "$RUNTIME_CMD" ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"
}

ensure_host_dir() {
  if [[ ! -d "$HOST_DIR" ]]; then
    echo "Creating host directory: $HOST_DIR"
    mkdir -p "$HOST_DIR"
  fi

  mkdir -p "$STATE_DIR"
}

maybe_commit() {
  local default_tag=""
  local new_tag=""

  echo
  read -r -p "Save container changes so they persist? [y/N] " ans
  case "${ans,,}" in
    y|yes)
      default_tag="${IMAGE_NAME%:*}:${PROFILE_SLUG}-$(date +%Y%m%d-%H%M%S)"
      read -r -p "New image tag (default: ${default_tag}): " new_tag
      new_tag="${new_tag:-$default_tag}"

      echo "Committing container via $RUNTIME_CMD -> $new_tag"
      "$RUNTIME_CMD" commit "$CONTAINER_NAME" "$new_tag" >/dev/null

      printf '%s\n' "$new_tag" > "$IMAGE_STATE_FILE"
      echo "Saved. Future runs use: $new_tag"
      ;;
    *)
      echo "Not committing."
      ;;
  esac
}

run_with_spinner() {
  local message="$1"
  shift

  if [[ ! -t 1 ]]; then
    echo "$message"
    "$@"
    return
  fi

  local frames='|/-\'
  local i=0
  local cmd_pid=0
  local status=0
  local output_file=""

  output_file="$(mktemp "${TMPDIR:-/tmp}/smos-dev-spinner.XXXXXX")"

  "$@" >"$output_file" 2>&1 &
  cmd_pid=$!

  while kill -0 "$cmd_pid" 2>/dev/null; do
    printf '\r\033[K%s [%c]' "$message" "${frames:i%4:1}"
    i=$((i + 1))
    sleep 0.1
  done

  wait "$cmd_pid" || status=$?

  if (( status == 0 )); then
    printf '\r\033[K%s [done]\n' "$message"
  else
    printf '\r\033[K%s [failed]\n' "$message"
  fi

  if [[ -s "$output_file" ]]; then
    cat "$output_file"
  fi

  rm -f "$output_file"
  return "$status"
}

recreate_container_for_work_change() {
  local current_host=""
  local current_container=""

  current_host="${WORK_STATE_HOST_DIR:-$INSPECT_WORK_HOST_DIR}"
  current_container="${WORK_STATE_CONTAINER_DIR:-$INSPECT_WORK_CONTAINER_DIR}"

  if [[ -n "$current_host" || -n "$current_container" ]]; then
    cat <<EOF
Container '$CONTAINER_NAME' already exists with a different workspace mount.
Current mount: ${current_host:-unknown} -> ${current_container:-unknown}
Requested mount: ${HOST_DIR} -> ${CONTAINER_DIR}
EOF
  else
    cat <<EOF
Container '$CONTAINER_NAME' already exists and workspace mount metadata is unavailable.
Requested mount: ${HOST_DIR} -> ${CONTAINER_DIR}
EOF
  fi

  maybe_commit

  if container_running; then
    run_with_spinner "Stopping container '$CONTAINER_NAME'" \
      "$RUNTIME_CMD" stop "$CONTAINER_NAME"
  fi

  run_with_spinner "Removing container '$CONTAINER_NAME'" \
    "$RUNTIME_CMD" rm "$CONTAINER_NAME"
  write_work_state
  run_new_container
}

run_new_container() {
  local runtime_args=(
    -it
    --name "$CONTAINER_NAME"
    -e HOST_USER="$HOST_USER"
  )

  if [[ "$RUNTIME_CMD" == "docker" ]]; then
    runtime_args+=(--user "$(id -u):$(id -g)")
    runtime_args+=(-v "$HOST_DIR":"$CONTAINER_DIR")
  elif [[ "$RUNTIME_CMD" == "podman" ]]; then
    runtime_args+=(--userns=keep-id)
    runtime_args+=(-v "${HOST_DIR}:${CONTAINER_DIR}:Z,U")
  fi

  case "$NETWORK_MODE" in
    none)
      runtime_args+=(--network none)
      ;;
    proxy-only)
      runtime_args+=(
        -e HTTP_PROXY="$PROXY_URL"
        -e HTTPS_PROXY="$PROXY_URL"
        -e http_proxy="$PROXY_URL"
        -e https_proxy="$PROXY_URL"
      )
      if [[ -n "$no_proxy" ]]; then
        runtime_args+=(
          -e NO_PROXY="$no_proxy"
          -e no_proxy="$no_proxy"
        )
      fi
      ;;
  esac

  print_network_enforcement_note
  run_with_spinner "Creating container '$CONTAINER_NAME' with $RUNTIME_CMD" \
    "$RUNTIME_CMD" create "${runtime_args[@]}" "$CURRENT_IMAGE" /bin/bash
  echo "Starting container '$CONTAINER_NAME' with $RUNTIME_CMD"
  "$RUNTIME_CMD" start -ai "$CONTAINER_NAME"

  maybe_commit
}

start_existing_container() {
  echo "Starting container '$CONTAINER_NAME' with $RUNTIME_CMD"
  print_existing_container_note
  "$RUNTIME_CMD" start -ai "$CONTAINER_NAME"
  maybe_commit
}

open_running_container_shell() {
  echo "Container already running in $RUNTIME_CMD. Opening new shell..."
  print_existing_container_note
  "$RUNTIME_CMD" exec -it "$CONTAINER_NAME" /bin/bash
  maybe_commit
}

########################################
# Main
########################################
require_container_user
require_profile
require_runtime_value
require_valid_network_mode
require_proxy_config
ensure_host_dir
select_runtime
require_runtime_installed
require_runtime_ready
load_current_image
ensure_image

if container_exists; then
  warn_ignored_containerfile

  if ! runtime_exists_in_state; then
    echo "Container state is incomplete. Missing runtime sidecar: $RUNTIME_STATE_FILE"
    exit 1
  fi

  if container_uses_requested_workdir; then
    if container_running; then
      open_running_container_shell
    else
      start_existing_container
    fi
  else
    recreate_container_for_work_change
  fi
else
  write_runtime_state
  write_work_state
  run_new_container
fi
