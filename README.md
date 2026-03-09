<!-- SPDX-License-Identifier: MIT -->

# smos-dev

`smos-dev.sh` is a small Docker wrapper for launching a persistent development container for a named workspace.

It supports:

- profile-aware containers and image state
- Dockerfile-based image builds
- one mounted workspace per container
- optional image snapshotting with `docker commit`
- basic network modes: `default`, `none`, and `proxy-only`
- Linux and macOS host messaging

## Quick Start

1. Install Docker.
   Linux: Docker Engine.
   macOS: Docker Desktop.
2. Make sure the `docker` CLI works in your shell.
3. Run:

```bash
./smos-dev.sh --work my-project
```

This command will:

- derive a default profile from the first `FROM` line in [`Dockerfile`](/Dockerfile)
- build an image if needed
- create a host workspace directory if it does not already exist
- create or reuse a container for that profile and workspace

## Usage

```bash
./smos-dev.sh [--work NAME] [--profile NAME] [--network MODE] [--proxy URL]
```

Options:

- `--work NAME`: workspace name, default `work`
- `--profile NAME`: profile key for container naming and saved image state
- `--network MODE`: one of `default`, `none`, or `proxy-only`
- `--proxy URL`: proxy URL used with `--network proxy-only`
- `--help`: print inline help

## Environment Variables

- `SMOS_DEV_CONTAINER_USER`: in-container username; defaults to `USER`, then `id -un`
- `SMOS_DEV_HOST_ROOT`: host workspace root; defaults to `$HOME/code`
- `SMOS_DEV_CONTAINER_ROOT`: container workspace root; defaults to `/workspace`
- `SMOS_DEV_NETWORK_MODE`: default network mode
- `SMOS_DEV_PROFILE`: default profile; otherwise the first Dockerfile `FROM` image is used
- `SMOS_DEV_IMAGE_NAME`: override the built image tag
- `SMOS_DEV_PROXY_URL`: default proxy URL
- `DEVBOX_*`: backward-compatible fallback environment variables
- `DOCKERFILE_DIR`: directory containing the `Dockerfile`
- `XDG_STATE_HOME`: base state directory; defaults to `$HOME/.local/state`

## Examples

Use the default profile and workspace:

```bash
./smos-dev.sh --work api
```

Use a custom profile name:

```bash
./smos-dev.sh --profile debian:13.1 --work api
```

Use proxy-oriented networking:

```bash
./smos-dev.sh --network proxy-only --proxy http://127.0.0.1:8080 --work api
```

Use custom host and container workspace roots:

```bash
SMOS_DEV_HOST_ROOT="$HOME/src" \
SMOS_DEV_CONTAINER_ROOT="/projects" \
./smos-dev.sh --work api
```

## How State Works

The script stores the last committed image tag per profile and workspace:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/smos-dev/<profile-slug>--<work>.image_tag
```

For example:

```text
~/.local/state/smos-dev/ubuntu-latest--api.image_tag
```

That means these do not collide:

- `--profile ubuntu:latest --work api`
- `--profile debian:13.1 --work api`

## Container Naming

Containers are named like this:

```text
smos-dev-<profile-slug>-<work>
```

Examples:

- `smos-dev-ubuntu-latest-api`
- `smos-dev-debian-13.1-api`

## Networking

`smos-dev.sh` never publishes container ports by default.

Supported network modes:

- `default`: standard Docker outbound networking
- `none`: disables container networking
- `proxy-only`: sets `HTTP_PROXY` / `HTTPS_PROXY` inside the container for tools that honor them

Important: `proxy-only` is convenience configuration, not full egress enforcement. It does not by itself block direct outbound connections from software that ignores proxy settings.

## Platform Notes

### Linux

- Works with the Docker CLI directly.
- Isolation behavior depends on your Docker setup, kernel features, and any firewall rules you add.

### macOS

- Works through Docker Desktop’s Linux VM.
- The basic workflow is supported, but the host security model differs from Linux.
- This repository does not attempt to define or enforce a macOS sandboxing model.

## Security Model

This project is a convenience wrapper, not a hardened sandbox.

It helps with:

- repeatable container startup
- narrow workspace mounts
- profile-aware container separation

It does not guarantee:

- strict host isolation
- strict egress control
- a consistent security boundary across Linux and macOS

If you need a stronger security boundary, treat that as a separate host-level design problem.

## License

This project is licensed under the MIT License. See [LICENSE](/LICENSE).
