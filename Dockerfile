# Download base image debian latest stable
FROM debian:latest

# Install package dependencies
RUN apt-get update && apt-get install -y device-tree-compiler u-boot-tools crossbuild-essential-armhf imagemagick

# Setup the build environment
RUN mkdir /workspace
ENV CROSS_COMPILE="arm-linux-gnueabihf-"
ENV MAKEFLAGS="-j 5"