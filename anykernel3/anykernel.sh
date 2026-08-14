# AnyKernel3 Ramdisk Mod Script
# Nothing Phone (3a) Pro  -  asteroids / SM7635  -  GKI (boot partition, Image only)
# osm0sis/AnyKernel3

## AnyKernel setup
properties() { '
kernel.string=Nothing Phone 3a Pro Custom Kernel (asteroids) - KernelSU-Next + SUSFS
do.devicecheck=0
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=1
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
## boot files attributes
boot_attributes() {
seclabel=u:object_r:boot_block_device:s0
}

## GKI: flash the kernel Image into the boot partition
block=boot;
is_slot_device=1;
ramdisk_compression=auto;
patch_vbmeta_flag=auto;

# import functions/variables and setup patching - see AnyKernel3 README
. tools/ak3-core.sh && boot_attributes;

# GKI boot image: replace the kernel, keep everything else, repack, flash
dump_boot;
write_boot;
## end boot install
