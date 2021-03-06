#!/bin/sh
#
# Copyright (C) 2019 Ultimaker B.V.

set -eu

LOCAL_REGISTRY_IMAGE="um-u-boot"

SRC_DIR="$(pwd)"
RELEASE_VERSION="${RELEASE_VERSION:-999.999.999}"
DOCKER_WORK_DIR="/build"
BUILD_DIR="_build"

run_env_check="yes"
run_linters="yes"
run_tests="yes"

update_docker_image()
{
    echo "Building local Docker build environment."
    echo "!! Make sure you implement a proper 'buildenv_check.sh' script.!!"
    echo "This script should check your docker env, in order to get early feedback."
    docker build ./docker_env/ -t "${LOCAL_REGISTRY_IMAGE}"
}

run_in_docker()
{
    docker run \
        --rm \
        -it \
        -e "MAKEFLAGS=-j$(($(getconf _NPROCESSORS_ONLN) - 1))" \
        -e "BUILD_DIR=${DOCKER_WORK_DIR}/${BUILD_DIR}" \
        -e "RELEASE_VERSION=${RELEASE_VERSION}" \
        -v "${SRC_DIR}:${DOCKER_WORK_DIR}" \
        -w "${DOCKER_WORK_DIR}" \
        "${LOCAL_REGISTRY_IMAGE}" \
        "${@}"
}

env_check()
{
    run_in_docker "./docker_env/buildenv_check.sh"
}

run_build()
{
    
    git submodule update --init --recursive || {
        git submodule deinit --all -f
        rm -rf .git/modules
        git submodule update --init --recursive 
    }
    run_in_docker "./build.sh" "${@}"
}

deliver_pkg()
{
    run_in_docker chown -R "$(id -u):$(id -g)" "${DOCKER_WORK_DIR}"

    cp "${BUILD_DIR}/"*".deb" "./"
}

run_tests()
{
    echo "There are no tests available for this repository."
}

run_shellcheck()
{
    docker run \
        --rm \
        -v "${SRC_DIR}:${DOCKER_WORK_DIR}" \
        -w "${DOCKER_WORK_DIR}" \
        "registry.hub.docker.com/koalaman/shellcheck-alpine:stable" \
        "./run_shellcheck.sh"
}

run_linter()
{
    run_shellcheck
}

usage()
{
    echo "Usage: ${0} [OPTIONS]"
    echo "  -c   Skip build environment checks"
    echo "  -h   Print usage"
    echo "  -l   Skip code linting"
    echo "  -t   Skip tests"
    echo
    echo "Other options will be passed on to build.sh"
    echo "Run './build.sh -h' for more information."
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
    run_linter || true
fi

run_build "${@}"

if [ "${run_tests}" = "yes" ]; then
    run_tests
fi

deliver_pkg

exit 0
