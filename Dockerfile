FROM registry.hub.docker.com/library/debian:stretch-slim

LABEL Maintainer="software-embedded-platform@ultimaker.com" \
      Comment="Ultimaker U-Boot build environment"

RUN apt-get update && \
    apt-get install -y \
        bzip2 \
        device-tree-compiler \
        fakeroot \
        gcc \
        gcc-arm-linux-gnueabihf \
        gettext \
        imagemagick \
        make \
        ncurses-dev \
        u-boot-tools \
    && \
    apt-get clean && \
    rm -rf /var/cache/apt/*

COPY docker_env/buildenv_check.sh /test/buildenv_check.sh
