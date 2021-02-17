# Ultimaker u-boot for iMX-8 (used in Colorado)

This repository is used to build a bootloader for the Congatec iMX-8 System on a Module (SoM) that is used in the Colorado printer. We need a modified bootloader instead of the preflashed one on the SoM for two reasons:

1) to allow booting from SD as a means of recovery, and a means of flashing firmware in our Zaltbommel factory.
2) to allow us to update the bootloader via over-the-air updates in the future, should we need new functionality.

## iMX-8 boot flow
### How it worked in earlier (iMX-6) SoMs
Our previous generation of printers (S3 and S5r2) used iMX-6 SoMs that had a simple boot procedure. A static bootrom in the processor would load the u-boot bootloader from SPI flash, and jump to it. u-boot would then load a kernel and device tree from SD or internal flash, and jump to it. Visually:

Bootrom -> u-boot -> linux kernel (which then loads an initramfs, which loads and starts a Debian rootfs)

### How it works now
The iMX-8 has new security features (ARM Trusted Firmware, "ATF") that make the u-boot step above a bit more complex. Instead of jumping from the bootrom directly into u-boot, on the iMX-8 we jump into a "boot container" ([https://wiki.congatec.com/display/IMX8DOC/i.MX+8M+Mini+Bootcontainer](https://wiki.congatec.com/display/IMX8DOC/i.MX+8M+Mini+Bootcontainer)).

This container contains an ATF binary, u-boot, and a few low level blobs like [DDR memory trainers](https://github.com/librecore-org/librecore/wiki/Understanding-DDR-Memory-Training). Visually:

Bootrom -> SPI[ATF > DDR Training > u-boot] -> linux kernel (and again initramfs > Debian rootfs)

If the SPI flash is **zeroed out**, the bootrom will instead try to load a boot container from SD. You can force this by running `flash_eraseall /dev/mtd0`. The SoM will then load u-boot from SD instead of SPI.

## Consequences for building our bootloader
- Instead of building only u-boot, we need to also compile the ATF binary and build the boot container.
- This build container is flashed to SPI flash, instead of u-boot itself.

## Build instructions
Run `./build_for_ultimaker.sh container` to build boot containers (including u-boot) for SPI flash and for SD (these are 2 slightly different containers). A Debian package containing both will be created that can be used to install the files on a printer, after which jedi-system-update can flash the SPI flash one to the printer.

You can also find the individual SPI and SD boot containers under _build/flash_*.bin. If you want to flash either of them manually, the SPI container is flashed to /dev/mtd0 at offset 0, and the SD container to an SD card at offset 0x8400 (33kB).

## More information
- Ultimaker notes on iMX-8 boot procedure and its differences to iMX-6: [https://confluence.ultimaker.com/pages/viewpage.action?pageId=50501127](https://confluence.ultimaker.com/pages/viewpage.action?pageId=50501127)
- Congatec wiki page on boot container: [https://wiki.congatec.com/display/IMX8DOC/i.MX+8M+Mini+Bootcontainer](https://wiki.congatec.com/display/IMX8DOC/i.MX+8M+Mini+Bootcontainer) 
- NXP documentation of iMX-8 boot procedure: [https://community.nxp.com/t5/i-MX-Processors-Knowledge-Base/i-MX8-Boot-process-and-creating-a-bootable-image/ta-p/1101253](https://community.nxp.com/t5/i-MX-Processors-Knowledge-Base/i-MX8-Boot-process-and-creating-a-bootable-image/ta-p/1101253)