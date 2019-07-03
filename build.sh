#!/bin/bash
# shellcheck disable=SC2044
# shellcheck disable=SC1117

# This scripts builds the bootloader for the A20 linux system that we use.

# Check for a valid cross compiler. When unset, the kernel tries to build itself
# using arm-none-eabi-gcc, so we need to ensure it exists. Because printenv and
# which can cause bash -e to exit, so run this before setting this up.
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

set -eu

CWD="$(pwd)"

# Which bootloader to build.
UBOOT="${CWD}/u-boot/"

# Which bootloader config to build.
BUILDCONFIG="msc_sm2_imx6"

# Setup internal variables.
SD_CONFIG="msc_sm2_imx6_sd_defconfig"
SPI_CONFIG="msc_sm2_imx6_spi_defconfig"
UCONFIG="${CWD}/configs/${BUILDCONFIG}_defconfig"
UBOOT_BUILD_DIR="${CWD}/_build_armhf/${BUILDCONFIG}-u-boot"

u-boot_build()
{
	#Check if the release version number is set, if not, we are building a dev version.
	RELEASE_VERSION=${RELEASE_VERSION:-9999.99.99}

    # Create Debian package data directory
	DEB_DIR="${CWD}/debian"

	rm -r "${DEB_DIR}" 2> /dev/null || true
	mkdir -p "${DEB_DIR}/boot"

	# Prepare the build environment
	mkdir -p "${UBOOT_BUILD_DIR}"
	cd "${UBOOT}"

#    ARCH=arm CROSS_COMPILE="${CROSS_COMPILE}" make "O=${UBOOT_BUILD_DIR}" mrproper

	# Build the u-boot image files
	ARCH=arm CROSS_COMPILE="${CROSS_COMPILE}" make "O=${UBOOT_BUILD_DIR}" "${SD_CONFIG}" all
#	ARCH=arm CROSS_COMPILE="${CROSS_COMPILE}" make "O=${UBOOT_BUILD_DIR}" "KCONFIG_CONFIG=${UCONFIG}"

    cp "${UBOOT_BUILD_DIR}/u-boot.bin" "${DEB_DIR}/boot/u-boot-sd.bin"
    cp "${UBOOT_BUILD_DIR}/SPL" "${DEB_DIR}/boot/spl_sd.img"

	ARCH=arm CROSS_COMPILE="${CROSS_COMPILE}" make "O=${UBOOT_BUILD_DIR}" "${SPI_CONFIG}" all

    cp "${UBOOT_BUILD_DIR}/u-boot.bin" "${DEB_DIR}/boot/u-boot-spi.bin"
    cp "${UBOOT_BUILD_DIR}/SPL" "${DEB_DIR}/boot/spl_spi.img"

    cd "${CWD}"

	# Add splashimage
	convert -density 600 "splash/umsplash.*" -resize 800x320 -gravity center -extent 800x320 -flatten BMP3:"${UBOOT_BUILD_DIR}/umsplash.bmp"
	gzip -9 -f "${UBOOT_BUILD_DIR}/umsplash.bmp"
	cp "${UBOOT_BUILD_DIR}/umsplash.bmp.gz" "${DEB_DIR}/boot/"

    # Prepare the u-boot environment
#    for env in $(find env/ -name '*.env' -exec basename {} \;); do
#        echo "Building environment for ${env%.env}"
#        mkenvimage -s 131072 -p 0x00 -o "${UBOOT_BUILD_DIR}/${env}.bin" "env/${env}"
#        chmod a+r "${UBOOT_BUILD_DIR}/${env}.bin"
#        cp "env/${env}" "${UBOOT_BUILD_DIR}/${env}.bin" "${DEB_DIR}/boot/"
#    done

    mkdir -p "${DEB_DIR}/DEBIAN"
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

    # Build the debian package
    fakeroot dpkg-deb --build "${DEB_DIR}" "um-u-boot-${RELEASE_VERSION}.deb"
}

if [ ${#} -gt 0 ]; then
	pushd "${UBOOT}"
	ARCH=arm make "O=${UBOOT_BUILD_DIR}" "KCONFIG_CONFIG=${UCONFIG}" "${@}"
	popd
else
	u-boot_build
fi
