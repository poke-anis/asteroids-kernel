# Nothing Phone (3a) Pro — Custom Kernel (KernelSU-Next + SUSFS)

Custom Android kernel for the **Nothing Phone (3a) Pro** — codename **`asteroids`**,
SoC Qualcomm **SM7635** (Snapdragon 7s Gen 3, platform codename `pitti`),
kernel **Linux 6.1.157** (GKI `android14-6.1`).

Built entirely in CI (GitHub Actions) from Nothing's official GPL source — no source
tree is vendored here, only the build pipeline and device packaging.

## Features

- **KernelSU-Next** (rifsxd) — kernel-level root, with manual (kprobes-free) syscall hooks.
- **SUSFS** (susfs4ksu, branch `gki-android14-6.1-dev`) — hide root from Play Integrity / banking / games.
- **Baseband-guard** (vc-teahouse) — lightweight LSM blocking writes to critical partitions/nodes.
- **BBR** congestion control + `fq` qdisc (network tweaks).
- `TMPFS_XATTR` / `TMPFS_POSIX_ACL` (Mountify support).
- **LTO: none by default** — the stock kernel ships `LTO_NONE` and we reuse the
  stock vendor modules; Thin/Full LTO changes CFI/codegen and makes those modules
  fault at runtime (bootloop). Only use `thin` if you also rebuild the modules.
- Packaged as a flashable **AnyKernel3** zip (boot-partition GKI flash).

## Kernel source

| | |
|---|---|
| Repo | [`NothingOSS/android_kernel_msm-6.1_nothing_sm7635`](https://github.com/NothingOSS/android_kernel_msm-6.1_nothing_sm7635) |
| Branch | `sm7635/b/mr` |
| Version | **6.1.157** (`android14-6.1-keystone-qcom-release.6.1.157+`, NOS 4.1 Asteroids) |
| Target | `pitti` — config `gki_defconfig` + `arch/arm64/configs/vendor/pitti_GKI.config` |
| Toolchain | AOSP clang `r487747c`, `LLVM=1` (matches `build.config.constants`) |

## Build

Push this repo to GitHub, then run **Actions → “Build Kernel (Nothing 3a Pro / asteroids)” → Run workflow**.
Inputs: `lto` (thin/none), `ksu_branch`, `make_release`. Output: an AnyKernel3 zip artifact
(and optionally a Release).

The pipeline ([`.github/workflows/build.yml`](.github/workflows/build.yml)):

1. Clones the kernel (`sm7635/b/mr`) and the pinned AOSP clang.
2. Integrates KernelSU-Next (`kernel/setup.sh`).
3. Applies SUSFS (copies kernel-side files + `50_add_susfs_in_gki-android14-6.1.patch`).
4. Integrates Baseband-guard.
5. Merges `gki_defconfig` + `pitti_GKI.config` + [`configs/nothing_asteroids_addons.config`](configs/nothing_asteroids_addons.config).
6. Builds the GKI `Image` (`make … LLVM=1 Image`, Thin LTO).
7. Packs [`anykernel3/anykernel.sh`](anykernel3/anykernel.sh) + `Image` into a flashable zip.

> **Why plain `make` and not `bazel`?** The repo's `BUILD.bazel` loads `//build/kernel/kleaf`,
> which is **not** in this repo — Qualcomm's bazel/kleaf build needs the full `kernel_platform`
> manifest (prebuilts, external, `build/`). A bare clone can't run it. For a GKI root kernel we
> only need the `Image`, so the pipeline builds it directly and flashes it via AnyKernel3, keeping
> the stock `vendor_dlkm`/modules (they load because we build from Nothing's exact 6.1.157 source).

## Flashing

Prerequisites: unlocked bootloader, and you are already rooted (needed to run a
kernel flasher). Back up your current `boot` partition first.

**Use the maintained [fatalcoder524 fork of Kernel Flasher](https://github.com/fatalcoder524/KernelFlasher/releases/latest)** —
*not* the original (capntrips) Kernel Flasher, and not the KernelSU-Next manager's
built-in flasher. On newer A/B devices like the 3a Pro those older AnyKernel3
runners fail partition detection with **"Unable to determine partition. Aborting..."**;
the fork fixes exactly that.

1. Install `KernelFlasher_x.y.z.apk` from the fork above.
2. Flash the AnyKernel3 zip **to the active slot** with it.
3. Install the **KernelSU-Next Manager** app (match the KSU-Next version this kernel
   was built with — check the build log's `KSU_VERSION`), open it to confirm root.
4. Configure SUSFS via a module as needed.

> Only for the 3a Pro (`asteroids`). Device-check is **off** by default in `anykernel.sh`
> (see the TODO there) — double-check you're flashing the right device.

## TODO / to verify

These weren't verifiable without a real build — check before trusting a release:

- **Manual hooks** — `CONFIG_KSU_MANUAL_HOOK=y` needs the hook call-sites present. The SUSFS
  patch adds most; if root isn't granted, apply KernelSU-Next's manual-hook patch
  (see <https://kernelsu.org/guide/how-to-integrate-for-non-gki.html> / ReSukiSU manual-integrate).
- **SUSFS + KSU-Next** — assumed no separate KernelSU-side susfs patch is needed on this branch.
  If susfs misbehaves, apply KSU-Next's own susfs patch too.
- **Baseband-guard** — confirm `setup.sh` path/name and the real Kconfig symbol (assumed `CONFIG_BBG`).
- **BBRv3** — only BBRv1 (`CONFIG_TCP_CONG_BBR`) is a Kconfig option in `android14-6.1`.
  BBRv3 requires patching `net/ipv4/tcp_bbr.c` — not included.
- **AnyKernel device names** — set `do.devicecheck=1` + exact `ro.product.device` before public release.
- **Droidspaces-OSS** — evaluated as optional; not integrated.

## Credits

- [KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next) — rifsxd
- [susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu) — simonpunk
- [Baseband-guard](https://github.com/vc-teahouse/Baseband-guard) — vc-teahouse
- [AnyKernel3](https://github.com/osm0sis/AnyKernel3) — osm0sis
- [android_kernel_msm-6.1_nothing_sm7635](https://github.com/NothingOSS/android_kernel_msm-6.1_nothing_sm7635) — Nothing (GPL source)
- Structure/stack inspired by [Origin-Kernel](https://github.com/samakshkambxj/Origin-Kernel) — samakshkambxj

## License

GPL-2.0 — inherits the Linux kernel license.
