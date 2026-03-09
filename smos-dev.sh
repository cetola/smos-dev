#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKERFILE_DIR="${DOCKERFILE_DIR:-$SCRIPT_DIR}"
HOST_USER="${USER:-$(id -un)}"
CONTAINER_USER="${SMOS_DEV_CONTAINER_USER:-${DEVBOX_CONTAINER_USER:-$HOST_USER}}"
BASE_HOST_DIR="${SMOS_DEV_HOST_ROOT:-${DEVBOX_HOST_ROOT:-${HOME}/code}}"
BASE_CONTAINER_DIR="${SMOS_DEV_CONTAINER_ROOT:-${DEVBOX_CONTAINER_ROOT:-/workspace}}"
STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/smos-dev"
HOST_OS="$(uname -s)"

WORK_NAME="work"   # default if not specified
NETWORK_MODE="${SMOS_DEV_NETWORK_MODE:-${DEVBOX_NETWORK_MODE:-default}}"
PROXY_URL="${SMOS_DEV_PROXY_URL:-${DEVBOX_PROXY_URL:-}}"
PROFILE="${SMOS_DEV_PROFILE:-${DEVBOX_PROFILE:-}}"

http_proxy="${HTTP_PROXY:-${http_proxy:-}}"
https_proxy="${HTTPS_PROXY:-${https_proxy:-}}"
no_proxy="${NO_PROXY:-${no_proxy:-}}"

get_default_profile() {
  local dockerfile_path="${DOCKERFILE_DIR}/Dockerfile"
  local from_image=""

  if [[ -f "$dockerfile_path" ]]; then
    from_image="$(awk 'toupper($1) == "FROM" { print $2; exit }' "$dockerfile_path")"
  fi

  if [[ -n "$from_image" ]]; then
    printf '%s\n' "$from_image"
  else
    printf 'default\n'
  fi
}

sanitize_profile() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_.-]/-/g'
}

initialize_runtime_vars() {
  PROFILE="${PROFILE:-$(get_default_profile)}"
  PROFILE_SLUG="$(sanitize_profile "$PROFILE")"
  IMAGE_NAME="${SMOS_DEV_IMAGE_NAME:-${DEVBOX_IMAGE_NAME:-smos-dev-${PROFILE_SLUG}:latest}}"
  CONTAINER_NAME="smos-dev-${PROFILE_SLUG}-${WORK_NAME}"
  HOST_DIR="${BASE_HOST_DIR}/${WORK_NAME}"
  CONTAINER_DIR="${BASE_CONTAINER_DIR}/${WORK_NAME}"
  STATE_FILE="${STATE_DIR}/${PROFILE_SLUG}--${WORK_NAME}.image_tag"
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

get_platform_setup_line() {
  case "$HOST_OS" in
    Darwin)
      printf '%s\n' "Install Docker Desktop for Mac and ensure the 'docker' CLI works in your shell."
      ;;
    Linux)
      printf '%s\n' "Install Docker Engine and ensure your user can run 'docker'."
      ;;
    *)
      printf '%s\n' "Install a Docker-compatible runtime and ensure the 'docker' CLI works in your shell."
      ;;
  esac
}

print_help() {
  cat <<EOF
Usage:
  $(basename "$0") [--work NAME] [--profile NAME] [--network MODE] [--proxy URL] [--help]

Start or attach to a Docker development container for a named workspace.

Options:
  --work NAME       Workspace name. Default: '$WORK_NAME'
  --profile NAME    Container profile. Default: '$PROFILE'
  --network MODE    default | none | proxy-only. Default: '$NETWORK_MODE'
  --proxy URL       Required with '--network proxy-only' unless SMOS_DEV_PROXY_URL is set.
  --help, -h        Show this help text and exit.

Environment:
  SMOS_DEV_CONTAINER_USER  In-container username. Default: USER / id -un
  SMOS_DEV_HOST_ROOT       Host workspace root. Default: '${HOME}/code'
  SMOS_DEV_CONTAINER_ROOT  Container workspace root. Default: '/workspace'
  SMOS_DEV_NETWORK_MODE    Default network mode. Default: '$NETWORK_MODE'
  SMOS_DEV_PROFILE         Default profile. Default: first Dockerfile FROM image
  SMOS_DEV_IMAGE_NAME      Override built image tag. Default: '$IMAGE_NAME'
  SMOS_DEV_PROXY_URL       Default proxy URL
  DEVBOX_*                Backward-compatible fallback environment variables
  DOCKERFILE_DIR          Dockerfile directory. Default: script directory
  XDG_STATE_HOME          State root. Default: '${HOME}/.local/state'

Examples:
  $(basename "$0") --work api
  $(basename "$0") --profile debian:13.1 --work api
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
    --work)
      require_option_value "--work" "${2:-}"
      WORK_NAME="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

initialize_runtime_vars

########################################
# Image handling
########################################
if [[ -f "$STATE_FILE" ]]; then
  CURRENT_IMAGE="$(cat "$STATE_FILE")"
else
  CURRENT_IMAGE="$IMAGE_NAME"
fi

image_exists_locally() {
  docker image inspect "$1" >/dev/null 2>&1
}

require_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "docker is required but was not found in PATH"
    exit 1
  fi
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
To enforce "proxy and DNS only", add host firewall rules for your Docker runtime.
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

ensure_image() {
  if image_exists_locally "$CURRENT_IMAGE"; then
    return
  fi

  echo "Image '$CURRENT_IMAGE' not found locally."
  echo "Building from Dockerfile in: $DOCKERFILE_DIR"

  docker build \
    --build-arg "SMOS_DEV_USERNAME=$CONTAINER_USER" \
    -t "$IMAGE_NAME" \
    "$DOCKERFILE_DIR"
  CURRENT_IMAGE="$IMAGE_NAME"
}

########################################
# Container helpers
########################################
container_exists() {
  docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"
}

container_running() {
  docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"
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
      default_tag="${IMAGE_NAME%:*}:${WORK_NAME}-$(date +%Y%m%d-%H%M%S)"
      read -r -p "New image tag (default: ${default_tag}): " new_tag
      new_tag="${new_tag:-$default_tag}"

      echo "Committing container -> $new_tag"
      docker commit "$CONTAINER_NAME" "$new_tag" >/dev/null

      echo "$new_tag" > "$STATE_FILE"
      echo "Saved. Future runs use: $new_tag"
      ;;
    *)
      echo "Not committing."
      ;;
  esac
}

run_new_container() {
  local docker_args=(
    -it
    --name "$CONTAINER_NAME"
    -v "$HOST_DIR":"$CONTAINER_DIR"
    -e HOST_USER="$HOST_USER"
  )

  case "$NETWORK_MODE" in
    none)
      docker_args+=(--network none)
      ;;
    proxy-only)
      docker_args+=(
        -e HTTP_PROXY="$PROXY_URL"
        -e HTTPS_PROXY="$PROXY_URL"
        -e http_proxy="$PROXY_URL"
        -e https_proxy="$PROXY_URL"
      )
      if [[ -n "$no_proxy" ]]; then
        docker_args+=(
          -e NO_PROXY="$no_proxy"
          -e no_proxy="$no_proxy"
        )
      fi
      ;;
  esac

  echo "Creating container '$CONTAINER_NAME'"
  print_network_enforcement_note
  docker run "${docker_args[@]}" "$CURRENT_IMAGE" /bin/bash

  maybe_commit
}

start_existing_container() {
  echo "Starting container '$CONTAINER_NAME'"
  print_existing_container_note
  docker start -ai "$CONTAINER_NAME"
  maybe_commit
}

open_running_container_shell() {
  echo "Container already running. Opening new shell..."
  print_existing_container_note
  docker exec -it "$CONTAINER_NAME" /bin/bash
}

########################################
# Main
########################################
require_container_user
require_profile
require_valid_network_mode
require_proxy_config
require_docker
ensure_host_dir
ensure_image

if container_exists; then
  if container_running; then
    open_running_container_shell
  else
    start_existing_container
  fi
else
  run_new_container
fi
