# SPDX-License-Identifier: MIT

FROM ubuntu:latest

ENV DEBIAN_FRONTEND=noninteractive
ARG SMOS_DEV_USERNAME

# Install developer tools
RUN apt-get update && apt-get install -y \
    build-essential \
    vim \
    git \
    tmux \
    curl \
    wget \
    iputils-ping \
    net-tools \
    sudo \
    ca-certificates \
    unzip \
    less \
    file \
    pkg-config \
    man-db \
    bash-completion \
    && rm -rf /var/lib/apt/lists/*

# Rename existing UID 1000 user (usually ubuntu) to the requested username
RUN test -n "$SMOS_DEV_USERNAME" && \
    existing_user=$(getent passwd 1000 | cut -d: -f1) && \
    existing_group=$(getent group 1000 | cut -d: -f1) && \
    usermod -l "$SMOS_DEV_USERNAME" "$existing_user" && \
    groupmod -n "$SMOS_DEV_USERNAME" "$existing_group" && \
    usermod -d "/home/$SMOS_DEV_USERNAME" -m "$SMOS_DEV_USERNAME" && \
    usermod -aG sudo "$SMOS_DEV_USERNAME" && \
    echo "$SMOS_DEV_USERNAME ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

WORKDIR /home/$SMOS_DEV_USERNAME

USER $SMOS_DEV_USERNAME

CMD ["/bin/bash"]
