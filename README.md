<!-- SPDX-License-Identifier: MIT -->

# smos-dev

## tl;dr
I can't remember all the docker / podman commands. I just want a development environment that is simple, mostly secure, and is not a set of aliases in my shell. I don't need a constantly updated Dockerfile, I need to be able to use docker commit several times, then throw that image away when I'm done. This script solves that problem.

## Overview

`smos-dev.sh` is a small Docker/Podman wrapper for launching a persistent development container for a profile, with a selectable workspace mount.

It supports:

- profile-aware containers and image state
- runtime-aware container and image state
- Containerfile-based image builds (default `Containerfile.ubuntu`, override with `--cfile`)
- one mounted workspace per container, replaceable by rerunning with a new `--work`
- optional image snapshotting with `docker commit` or `podman commit`
- basic network modes: `default`, `none`, and `proxy-only`
- Linux and macOS host messaging

## Quick Start

1. Install Docker or Podman.
   Linux: Docker Engine or Podman.
   macOS: Docker Desktop or Podman Desktop.
2. Make sure the chosen CLI works in your shell.
3. Run:

```bash
./smos-dev.sh --work my-project
```

This command will:

- derive a default profile from the first `FROM` line in [`Containerfile.ubuntu`](/Containerfile.ubuntu) (or the file selected with `--cfile`)
- pick a runtime if both `docker` and `podman` are installed and no runtime is already recorded
- build an image if needed
- create a host workspace directory if it does not already exist
- create or reuse a container for that profile and runtime
- recreate that container automatically when `--work` points to a different directory (mounts are immutable after container creation)

## Usage

```bash
./smos-dev.sh [--work PATH] [--profile NAME] [--runtime NAME] [--network MODE] [--proxy URL] [--cfile FILE]
```

Options:

- `--work PATH`: workspace path, default `work`
  - `/some/dir/foo` stays absolute
  - `~/my/dir/foo` expands from your home directory
  - `foo` and `foo/bar` are treated as relative to `SMOS_DEV_HOST_ROOT` and default to `$HOME/foo` and `$HOME/foo/bar`
- `--profile NAME`: profile key for container naming and saved image state
- `--runtime NAME`: one of `auto`, `docker`, or `podman`
- `--network MODE`: one of `default`, `none`, or `proxy-only`
- `--proxy URL`: proxy URL used with `--network proxy-only`
- `--cfile FILE`: container file to build from; default `Containerfile.ubuntu`
- `--help`: print inline help

## Environment Variables

- `SMOS_DEV_CONTAINER_USER`: in-container username; defaults to `USER`, then `id -un`
- `SMOS_DEV_HOST_ROOT`: base directory for relative work paths; defaults to `$HOME`
- `SMOS_DEV_CONTAINER_ROOT`: container workspace root; defaults to `/workspace`
- `SMOS_DEV_RUNTIME`: default runtime; `auto`, `docker`, or `podman`
- `SMOS_DEV_NETWORK_MODE`: default network mode
- `SMOS_DEV_PROFILE`: default profile; otherwise the first selected container file `FROM` image is used
- `SMOS_DEV_CFILE`: default container file name/path; defaults to `Containerfile.ubuntu`
- `SMOS_DEV_IMAGE_NAME`: override the built image tag
- `SMOS_DEV_PROXY_URL`: default proxy URL
- `DOCKERFILE_DIR`: directory containing container files; defaults to the script directory
- `XDG_STATE_HOME`: base state directory; defaults to `$HOME/.local/state`

## Examples

Use the default profile and a relative workspace path:

```bash
./smos-dev.sh --work api
```

Use a home-relative workspace path:

```bash
./smos-dev.sh --runtime podman --work ~/code/my-project
```

Use an alternate container file:

```bash
./smos-dev.sh --cfile Containerfile.debian --work api
```

Use an absolute workspace path with a custom profile name:

```bash
./smos-dev.sh --profile debian:13.1 --work /srv/dev/api
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

Container file note:

- `--cfile` only affects image build selection when creating/rebuilding images.
- If the target container already exists, `--cfile` is ignored and the script prompts: "Press Enter to continue or Ctrl-C to cancel."

## How State Works

The script stores the selected runtime per profile:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/smos-dev/<profile-slug>.runtime
```

It also stores the last committed image tag per runtime and profile:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/smos-dev/<profile-slug>.<runtime>.image_tag
```

And it stores the active workspace mount path per runtime and profile:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/smos-dev/<profile-slug>.<runtime>.work_mount
```

For example:

```text
~/.local/state/smos-dev/ubuntu-latest.runtime
~/.local/state/smos-dev/ubuntu-latest.docker.image_tag
~/.local/state/smos-dev/ubuntu-latest.docker.work_mount
```

That means these do not collide:

- `--profile ubuntu:latest`
- `--profile debian:13.1`
- `--runtime docker --profile ubuntu:latest`
- `--runtime podman --profile ubuntu:latest`

And these share the same profile container identity but change the mounted directory by recreating the container:

- `--profile ubuntu:latest --work api`
- `--profile ubuntu:latest --work ~/code/other-project`

## Container Naming

Containers are named like this:

```text
smos-dev-<profile-slug>
```

Examples:

- `smos-dev-ubuntu-latest`
- `smos-dev-debian-13.1`

## Networking

`smos-dev.sh` never publishes container ports by default.

Supported network modes:

- `default`: standard outbound networking for the selected runtime
- `none`: disables container networking
- `proxy-only`: sets `HTTP_PROXY` / `HTTPS_PROXY` inside the container for tools that honor them

Important: `proxy-only` is convenience configuration, not full egress enforcement. It does not by itself block direct outbound connections from software that ignores proxy settings.

## Platform Notes

### Linux

- Works with Docker or Podman.
- Isolation behavior depends on your runtime setup, kernel features, and any firewall rules you add.

### macOS

- Works through Docker Desktop’s Linux VM or Podman machine.
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
