#!/bin/bash

umount /dev/sda*

sudo dd if=_build_armhf/msc_sm2_imx6_sd/SPL_signed of=/dev/sda bs=1k seek=1 conv=notrunc
sudo dd if=_build_armhf/msc_sm2_imx6_sd/u-boot-ivt.img_signed of=/dev/sda bs=1k seek=69 conv=notrunc

sync
