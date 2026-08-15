#!/usr/bin/env bash
# Local build, mirrors .github/workflows/build.yml. Run inside WSL2 Ubuntu.
#   ./build-local.sh [thin|none]
# Re-runs are fast: toolchain/kernel/susfs are cached, ccache speeds recompiles.
# Force a clean tree with:  CLEAN=1 ./build-local.sh
set -euo pipefail
cd "$(dirname "$0")"
ROOT=$(pwd)
LTO="${1:-thin}"

# --- same knobs as the workflow ----------------------------------------------
KERNEL_REPO=https://github.com/NothingOSS/android_kernel_msm-6.1_nothing_sm7635
KERNEL_BRANCH=sm7635/b/mr
DEFCONFIG_FRAGMENT=vendor/pitti_GKI.config
CLANG_URL=https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/android14-release/clang-r487747c.tar.gz
SUSFS_REPO=https://gitlab.com/simonpunk/susfs4ksu
SUSFS_BRANCH=gki-android14-6.1-dev
BBGUARD_REPO=https://github.com/vc-teahouse/Baseband-guard
ANYKERNEL_REPO=https://github.com/osm0sis/AnyKernel3
KSU_BRANCH=next

W="$ROOT/build"                 # all working files live here
[ "${CLEAN:-0}" = "1" ] && rm -rf "$W"
mkdir -p "$W"

# --- deps (idempotent) -------------------------------------------------------
sudo apt-get update -qq
sudo apt-get install -y -qq --no-install-recommends \
  bc bison flex libssl-dev make gcc git zip curl python3 python-is-python3 \
  libelf-dev cpio ccache build-essential zstd lz4 file dwarves unzip
export PATH="/usr/lib/ccache:$PATH" CCACHE_DIR="${CCACHE_DIR:-$HOME/.ccache}"

# --- toolchain (cached) ------------------------------------------------------
if [ ! -x "$W/toolchain/clang/bin/clang" ]; then
  mkdir -p "$W/toolchain/clang"
  curl -fLSs "$CLANG_URL" -o "$W/clang.tar.gz"
  file "$W/clang.tar.gz" | grep -q gzip || { echo "CLANG_URL not a gzip"; exit 1; }
  tar -C "$W/toolchain/clang" -xzf "$W/clang.tar.gz"
fi
export PATH="$W/toolchain/clang/bin:$PATH"
clang --version | head -1

# --- kernel + integrations (only on first run) -------------------------------
K="$W/kernel"
if [ ! -d "$K" ]; then
  git clone --depth=1 -b "$KERNEL_BRANCH" "$KERNEL_REPO" "$K"
  cd "$K"
  # KernelSU-Next
  curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/${KSU_BRANCH}/kernel/setup.sh" | bash -s "$KSU_BRANCH"
  # SUSFS (skipped when SUSFS=0 so CLEAN=1 SUSFS=0 gives a patch-free tree)
  if [ "${SUSFS:-1}" = 1 ]; then
    git clone --depth=1 -b "$SUSFS_BRANCH" "$SUSFS_REPO" "$W/susfs4ksu"
    cp "$W"/susfs4ksu/kernel_patches/fs/* fs/
    cp "$W"/susfs4ksu/kernel_patches/include/linux/* include/linux/
    patch -p1 --forward < "$W/susfs4ksu/kernel_patches/50_add_susfs_in_gki-android14-6.1.patch" || echo "WARN: susfs patch rejects"
  fi
  # Baseband-guard (skipped when BBG=0)
  if [ "${BBG:-1}" = 1 ]; then
    git clone --depth=1 "$BBGUARD_REPO" "$W/Baseband-guard"
    [ -f "$W/Baseband-guard/setup.sh" ] && bash "$W/Baseband-guard/setup.sh" || echo "WARN: bbg setup"
  fi
fi
cd "$K"

# --- defconfig ---------------------------------------------------------------
mkdir -p out
bash scripts/kconfig/merge_config.sh -m -O out \
  arch/arm64/configs/gki_defconfig \
  "arch/arm64/configs/${DEFCONFIG_FRAGMENT}" \
  "$ROOT/configs/nothing_asteroids_addons.config"
if [ "$LTO" = "none" ]; then
  ./scripts/config --file out/.config -d LTO_CLANG_THIN -d LTO_CLANG_FULL -e LTO_NONE
fi
# Bisect toggles (config-only; works on the cached tree). Default on.
#   BBG=0   -> drop baseband_guard LSM         (prime bootloop suspect)
#   SUSFS=0 -> drop SUSFS hooks
[ "${BBG:-1}" = 1 ]   || ./scripts/config --file out/.config -d BBG
[ "${SUSFS:-1}" = 1 ] || ./scripts/config --file out/.config -d KSU_SUSFS
make O=out ARCH=arm64 LLVM=1 olddefconfig
CUR_LSM=$(sed -n 's/^CONFIG_LSM="\(.*\)"$/\1/p' out/.config)
if [ "${BBG:-1}" = 1 ] && [ -n "$CUR_LSM" ] && ! echo "$CUR_LSM" | grep -qw baseband_guard; then
  ./scripts/config --file out/.config --set-str LSM "${CUR_LSM},baseband_guard"
fi
make O=out ARCH=arm64 LLVM=1 olddefconfig
echo "toggles: BBG=${BBG:-1} SUSFS=${SUSFS:-1} | $(grep -E '^CONFIG_(BBG|KSU_SUSFS)=' out/.config | tr '\n' ' ')"

# --- build -------------------------------------------------------------------
make -j"$(nproc)" O=out ARCH=arm64 LLVM=1 CC="ccache clang" CROSS_COMPILE=aarch64-linux-gnu- Image
ls -lh out/arch/arm64/boot/Image

# --- package -----------------------------------------------------------------
AK="$W/ak3"
[ -d "$AK" ] || git clone --depth=1 "$ANYKERNEL_REPO" "$AK"
# Swap AnyKernel3's 32-bit tools for arm64 ones (the 3a Pro has no 32-bit
# userspace -> "busybox setup failed"). Official binaries from Magisk.
if ! file "$AK/tools/busybox" | grep -q aarch64; then
  MAGISK_URL=$(curl -fsSL https://api.github.com/repos/topjohnwu/Magisk/releases/latest | grep -o 'https://[^"]*\.apk' | head -1)
  curl -fLSs "$MAGISK_URL" -o "$W/magisk.apk"
  unzip -o -q "$W/magisk.apk" 'lib/arm64-v8a/*' -d "$W/magisk_x"
  cp "$W"/magisk_x/lib/arm64-v8a/libmagiskboot.so   "$AK/tools/magiskboot"
  cp "$W"/magisk_x/lib/arm64-v8a/libbusybox.so      "$AK/tools/busybox"
  cp "$W"/magisk_x/lib/arm64-v8a/libmagiskpolicy.so "$AK/tools/magiskpolicy" 2>/dev/null || true
  chmod +x "$AK"/tools/magiskboot "$AK"/tools/busybox "$AK"/tools/magiskpolicy
fi
cp "$ROOT/anykernel3/anykernel.sh" "$AK/anykernel.sh"
cp out/arch/arm64/boot/Image "$AK/Image"
NAME="Nothing3aPro-asteroids-KSUNext-SUSFS-$(date +%Y%m%d-%H%M)"
( cd "$AK" && rm -rf .git .github && zip -qr9 "$ROOT/${NAME}.zip" . -x '*.git*' )
echo "==> $ROOT/${NAME}.zip"
