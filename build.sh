#!/bin/sh
# shellcheck disable=SC2044
# shellcheck disable=SC1117

# This scripts builds the bootloader for the A20 linux system that we use.

# Check for a valid cross compiler. When unset, the kernel tries to build itself
# using arm-none-eabi-gcc, so we need to ensure it exists. Because printenv and
# which can cause bash -e to exit, so run this before setting this up.
if [ "${CROSS_COMPILE}" = "" ]; then
    if [ "$(command -v arm-none-eabi-gcc)" != "" ]; then
        CROSS_COMPILE="arm-none-eabi-"
    fi
    if [ "$(command -v arm-linux-gnueabihf-gcc)" != "" ]; then
        CROSS_COMPILE="arm-linux-gnueabihf-"
    fi
    if [ "${CROSS_COMPILE}" = "" ]; then
        echo "No suiteable cross-compiler found."
        echo "One can be set explicitly via the environment variable CROSS_COMPILE='arm-linux-gnueabihf-' for example."
        exit 1
    fi
fi
export CROSS_COMPILE="${CROSS_COMPILE}"

if [ "${MAKEFLAGS}" = "" ]; then
    echo "Makeflags not set, hint, to speed up compilation time, increase the number of jobs. For example:"
    echo "MAKEFLAGS='-j 4' ${0}"
fi

set -eu

ARCH="armhf"
UM_ARCH="sun7i" # Empty string, or sun7i for R1, or imx6dl for R2

SRC_DIR="$(pwd)"
UBOOT_DIR="${SRC_DIR}/u-boot/"
BUILD_DIR_TEMPLATE="_build"
BUILD_DIR="${SRC_DIR}/${BUILD_DIR_TEMPLATE}"

# Which bootloader config to build.
BUILDCONFIG="opinicus"

# Setup internal variables.
UCONFIG="${SRC_DIR}/configs/${BUILDCONFIG}_config"
UBOOT_BUILD_DIR="${BUILD_DIR}/${BUILDCONFIG}-u-boot"

# Debian package information
PACKAGE_NAME="${PACKAGE_NAME:-um-u-boot}"
RELEASE_VERSION="${RELEASE_VERSION:-999.999.999}"

create_debian_package()
{
    echo "Creating Debian package.."
    DEB_DIR="${BUILD_DIR}/debian_deb_build"

    mkdir -p "${DEB_DIR}/DEBIAN"
    sed -e 's|@ARCH@|'"${ARCH}"'|g' \
        -e 's|@PACKAGE_NAME@|'"${PACKAGE_NAME}"'|g' \
        -e 's|@RELEASE_VERSION@|'"${RELEASE_VERSION}-${UM_ARCH}"'|g' \
        "${SRC_DIR}/debian/control.in" > "${DEB_DIR}/DEBIAN/control"

	mkdir -p "${DEB_DIR}/boot"
	cp "${UBOOT_BUILD_DIR}/u-boot-sunxi-with-spl.bin" "${DEB_DIR}/boot/"

	# Add splashimage
	cp "${UBOOT_BUILD_DIR}/umsplash.bmp.gz" "${DEB_DIR}/boot/"

	for env in $(find env/ -name '*.env' -exec basename {} \;); do
        cp "env/${env}" "${UBOOT_BUILD_DIR}/${env}.bin" "${DEB_DIR}/boot/"
	done

    DEB_PACKAGE="${PACKAGE_NAME}_${RELEASE_VERSION}-${UM_ARCH}_${ARCH}.deb"

    dpkg-deb --build --root-owner-group "${DEB_DIR}" "${BUILD_DIR}/${DEB_PACKAGE}"
    dpkg-deb -c "${BUILD_DIR}/${DEB_PACKAGE}"
}

generate_splash_image()
{
    echo "Generating splash image.."
	convert -density 600 "splash/umsplash.*" -resize 800x320 -gravity center -extent 800x320 -flatten BMP3:"${UBOOT_BUILD_DIR}/umsplash.bmp"
	gzip -9 -f "${UBOOT_BUILD_DIR}/umsplash.bmp"
}

generate_uboot_env_files()
{
    echo "Generating U-Boot env files.."
	for env in $(find env/ -name '*.env' -exec basename {} \;); do
		echo "Building environment for ${env%.env}"
		mkenvimage -s 131072 -p 0x00 -o "${UBOOT_BUILD_DIR}/${env}.bin" "env/${env}"
		chmod a+r "${UBOOT_BUILD_DIR}/${env}.bin"
	done
}

build_uboot()
{
    echo "Building U-Boot.."
	cd "${UBOOT_DIR}"

    if [ -n "${1-}" ]; then
        ARCH=arm CROSS_COMPILE="${CROSS_COMPILE}" make "O=${UBOOT_BUILD_DIR}" "KCONFIG_CONFIG=${UCONFIG}" "${1}"
    else
        ARCH=arm CROSS_COMPILE="${CROSS_COMPILE}" make "O=${UBOOT_BUILD_DIR}" "KCONFIG_CONFIG=${UCONFIG}"
    fi

	cd "${SRC_DIR}"
}

create_build_dir()
{
    if [ ! -d "${UBOOT_BUILD_DIR}" ]; then
        mkdir -p "${UBOOT_BUILD_DIR}"
    fi
}

cleanup()
{
    if [ -z "${BUILD_DIR##*${BUILD_DIR_TEMPLATE}*}" ]; then
        rm -rf "${BUILD_DIR:?}"
    fi
}

usage()
{
    echo "Usage: ${0} [OPTIONS] [u-boot|splash|env|deb]"
    echo "  For config modification use: ${0} menuconfig"
    echo "  -c   Explicitly cleanup the build directory"
    echo "  -h   Print this usage"
    echo "NOTE: This script requires root permissions to run."
}

while getopts ":hc" options; do
    case "${options}" in
    c)
        cleanup
        exit 0
        ;;
    h)
        usage
        exit 0
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

if [ "$(id -u)" -ne 0 ]; then
    echo "Warning: this script requires root permissions."
    echo "Run this script again with 'sudo ${0}'."
    echo "See ${0} -h for more info."
    exit 1
fi

if [ "${#}" -gt 1 ]; then
    echo "Error, too many arguments."
    usage
    exit 1
fi

if [ "${#}" -eq 0 ]; then
    cleanup
    create_build_dir
    build_uboot
    generate_splash_image
    generate_uboot_env_files
    create_debian_package
    exit 0
fi

create_build_dir

case "${1-}" in
    u-boot)
        build_uboot
        ;;
    splash)
        generate_splash_image
        ;;
    env)
        generate_uboot_env_files
        ;;
    deb)
        build_uboot
        generate_splash_image
        generate_uboot_env_files
        ;;
    menuconfig)
        build_uboot menuconfig
        ;;
    *)
        echo "Error, unknown build option given"
        usage
        exit 1
        ;;
esac

exit 0
