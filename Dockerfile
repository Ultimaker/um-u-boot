FROM registry.hub.docker.com/library/debian:stretch-slim

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

ENV CROSS_COMPILE="arm-none-eabi-"
COPY test/buildenv_check.sh /test/buildenv_check.sh
