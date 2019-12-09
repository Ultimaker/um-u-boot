FROM registry.hub.docker.com/library/debian:buster-slim

LABEL Maintainer="software-embedded-platform@ultimaker.com" \
      Comment="Ultimaker U-Boot build environment"

RUN apt-get update && \
    apt-get install -y \
        device-tree-compiler \
        fakeroot \
        gcc \
        gcc-arm-none-eabi \
        imagemagick \
        make \
        ncurses-dev \
        u-boot-tools \
    && \
    apt-get clean && \
    rm -rf /var/cache/apt/*

COPY buildenv_check.sh buildenv_check.sh
