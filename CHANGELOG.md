# Changelog

## 0.2.2

### Removed
- systemd, completely: the service manager, units, generators, journald/logind/networkd/resolved, `systemctl` & co.,
  `systemd-udevd`, systemd's `libudev`, the systemd NSS modules and accounts, `/etc/systemd` and `pam_systemd`, plus the
  dead OpenRC scripts (`/etc/init.d`, `/etc/runlevels`, `/etc/conf.d`). `tools/check-no-systemd.sh` enforces it.

### Fixed
- Boot: `could not find the live medium` on machines/VMs whose boot device sits on an ATA/IDE, legacy SCSI, VMware or
  Hyper-V controller (QEMU's default IDE CD-ROM, as used by the BIOS smoke test). The initramfs shipped only
  AHCI/NVMe/USB/virtio drivers, so `/dev/sr0` never appeared. It now ships the whole ata/scsi/usb-storage/nvme/mmc/virtio
  driver directories and the init loads drivers by device modalias (initially and on every wait-loop retry).
- Boot: a missing kernel-module tree no longer produces a silently unbootable ISO. `build-initrd.sh` used to only warn
  when no storage/filesystem modules could be copied; the ISO then died with `could not find the live medium`
  (the 0.2.2 symptom). It now fails the build (`ALLOW_NO_MODULES=1` opts out for a kernel with everything built in).
- Boot: `systemlinux.toram=1` always dropped to the emergency shell, because the free-space check used `df /` of the
  initramfs root (meaningless on ramfs/tmpfs). It now uses `MemAvailable`.
- Boot: the CI smoke test booted the kernel directly (`-kernel`), so GRUB, `grub.cfg` and the BIOS/EFI images were never
  exercised, and it passed at `[live] medium found` without reaching PID 1. `tools/tests/boot-smoke.sh` now boots the
  ISO through its bootloader in both BIOS and UEFI mode and waits for dinit's `boot` service.

### Changed
- Init system: **dinit** replaces systemd as PID 1 (see `docs/DINIT.md`). Service files in `rootfs/etc/dinit.d/`, helper
  scripts in `rootfs/usr/lib/dinit/`, shutdown/reboot/poweroff/halt are dinit's own. The initramfs hands over with
  `switch_root /newroot /usr/bin/dinit` (`init=` overrides). The systemd units and preset were removed.
- `systemlinux-install` now works in legacy BIOS mode too and `--disk` creates a BIOS boot partition + ESP + data (GPT).

### Added
- eudev as the device manager (`tools/eudev/build.sh`) and `tools/libsystemd-stub`, a no-op `libsystemd.so.0` with no
  systemd code for prebuilt programs still linked to it.
- The kernel is the newest Ubuntu `linux-image-generic` (7.3.0 from 26.10), fetched and verified by
  `tools/ubuntu-kernel/fetch.sh`; its full module tree ships in the image.
- 258 more ports (792 in total), each with a verified `sha256`.
- Legacy BIOS boot: hybrid BIOS+UEFI ISO (both GRUB platforms are required at build time), `docs/BIOS.md`.
- About 180 new ports (core utilities, networking, toolchain/developer tools, editors, shells, libraries), all with
  `sha256`. `tools/ports-check.sh` and the `Ports check` workflow validate the tree.
- `tools/dinit/check-services.sh`, `tools/tests/boot-smoke.sh`, `dinit-check` workflow.

### Fixed (earlier 0.2.2 build)
- The live ISO failed to boot with `could not find the live medium (a device with /live/rootfs.squashfs)`: distro
  kernels build isofs, squashfs, overlay, loop and the storage drivers as modules, and the initramfs had none.
  `build_iso.sh` now fetches the `linux-modules` (and `-extra`) packages for the embedded kernel, `build-initrd.sh`
  copies the needed modules (decompressed, with dependencies) and runs `depmod`, and `init` loads them first.
- `init` also finds the medium by its volume label (`SYSTEMLINUX`, or `systemlinux.label=`), logs
  `[live] medium found` and prints filesystems and block devices on failure.

### Changed
- Version 0.2.2; the ISO is `systemLinux-0.2.2-x86_64.iso`, with a BIOS+UEFI hybrid layout when `grub-pc-bin` is installed.
- CI boots the built ISO headless in QEMU and only uploads the artifact when it reaches the live init marker.

## 2.0.0 (2.0)

### Breaking changes
- `goget` is removed and replaced by `get`, a POSIX `sh` script: `get URL` downloads a source tarball, extracts it,
  runs `./configure`, `make` and `make install` into a chosen prefix. `goget upgrade`, the nixpkgs-based package set
  and the `goget-check` update notifier no longer exist; update by installing the new ISO.
- The live ISO is minimal and install-only: the kernel plus the bare minimum to run `systemlinux-install`
  (systemd, NetworkManager, disk/boot tools, `get`). No desktop, firmware bundles, docs, locales, extra daemons,
  compilers or language runtimes.
- The build stack is now installed after installation with `get --profile build-toolchain`
  (also `common-build-deps`, `lang-runtimes`, ...); `validate-build-ready` checks it.
- The init system is systemd (introduced in 1.2); the previous init is gone.
- The ISO is named `systemLinux-2.0-x86_64.iso` (was `systemlinux-vX.Y.iso`) and ships with a `.sha256` file and a
  release-wide `SHA256SUMS`.

### Added
- GitHub Actions: `build-iso.yml` builds the ISO and checksums; `release.yml` publishes a GitHub Release on a
  `v2.0.0` (or `v2.0`) tag.
- Release assets: `systemLinux-2.0-x86_64.iso`, `systemLinux-2.0-x86_64.iso.sha256`, `SHA256SUMS` (covers the ISO and
  the profile archives) and the `profile-NAME.tar.xz` / `.sha256` / `.requires` files that `get --profile NAME` installs.
- `make iso` as a shortcut for `./build_iso.sh`.
- Website: what's new section, 2.0 download and checksum links, `get` usage examples.

### Changed
- Version bumped to 2.0 in `VERSION`, `os-release`, `issue`, the installer/provisioning script, README and website.
