#!/bin/sh
#
# SPDX-License-Identifier: AGPL-3.0+
#
# Copyright (C) 2019 Ultimaker B.V.
#

set -eu

CI_REGISTRY_IMAGE="${CI_REGISTRY_IMAGE:-registry.gitlab.com/ultimaker/embedded/platform/um-u-boot}"
CI_REGISTRY_IMAGE_TAG="${CI_REGISTRY_IMAGE_TAG:-latest}"

ARCH="${ARCH:-armhf}"

RELEASE_VERSION="${RELEASE_VERSION:-}"
CROSS_COMPILE="${CROSS_COMPILE:-""}"
DOCKER_WORK_DIR="${WORKDIR:-/build}"

run_env_check="yes"
run_linters="yes"
run_tests="yes"

update_docker_image()
{
    if ! docker pull "${CI_REGISTRY_IMAGE}:${CI_REGISTRY_IMAGE_TAG}" 2> /dev/null; then
        echo "Unable to update docker image '${CI_REGISTRY_IMAGE}:${CI_REGISTRY_IMAGE_TAG}', building locally instead."
        docker build . -t "${CI_REGISTRY_IMAGE}:${CI_REGISTRY_IMAGE_TAG}"
    fi
}

run_in_docker()
{
    docker run \
        --rm \
        -it \
        -u "$(id -u)" \
        -v "$(pwd):${DOCKER_WORK_DIR}" \
        -e "ARCH=${ARCH}" \
        -e "RELEASE_VERSION=${RELEASE_VERSION}" \
        -e "CROSS_COMPILE=${CROSS_COMPILE}" \
        -e "MAKEFLAGS=-j$(($(getconf _NPROCESSORS_ONLN) - 1))" \
        -w "${DOCKER_WORK_DIR}" \
        "${CI_REGISTRY_IMAGE}:${CI_REGISTRY_IMAGE_TAG}" \
        "${@}"
}

env_check()
{
    run_in_docker "./docker_env/buildenv_check.sh"
}

run_build()
{
    git submodule update --init --recursive
    run_in_docker "./build.sh" "${@}"
}

run_tests()
{
    echo "There are no tests available for this repository."
}

run_linters()
{
    run_shellcheck
}

run_shellcheck()
{
    docker run \
        --rm \
        -v "$(pwd):${DOCKER_WORK_DIR}" \
        -w "${DOCKER_WORK_DIR}" \
        "registry.hub.docker.com/koalaman/shellcheck-alpine:stable" \
        "./run_shellcheck.sh"
}

usage()
{
    echo "Usage: ${0} [OPTIONS]"
    echo "  -c   Skip build environment checks"
    echo "  -h   Print usage"
    echo "  -l   Skip code linting"
    echo "  -t   Skip tests"
}

while getopts ":chlt" options; do
    case "${options}" in
    c)
        run_env_check="no"
        ;;
    h)
        usage
        exit 0
        ;;
    l)
        run_linters="no"
        ;;
    t)
        run_tests="no"
        ;;
    :)
        echo "Option -${OPTARG} requires an argument."
        exit 1
        ;;
    ?)
        echo "Invalid option: -${OPTARG}"
        exit 1
        ;;
    esac
done
shift "$((OPTIND - 1))"

if ! command -V docker; then
    echo "Docker not found, docker-less builds are not supported."
    exit 1
fi

update_docker_image

if [ "${run_env_check}" = "yes" ]; then
    env_check
fi

if [ "${run_linters}" = "yes" ]; then
    run_linters
fi

run_build "${@}"

if [ "${run_tests}" = "yes" ]; then
    run_tests
fi

exit 0
