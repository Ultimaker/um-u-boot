#!/bin/bash
# shellcheck disable=SC2044
# shellcheck disable=SC1117

# This scripts builds and packs the bootloaders for the msc-sm2-imx6 linux SOM.
# It build two variations of the bootloader; one for the SPI-NOR flash and one
# for running from SD card.
# This U-Boot variant has a separate SPL and does not have a separate environment.

set -eu

CWD="$(pwd)"
UBOOT_SRC="${CWD}/u-boot/"
BUILD_DIR="${CWD}/_build_armhf/"
BUILDCONFIG="msc_sm2_imx6"
SUPPORTED_VARIANTS="sd spi"
RELEASE_VERSION=${RELEASE_VERSION:-9999.99.99}


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

if [ "${MAKEFLAGS}" == "" ]; then
    echo -e -n "\e[1m"
    echo "Makeflags not set, hint, to speed up compilation time, increase the number of jobs. For example:"
    echo "MAKEFLAGS='-j 4' ${0}"
    echo -e "\e[0m"
fi

package()
{
    # Create Debian package data directory
	deb_dir="${CWD}/debian"

	rm -r "${deb_dir}" 2> /dev/null || true
	mkdir -p "${deb_dir}/boot"

    mkdir -p "${deb_dir}/DEBIAN"
    cat > debian/DEBIAN/control <<-\
________________________________________________________________________________________________
Package: um-u-boot
Conflicts: u-boot-sunxi
Replaces: u-boot-sunxi
Version: ${RELEASE_VERSION}
Architecture: armhf
Maintainer: Anonymous <software-embedded-platform@ultimaker.com>
Section: admin
Priority: optional
Homepage: http://www.denx.de/wiki/U-Boot/
Description: U-Boot package with SPI-NOR/SD U-boot and SPL binary for the MSC IMX.6.
________________________________________________________________________________________________

    cp "${BUILD_DIR}/umsplash.bmp.gz" "${deb_dir}/boot/"

    for variant in ${SUPPORTED_VARIANTS}; do
        cp "${BUILD_DIR}/${BUILDCONFIG}_${variant}/u-boot.img" "${deb_dir}/boot/u-boot.img-${variant}"
        cp "${BUILD_DIR}/${BUILDCONFIG}_${variant}/SPL" "${deb_dir}/boot/spl.img-${variant}"
    done

    # Build the debian package
    fakeroot dpkg-deb --build "${deb_dir}" "um-u-boot-${RELEASE_VERSION}.deb"
}

add_splash()
{
	# Add splashimage
	convert -density 600 "splash/umsplash.*" -resize 800x320 -gravity center -extent 800x320 -flatten BMP3:"${BUILD_DIR}/umsplash.bmp"
	gzip -9 -f "${BUILD_DIR}/umsplash.bmp"
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

	add_splash
	package
fi
