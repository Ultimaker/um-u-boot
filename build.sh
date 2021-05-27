#!/bin/sh
# shellcheck disable=SC2044
# shellcheck disable=SC1117

set +x

# This scripts builds and packs the bootloaders for the Congatec iMX8 linux SOM.
# It build two variations of the bootloader container; one for the SPI-NOR flash and one
# for running from SD card.


# Check for a valid cross compiler. When unset, it will try to build itself
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
UM_ARCH="imx8mm-SER3"

SRC_DIR="$(pwd)"
UBOOT_DIR="${SRC_DIR}/u-boot/"
ATF_DIR="${SRC_DIR}/imx-atf/"

BUILD_DIR_TEMPLATE="_build"
BUILD_DIR="${SRC_DIR}/${BUILD_DIR_TEMPLATE}"

# Setup internal variables.
BUILDCONFIG="cgtsx8m"
SUPPORTED_VARIANTS="usd fspi"

# Debian package information
PACKAGE_NAME="${PACKAGE_NAME:-um-u-boot}"
RELEASE_VERSION="${RELEASE_VERSION:-999.999.999}"

##
# copy_file() - Copy a file from target to destination file and
#               Stop the script if it fails.
# $1 : src file
# $2 : target file
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
        copy_file "${BUILD_DIR}/flash_${variant}.bin" "${DEB_DIR}/boot/flash_${variant}.bin"
    done

    if ! cp "${BUILD_DIR}/boot.scr" "${DEB_DIR}/boot/boot.scr"; then
        echo "Error, no bootscript files found."
        exit 1
    fi

    if ! cp "${BUILD_DIR}/boot.cmd" "${DEB_DIR}/boot/boot.cmd"; then
        echo "Error, no bootscript files found."
        exit 1
    fi

    DEB_PACKAGE="${PACKAGE_NAME}_${RELEASE_VERSION}-${UM_ARCH}_${ARCH}.deb"

    dpkg-deb --build --root-owner-group "${DEB_DIR}" "${BUILD_DIR}/${DEB_PACKAGE}"
    dpkg-deb -c "${BUILD_DIR}/${DEB_PACKAGE}"
}

build_imx_atf()
{
    echo "Building ARM Trusted Firmware (atf) .."
    cd "${ATF_DIR}"

    if [ ! -d "${BUILD_DIR}" ]; then
        mkdir -p "${BUILD_DIR}"
    fi

    ARCH=arm CROSS_COMPILE="${CROSS_COMPILE}" make BUILD_BASE="${BUILD_DIR}" PLAT=imx8mm bl31

    cd "${SRC_DIR}"
}

build_container()
{
    echo "Building bootcontainers .."
    
    mkimage_target_path="${SRC_DIR}/mkimage-imx8-family/iMX8M"
    bl3_1_artefact="bl31.bin"
    ddr_trainer_artefacts="lpddr4_pmu_train_1d_dmem.bin lpddr4_pmu_train_1d_imem.bin lpddr4_pmu_train_2d_dmem.bin lpddr4_pmu_train_2d_imem.bin"
    
    cp "${BUILD_DIR}/imx8mm/release/${bl3_1_artefact}" "${mkimage_target_path}"
    
    for file in ${ddr_trainer_artefacts}; do
        cp "${SRC_DIR}/firmware-imx-8.5/firmware/ddr/synopsys/${file}" "${mkimage_target_path}"
    done
    
    for variant in ${SUPPORTED_VARIANTS}; do
        cp "${BUILD_DIR}/cgtsx8m_${variant}/spl/u-boot-spl.bin" "${mkimage_target_path}"
        cp "${BUILD_DIR}/cgtsx8m_${variant}/u-boot-nodtb.bin" "${mkimage_target_path}"
        cp "${BUILD_DIR}/cgtsx8m_${variant}/arch/arm/dts/imx8mm-cgtsx8m.dtb" "${mkimage_target_path}"

        cd "${SRC_DIR}/mkimage-imx8-family"

        if [ "${variant}" = "usd" ]; then
            if ! make SOC=iMX8MM flash_sx8m; then
                echo "Error, running mkimage make 'flash_sx8m' for '${variant}'."
                exit 1
            fi
        else
            if ! make SOC=iMX8MM flash_sx8m_flexspi; then
                echo "Error, running mkimage make 'flash_sx8m_flexspi' for '${variant}'."
                exit 1
            fi
        fi

        if ! make SOC=iMX8MM print_fit_hab_sx8m; then
           echo "Warning,  for '${variant}'" 
        fi
        
        mv "${mkimage_target_path}/flash.bin" "${BUILD_DIR}/flash_${variant}.bin"
        
        rm "${mkimage_target_path}/u-boot-spl.bin"
        rm "${mkimage_target_path}/u-boot-nodtb.bin"
        rm "${mkimage_target_path}/imx8mm-cgtsx8m.dtb"
        
        cd "${SRC_DIR}"
    done
    
    for file in ${ddr_trainer_artefacts}; do
        rm "${mkimage_target_path}/${file}"
    done
    
    rm "${mkimage_target_path}/${bl3_1_artefact}"
}

build_uboot()
{
    echo "Building U-Boot.."
    
	cd "${UBOOT_DIR}"

    for variant in ${SUPPORTED_VARIANTS}; do
        config="${BUILDCONFIG}_${variant}"
        uconfig="${SRC_DIR}/configs/${config}_defconfig"
        cp "${uconfig}" "${UBOOT_DIR}/configs"
        build_dir="${BUILD_DIR}/${config}"

        if [ ! -d "${build_dir}" ]; then
            mkdir -p "${build_dir}"
        fi

        if [ -n "${1-}" ]; then
            ARCH=arm CROSS_COMPILE="${CROSS_COMPILE}" make "O=${build_dir}" "${config}_defconfig" "${1}"
            ARCH=arm CROSS_COMPILE="${CROSS_COMPILE}" make "O=${build_dir}" all
        else
            ARCH=arm CROSS_COMPILE="${CROSS_COMPILE}" make "O=${build_dir}" "${config}_defconfig"
            ARCH=arm CROSS_COMPILE="${CROSS_COMPILE}" make "O=${build_dir}" all
        fi
    done

	cd "${SRC_DIR}"
}

build_bootscript()
{
    # Create the boot-scripts for different firmware versions
    cp scripts/boot.cmd "${BUILD_DIR}/boot.cmd"

    # Convert the boot-scripts into proper U-Boot script images
    for cmd_file in "${BUILD_DIR}/"*".cmd"; do
        scr_file="$(basename "${cmd_file%.*}.scr")"
        mkimage -A "${ARCH}" -O linux -T script -C none -a 0x43100000 -n "Boot script" -d "${cmd_file}" "${BUILD_DIR}/${scr_file}"
    done
    echo "Finished building boot scripts."
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
    echo "Usage: ${0} [OPTIONS] [u-boot|imx-atf|container|bootscript|deb]"
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
    build_imx_atf
    build_container
    build_bootscript
    create_debian_package
    exit 0
fi

create_build_dir

case "${1-}" in
    bootscript)
        build_bootscript
        ;;
    container)
        build_uboot
        build_imx_atf
        build_container
        ;;
    deb)
        build_uboot
        build_imx_atf
        build_container
        build_bootscript
        create_debian_package
        ;;
    imx-atf)
        build_imx_atf
        ;;        
    menuconfig)
        build_uboot menuconfig
        ;;
    u-boot)
        build_uboot
        ;;        
    *)
        echo "Error, unknown build option given"
        usage
        exit 1
        ;;
esac

exit 0
