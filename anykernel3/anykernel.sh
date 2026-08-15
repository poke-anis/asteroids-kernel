# AnyKernel3 Ramdisk Mod Script
# Nothing Phone (3a) Pro  -  asteroids / SM7635  -  GKI (boot partition, Image only)
# osm0sis/AnyKernel3
# Install flow mirrors samakshkambxj/Origin-Kernel's proven release config.

## AnyKernel setup
properties() { '
kernel.string=Nothing Phone 3a Pro Custom Kernel (asteroids) - KernelSU-Next + SUSFS
do.devicecheck=0
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=asteroids
device.name2=Asteroids
device.name3=
device.name4=
device.name5=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties
# TODO verify: set do.devicecheck=1 and put the exact `ro.product.device` /
# `ro.product.vendor.device` value(s) of the 3a Pro into device.nameN before
# public release, so the zip refuses to flash on the wrong device.

### AnyKernel install
## boot shell variables
# Name (not a hardcoded path) so AK3 searches every known by-name root, and
# is_slot_device=auto so AK3 detects the A/B slot itself instead of depending on
# a slot_suffix prop that some flashers (e.g. Kernel Flasher) don't expose.
block=boot
is_slot_device=auto
ramdisk_compression=auto
patch_vbmeta_flag=auto
no_magisk_check=1

# import functions/variables and setup patching - see AnyKernel3 README
. tools/ak3-core.sh

# boot install: repack if the boot image carries a ramdisk, else flash the
# GKI-style (ramdisk-less) boot with the new kernel.
split_boot
if [ -f "split_img/ramdisk.cpio" ]; then
  unpack_ramdisk
  write_boot
else
  flash_boot
fi
