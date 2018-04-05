#!/bin/bash

# This scripts builds the bootloader for the A20 linux system that we use.

# Check for a valid cross compiler. When unset, the kernel tries to build itself
# using arm-none-eabi-gcc, so we need to ensure it exists. Because printenv and
# which can cause bash -e to exit, so run this before setting this up.
if [ "${CROSS_COMPILE}" == "" ]; then
	if [ "$(which arm-none-eabi-gcc)" != "" ]; then
		CROSS_COMPILE="arm-none-eabi-"
	fi
	if [ "$(which arm-linux-gnueabihf-gcc)" != "" ]; then
		CROSS_COMPILE="arm-linux-gnueabihf-"
	fi
	if [ "${CROSS_COMPILE}" == "" ]; then
		echo "No suiteable cross-compiler found."
		echo "One can be set explicitly via the environment variable CROSS_COMPILE='arm-linux-gnueabihf-' for example."
		exit 1
	fi
fi
export CROSS_COMPILE=${CROSS_COMPILE}

if [ "${MAKEFLAGS}" == "" ]; then
	echo -e -n "\e[1m"
	echo "Makeflags not set, hint, to speed up compilation time, increase the number of jobs. For example:"
	echo "MAKEFLAGS='-j 4' ${0}"
	echo -e "\e[0m"
fi

set -e
set -u

# Which bootloader to build.
UBOOT=`pwd`/u-boot/

# Which bootloader config to build.
BUILDCONFIG="opinicus"

# Setup internal variables.
UCONFIG=`pwd`/configs/${BUILDCONFIG}_config
UBOOT_BUILD=`pwd`/_build_armhf/${BUILDCONFIG}-u-boot

# Initialize repositories
git submodule init
git submodule update

u-boot_build() {
	#Check if the release version number is set, if not, we are building a dev version.
	RELEASE_VERSION=${RELEASE_VERSION:-9999.99.99}

	# Prepare the build environment
	mkdir -p ${UBOOT_BUILD}
	pushd ${UBOOT}

	# Build the u-boot image file
	ARCH=arm CROSS_COMPILE="${CROSS_COMPILE}" make O=${UBOOT_BUILD} KCONFIG_CONFIG=${UCONFIG}
	popd

	# Build the debian package data
	DEB_DIR=`pwd`/debian

	rm -r ${DEB_DIR} 2> /dev/null || true
	mkdir -p "${DEB_DIR}/boot"
	cp ${UBOOT_BUILD}/u-boot-sunxi-with-spl.bin "${DEB_DIR}/boot/"

	# Add splashimage
	convert -density 600 "splash/umsplash.*" -resize 800x320 -gravity center -extent 800x320 -flatten BMP3:"${UBOOT_BUILD}/umsplash.bmp"
	gzip -9 -f "${UBOOT_BUILD}/umsplash.bmp"
	cp "${UBOOT_BUILD}/umsplash.bmp.gz" "${DEB_DIR}/boot/"

	# Prepare the u-boot environment
	for env in $(find env/ -name '*.env' -exec basename {} \;); do
		echo "Building environment for ${env%.env}"
		mkenvimage -s 131072 -p 0x00 -o ${UBOOT_BUILD}/${env}.bin env/${env}
		chmod a+r ${UBOOT_BUILD}/${env}.bin
		cp env/${env} ${UBOOT_BUILD}/${env}.bin "${DEB_DIR}/boot/"
	done

	mkdir -p ${DEB_DIR}/DEBIAN
	cat > debian/DEBIAN/control <<-EOT
		Package: um-u-boot
		Conflicts: u-boot-sunxi
		Replaces: u-boot-sunxi
		Version: ${RELEASE_VERSION}
		Architecture: armhf
		Maintainer: Anonymous <root@monolith.ultimaker.com>
		Section: admin
		Priority: optional
		Homepage: http://www.denx.de/wiki/U-Boot/
		Description: u-boot image with spl for the Olimex OLinuXino Lime2 eMMC.
	EOT

	# Build the debian package
	fakeroot dpkg-deb --build "${DEB_DIR}" um-u-boot-${RELEASE_VERSION}.deb
}

if [ ${#} -gt 0 ]; then
	pushd ${UBOOT}
	ARCH=arm make O=${UBOOT_BUILD} KCONFIG_CONFIG=${UCONFIG} "${@}"
	popd
else
	u-boot_build
fi
