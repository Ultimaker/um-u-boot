#!/bin/bash
# shellcheck disable=SC2044
# shellcheck disable=SC1117

# This scripts builds and packs the bootloaders for the msc-sm2-imx6 linux SOM.
# It build two variations of the bootloader; one for the SPI-NOR flash and one
# for running from SD card.
# This U-Boot variant has a separate SPL and does not have a separate environment.

if [ "${CROSS_COMPILE}" == "" ]; then
    if [ "$(command -v arm-none-eabi-gcc)" != "" ]; then
        CROSS_COMPILE="arm-none-eabi-"
    fi
    if [ "$(command -v arm-linux-gnueabihf-gcc)" != "" ]; then
        CROSS_COMPILE="arm-linux-gnueabihf-"
    fi
    if [ "${CROSS_COMPILE}" == "" ]; then
        echo "No suiteable cross-compiler found."
        echo "One can be set explicitly via the environment variable CROSS_COMPILE='arm-linux-gnueabihf-' for example."
        exit 1
    fi
fi
export CROSS_COMPILE="${CROSS_COMPILE}"

if [ -z "${MAKEFLAGS}" ]; then
    echo -e -n "\e[1m"
    echo "Makeflags not set, hint, to speed up compilation time, increase the number of jobs. For example:"
    echo "MAKEFLAGS='-j 4' ${0}"
    echo -e "\e[0m"
fi

set -eu

CWD="$(pwd)"
UBOOT_SRC="${CWD}/u-boot/"
UBOOT_ENV_FILE="${CWD}/env/u-boot_env.txt"
UBOOT_SPLASHFILE="umsplash-800x320.bmp"
UMSPLASH="${CWD}/splash/SplashUM.bmp.bz2"
SPLASH_SERVICE="${CWD}/scripts/uboot-splashimage.service"
SPLASH_SCRIPT="${CWD}/scripts/uboot-set-splashimage.sh"

BUILD_DIR="${CWD}/_build_armhf/"
BUILDCONFIG="msc_sm2_imx6"
SUPPORTED_VARIANTS="sd spi"
RELEASE_VERSION=${RELEASE_VERSION:-9999.99.99}

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

package()
{
    # Create Debian package data directory
	deb_dir="${BUILD_DIR}/debian"

	rm -r "${deb_dir}" 2> /dev/null || true
	mkdir -p "${deb_dir}/boot"

    mkdir -p "${deb_dir}/DEBIAN"

    # Create a Debian control file to pack up a Debian package
    RELEASE_VERSION="${RELEASE_VERSION}" envsubst "\${RELEASE_VERSION}" < "${CWD}/scripts/debian_control" > "${deb_dir}/DEBIAN/control"

    for variant in ${SUPPORTED_VARIANTS}; do
        copy_file "${BUILD_DIR}/${BUILDCONFIG}_${variant}/u-boot.img" "${deb_dir}/boot/u-boot.img-${variant}"
        copy_file "${BUILD_DIR}/${BUILDCONFIG}_${variant}/SPL" "${deb_dir}/boot/spl.img-${variant}"
    done

    env_file="$(basename "${UBOOT_ENV_FILE}" ".txt")"
    copy_file "${BUILD_DIR}/${env_file}.bin" "${deb_dir}/boot/${env_file}.bin"

    # Set the default splash image to UM logo
    if ! bunzip2 -k -c  "${UMSPLASH}" > "${deb_dir}/boot/${UBOOT_SPLASHFILE}"; then
        echo "Failed to decompress splash file. Aborting..."
        exit 1
    fi

    # Copy SplashImage script
    mkdir -p "${deb_dir}/usr/share/uboot-splashimage/"
    copy_file "${SPLASH_SCRIPT}" "${deb_dir}/usr/share/uboot-splashimage/"
    chmod 755 "${deb_dir}/usr/share/uboot-splashimage/$(basename "${SPLASH_SCRIPT}")"     # Make sure the file is executable.

    # Copy Image files to script directory
    for file in "$(dirname "${UMSPLASH}")"/*.bmp.bz2; do
        copy_file "${file}" "${deb_dir}/usr/share/uboot-splashimage/"
    done;

    # Copy SplashImage SYSTEMD Service
    mkdir -p "${deb_dir}/lib/systemd/system/"
    copy_file "${SPLASH_SERVICE}" "${deb_dir}/lib/systemd/system/"

    # Copy preinst debian script file
    copy_file "${CWD}/scripts/preinst" "${deb_dir}/DEBIAN/"

    # Copy postinst debian script file
    copy_file "${CWD}/scripts/postinst" "${deb_dir}/DEBIAN/"

    # Build the debian package
    fakeroot dpkg-deb --build "${deb_dir}" "um-u-boot-${RELEASE_VERSION}.deb"
}

add_splash()
{
	# Disabled live conversion, because it does not work in docker, reason is unclear. But it is not worth the effort right now.
#	convert -density 600 "${CWD}/splash/umsplash.svg" -resize 800x320 -gravity center -extent 800x320 -flatten BMP3:"${BUILD_DIR}/umsplash.bmp"
#	gzip -9 -f "${BUILD_DIR}/umsplash.bmp"
    return
}

build_u-boot_env()
{
    echo "Building environment for '${UBOOT_ENV_FILE}'"
    filename="$(basename "${UBOOT_ENV_FILE}" ".txt")"
    mkenvimage -s 131072 -p 0x00 -o "${BUILD_DIR}/${filename}.bin" "${UBOOT_ENV_FILE}"
    chmod a+r "${BUILD_DIR}/${filename}.bin"
}

# Build the required U-Boot binaries/images.
# param: variant: can be either sd or spi.
build_u-boot()
{
    variant="${1}"
    config="${BUILDCONFIG}_${variant}"
    uconfig="${CWD}/configs/${config}_defconfig"
    build_dir="${BUILD_DIR}/${config}"

	# Prepare the build environment
	mkdir -p "${build_dir}"
	cd "${UBOOT_SRC}"

	# Build the u-boot image files
	ARCH=arm CROSS_COMPILE="${CROSS_COMPILE}" make "O=${build_dir}" "KCONFIG_CONFIG=${uconfig}" all

    cd "${CWD}"
}

if [ ${#} -gt 0 ]; then
	cd "${UBOOT_SRC}"
    for variant in ${SUPPORTED_VARIANTS}; do
        config="${BUILDCONFIG}_${variant}"
        uconfig="${CWD}/configs/${config}_defconfig"
        build_dir="${BUILD_DIR}/${config}"
        ARCH=arm make "O=${build_dir}" "KCONFIG_CONFIG=${uconfig}" "${@}"
	done
	cd "${CWD}"
else
    for variant in ${SUPPORTED_VARIANTS}; do
	    build_u-boot "${variant}"
	done

    build_u-boot_env
	add_splash
	package
fi
