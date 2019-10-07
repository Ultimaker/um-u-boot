#!/bin/bash
set -eu

BOOT_DEV="/dev/mmcblk2p1"
CACHE_FILE="/var/cache/uboot-splashimage/article_number"
EEPROM_HANDLER="/sys/bus/i2c/devices/3-0057/eeprom"
BOM_EEPROM_POS="256"  #Position, in bytes, of the Article Number in EEPROM (0x100 = 256 bytes)

S3_ARTNUM="0x00 0x03 0x41 0xEA"
S5_ARTNUM="0x00 0x03 0x45 0xCB"

UM_SPLASH="SplashUM"
S3_SPLASH="SplashS3"
S5_SPLASH="SplashS5"
SPLASHFILE="umsplash-800x320"

# Wait for the EEPROM handler become available (depends on loading of eeprom kernel module).
for (( seconds_wait=120; $seconds_wait > 0 ; seconds_wait-- )); do 
    if [ -r ${EEPROM_HANDLER} ]; then 
        break
    fi
    sleep 1
done;

if [ ! -r ${EEPROM_HANDLER} ]; then
    echo "EEPROM handler ${EEPROM_HANDLER} not available."
    echo "Maybe kernel module not properly loaded yet."
    exit 1
fi;


# Check if cache directory and cache file exist, and create them if needed.
status_dir="$(dirname ${CACHE_FILE})"
if [ ! -d  "${status_dir}" ]; then
    mkdir "${status_dir}"
fi

if [ ! -r  "${CACHE_FILE}" ]; then
    echo "0x00 0x00 0x00 0x00" > "${CACHE_FILE}"
    chmod 644 "${CACHE_FILE}"
fi

# Compare the stored article number with the EEPROM one and exit if they are equal.
eeprom_art_num="$(hexdump -e '"0x" 1/1 "%02X" " "' -n 4 -s ${BOM_EEPROM_POS} ${EEPROM_HANDLER})"
eeprom_art_num="${eeprom_art_num% }"        # remove the trailing space included by hexdump
cached_art_num="$(cat ${CACHE_FILE})"

if [ "${eeprom_art_num}" = "${cached_art_num}" ]; then
   exit 0
fi

# If /boot is not mounted, mount it.
if ! mount | grep "on /boot" > /dev/null; then
    boot_unmount_later=1
    mount ${BOOT_DEV} /boot/
fi

script_dir="$(dirname "${0}")"

# Uncompress the proper image file and place it named as UBoot expected filename
if [ "${eeprom_art_num}" = "${S3_ARTNUM}" ]; then
    bunzip2 -c  "${script_dir}/${S3_SPLASH}.bmp.bz2" > "/boot/${SPLASHFILE}.bmp"
elif [ "${eeprom_art_num}" = "${S5_ARTNUM}" ]; then
    bunzip2 -c  "${script_dir}/${S5_SPLASH}.bmp.bz2" > "/boot/${SPLASHFILE}.bmp"
else
    bunzip2 -c  "${script_dir}/${UM_SPLASH}.bmp.bz2" > "/boot/${SPLASHFILE}.bmp"
fi

# Store the EEPROM Article Number in a cache file for next boots.
echo "${eeprom_art_num}" > "${CACHE_FILE}"

# If /boot was not mounted before the script runs, unmount it.
if [ "${boot_unmount_later}" = "1" ]; then
    umount /boot/
fi

exit 0

