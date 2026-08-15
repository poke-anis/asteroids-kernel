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
  libelf-dev cpio ccache build-essential zstd lz4 file dwarves
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
  # SUSFS
  git clone --depth=1 -b "$SUSFS_BRANCH" "$SUSFS_REPO" "$W/susfs4ksu"
  cp "$W"/susfs4ksu/kernel_patches/fs/* fs/
  cp "$W"/susfs4ksu/kernel_patches/include/linux/* include/linux/
  patch -p1 --forward < "$W/susfs4ksu/kernel_patches/50_add_susfs_in_gki-android14-6.1.patch" || echo "WARN: susfs patch rejects"
  # Baseband-guard
  git clone --depth=1 "$BBGUARD_REPO" "$W/Baseband-guard"
  [ -f "$W/Baseband-guard/setup.sh" ] && bash "$W/Baseband-guard/setup.sh" || echo "WARN: bbg setup"
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
make O=out ARCH=arm64 LLVM=1 olddefconfig
CUR_LSM=$(sed -n 's/^CONFIG_LSM="\(.*\)"$/\1/p' out/.config)
if [ -n "$CUR_LSM" ] && ! echo "$CUR_LSM" | grep -qw baseband_guard; then
  ./scripts/config --file out/.config --set-str LSM "${CUR_LSM},baseband_guard"
fi
make O=out ARCH=arm64 LLVM=1 olddefconfig

# --- build -------------------------------------------------------------------
make -j"$(nproc)" O=out ARCH=arm64 LLVM=1 CC="ccache clang" CROSS_COMPILE=aarch64-linux-gnu- Image
ls -lh out/arch/arm64/boot/Image

# --- package -----------------------------------------------------------------
AK="$W/ak3"
[ -d "$AK" ] || git clone --depth=1 "$ANYKERNEL_REPO" "$AK"
cp "$ROOT/anykernel3/anykernel.sh" "$AK/anykernel.sh"
cp out/arch/arm64/boot/Image "$AK/Image"
NAME="Nothing3aPro-asteroids-KSUNext-SUSFS-$(date +%Y%m%d-%H%M)"
( cd "$AK" && rm -rf .git .github && zip -qr9 "$ROOT/${NAME}.zip" . -x '*.git*' )
echo "==> $ROOT/${NAME}.zip"
