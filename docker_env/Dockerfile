FROM registry.hub.docker.com/library/debian:buster-slim

LABEL Maintainer="software-embedded-platform@ultimaker.com" \
      Comment="Ultimaker U-Boot build environment"

RUN apt-get update && \
    apt-get install -y \
        bzip2 \
        device-tree-compiler \
        gcc \
        gcc-aarch64-linux-gnu \
        gettext \
        imagemagick \
        make \
        ncurses-dev \
        u-boot-tools \
    && \
    apt-get clean && \
    rm -rf /var/cache/apt/*

COPY buildenv_check.sh buildenv_check.sh
