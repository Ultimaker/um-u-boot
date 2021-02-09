#!/bin/sh
# shellcheck disable=SC2044
# shellcheck disable=SC1117

set +x

# This scripts builds and packs the bootloaders for the msc-sm2-imx6 linux SOM.
# It build two variations of the bootloader; one for the SPI-NOR flash and one
# for running from SD card.
# This U-Boot variant has a separate SPL and does not have a separate environment.


# Check for a valid cross compiler. When unset, the kernel tries to build itself
# using arm-none-eabi-gcc, so we need to ensure it exists. Because printenv and
# which can cause bash -e to exit, so run this before setting this up.
if [ "${CROSS_COMPILE}" = "" ]; then
    if [ "$(command -v aarch64-linux-gnu-gcc)" != "" ]; then
        CROSS_COMPILE="aarch64-linux-gnu-"
    fi
    if [ "${CROSS_COMPILE}" = "" ]; then
        echo "No suiteable cross-compiler found."
        echo "One can be set explicitly via the environment variable CROSS_COMPILE='aarch64-linux-gnu-' for example."
        exit 1
    fi
fi
export CROSS_COMPILE="${CROSS_COMPILE}"

if [ "${MAKEFLAGS}" = "" ]; then
    echo "Makeflags not set, hint, to speed up compilation time, increase the number of jobs. For example:"
    echo "MAKEFLAGS='-j 4' ${0}"
fi

set -eu

ARCH="arm64"
UM_ARCH="imx8mm" # Empty string, or sun7i for R1, or imx6dl for R2, or imx8mm

SRC_DIR="$(pwd)"
UBOOT_DIR="${SRC_DIR}/u-boot/"
UBOOT_ENV_FILE="${SRC_DIR}/env/u-boot_env.txt"

BUILD_DIR_TEMPLATE="_build"
BUILD_DIR="${SRC_DIR}/${BUILD_DIR_TEMPLATE}"

# Setup internal variables.
BUILDCONFIG="cgtsx8m"
SUPPORTED_VARIANTS="usd fspi"

# Debian package information
PACKAGE_NAME="${PACKAGE_NAME:-um-u-boot}"
RELEASE_VERSION="${RELEASE_VERSION:-999.999.999}"

UBOOT_SPLASHFILE="umsplash-800x320.bmp"
UMSPLASH="${SRC_DIR}/splash/SplashUM.bmp.bz2"
SPLASH_SERVICE="${SRC_DIR}/scripts/uboot-splashimage.service"
SPLASH_SCRIPT="${SRC_DIR}/scripts/uboot-set-splashimage.sh"

##
# copy_file() - Copy a file from target to destination file and
#               Stop the script if it fails.
# $1 : src file
# $2 : target file
#
copy_file()
{
    src_file="${1}"
    dst_file="${2}"

    if ! cp "${src_file}" "${dst_file}"; then
        echo "Failed to copy file '${src_file}' to '${dst_file}', unable to continue."
        exit 1
    fi
}

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

    for variant in ${SUPPORTED_VARIANTS}; do
        copy_file "${BUILD_DIR}/${BUILDCONFIG}_${variant}/u-boot.img" "${DEB_DIR}/boot/u-boot.img-${variant}"
        copy_file "${BUILD_DIR}/${BUILDCONFIG}_${variant}/SPL" "${DEB_DIR}/boot/spl.img-${variant}"
    done

    env_file="$(basename "${UBOOT_ENV_FILE}" ".txt")"
    copy_file "${BUILD_DIR}/${env_file}.bin" "${DEB_DIR}/boot/${env_file}.bin"

    # Set the default splash image to UM logo
    if ! bunzip2 -k -c  "${UMSPLASH}" > "${DEB_DIR}/boot/${UBOOT_SPLASHFILE}"; then
        echo "Failed to decompress splash file. Aborting..."
        exit 1
    fi

    # Copy SplashImage script
    mkdir -p "${DEB_DIR}/usr/share/uboot-splashimage/"
    copy_file "${SPLASH_SCRIPT}" "${DEB_DIR}/usr/share/uboot-splashimage/"
    chmod 755 "${DEB_DIR}/usr/share/uboot-splashimage/$(basename "${SPLASH_SCRIPT}")"     # Make sure the file is executable.

    # Copy Image files to script directory
    for file in "$(dirname "${UMSPLASH}")"/*.bmp.bz2; do
        copy_file "${file}" "${DEB_DIR}/usr/share/uboot-splashimage/"
    done;

    # Copy SplashImage SYSTEMD Service
    mkdir -p "${DEB_DIR}/lib/systemd/system/"
    copy_file "${SPLASH_SERVICE}" "${DEB_DIR}/lib/systemd/system/"

    # Copy preinst debian script file
    copy_file "${SRC_DIR}/scripts/preinst" "${DEB_DIR}/DEBIAN/"

    # Copy postinst debian script file
    copy_file "${SRC_DIR}/scripts/postinst" "${DEB_DIR}/DEBIAN/"

    DEB_PACKAGE="${PACKAGE_NAME}_${RELEASE_VERSION}-${UM_ARCH}_${ARCH}.deb"

    dpkg-deb --build --root-owner-group "${DEB_DIR}" "${BUILD_DIR}/${DEB_PACKAGE}"
    dpkg-deb -c "${BUILD_DIR}/${DEB_PACKAGE}"
}

generate_splash_image()
{
	# Disabled live conversion, because it does not work in docker, reason is unclear. But it is not worth the effort right now.
#    echo "Generating splash image.."
#	convert -density 600 "splash/umsplash.*" -resize 800x320 -gravity center -extent 800x320 -flatten BMP3:"${UBOOT_BUILD_DIR}/umsplash.bmp"
#	gzip -9 -f "${UBOOT_BUILD_DIR}/umsplash.bmp"
    return
}

generate_uboot_env_files()
{
    echo "Building environment for '${UBOOT_ENV_FILE}'"
    filename="$(basename "${UBOOT_ENV_FILE}" ".txt")"
    mkenvimage -s 131072 -p 0x00 -o "${BUILD_DIR}/${filename}.bin" "${UBOOT_ENV_FILE}"
    chmod a+r "${BUILD_DIR}/${filename}.bin"
}

build_uboot()
{
    echo "Building U-Boot.."
	cd "${UBOOT_DIR}"

    for variant in ${SUPPORTED_VARIANTS}; do
        config="${BUILDCONFIG}_${variant}"
        uconfig="${SRC_DIR}/configs/${config}_defconfig"
        cp ${uconfig} /build/u-boot/configs
        build_dir="${BUILD_DIR}/${config}"

        if [ ! -d "${build_dir}" ]; then
            mkdir -p "${build_dir}"
        fi

        if [ -n "${1-}" ]; then
            ARCH=arm CROSS_COMPILE="${CROSS_COMPILE}" make "O=${build_dir}" "${config}_defconfig" "${1}"
            ARCH=arm CROSS_COMPILE="${CROSS_COMPILE}" make "O=${build_dir}" all "${1}"
        else
            ARCH=arm CROSS_COMPILE="${CROSS_COMPILE}" make "O=${build_dir}" "${config}_defconfig"
            ARCH=arm CROSS_COMPILE="${CROSS_COMPILE}" make "O=${build_dir}" all
        fi
    done

	cd "${SRC_DIR}"
}

create_build_dir()
{
    if [ ! -d "${BUILD_DIR}" ]; then
        mkdir -p "${BUILD_DIR}"
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
