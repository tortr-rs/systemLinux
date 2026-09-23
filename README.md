
## HAIIIII :3 if you wanna suppoirt me please donate here [![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/L6N725GI1V)


<p align="center">
  <img src="assets/logo.png" alt="systemLinux logo: a golden wheat ear on a dark green circle" width="160">
</p>

# systemLinux 1.2

A minimal x86_64 GNU/Linux distribution built on a custom monolithic kernel, systemd, and a
GNU userland (GNU bash 5.3 is `/bin/bash` and `/bin/sh`, GNU coreutils, tar, sed, gawk, findutils; the `bbash` fork stays
installed as its own command). One console-only live ISO; no desktop edition. It boots
like any live ISO (a compressed `rootfs.squashfs` on the ISO with a RAM layer on top) and
can be installed to disk with the `systemlinux-install` command-line tool or, step by step
by hand, with the Handbook below. Installed systems update with `goget upgrade`: a signed
system image is downloaded, swapped in at the next reboot with your files kept, and a
failed trial boot rolls back on its own.

systemLinux is **atomic**, like Fedora Silverblue: the system is a read-only image that `goget upgrade` replaces as a whole, with a trial boot and automatic rollback; programs live in separate, rollback-able goget profiles.

Website: `website/index.html` (also the Handbook) · Download: [GitHub release `v1.2`](https://github.com/tortr-rs/systemLinux/releases/tag/v1.2)

| File | Size | RAM needed |
|---|---|---|
| `systemlinux-v1.2.iso` | about 1.9 GB | about 3 GB (4 GB+ to use *copy to RAM*) |

```sh
sha256sum -c systemlinux-v1.2.iso.sha256   # the .sha256 file is on the release page
```

Bundled firmware excludes vendor categories that cannot run on x86_64 at all (Qualcomm
Snapdragon/Adreno SoC firmware, other ARM/embedded-only vendors) and enterprise datacenter
NICs outside this project's laptop/desktop target (Netronome, Mellanox) — real WiFi/BT/GPU
hardware (MediaTek, Marvell, Atheros, AMD, Intel, NVIDIA) is untouched. See `ROADMAP.md` for
what's still deliberately not done (NVIDIA proprietary, Secure Boot, etc.).

Boot in **UEFI mode**: legacy BIOS is not supported (the GRUB build this project ships has
no BIOS/i386-pc modules). Each ISO has three GRUB entries: normal, *copy to RAM* (loads the
whole system into memory so the stick can be removed), and *debug shell* (stops just before
the real system starts).

## System specifications

* **Kernel:** monolithic Linux 7.2.6 with drivers for almost everything built in
  (`kernel_7.2.6-full.config`, over 3,200 options: Wi-Fi, Bluetooth, Intel/AMD/NVIDIA-open
  graphics, storage, sound, laptop hardware, exFAT/NTFS/btrfs/XFS, and a working nftables
  firewall). Built by `tools/kernel-full/`; `kernel_7.2.6.config` is the original, smaller
  config. Firmware comes from nixpkgs' `linux-firmware`/`sof-firmware`, fetched by
  `tools/firmware-overlay/` with `goget` itself, and is loaded by the drivers from the
  initramfs while the kernel starts.
* **Live boot:** a small busybox initramfs (`tools/live-image/`) finds the medium
  (also inside an ISO file on a Ventoy stick), mounts `/live/rootfs.squashfs`, adds a
  tmpfs overlay and switches to systemd. It can also unlock a LUKS-encrypted installed
  system (see "Installing to disk").
* **Shell:** GNU bash 5.3, built static by `tools/gnu-bash/build.sh` and installed as
  `/bin/bash` and `/bin/sh`. BSD tar (`bsdtar`) and friends are not installed: GNU tar is the tar.
* **Init:** systemd 261 (PID 1, with journald, udevd and logind). The base image's own
  services are ordinary systemd units in `/etc/systemd/system/` — see "Services" below.
* **Base:** a glibc userland with GNU bash, coreutils, tar, sed and gawk. Portage and the Gentoo tree are
  gone (since 1.0): `goget` is the only package manager, for the base system's own boot
  tooling as well as everything installed afterward — there is no host-distro package
  manager dependency anywhere in this project, including at build time (see "Building the ISO").
* **Networking:** NetworkManager (`NetworkManager.service`).
* **Everyday hardware and services:** Bluetooth (bluez), audio (PipeWire/WirePlumber,
  system-wide), time sync (chrony), power profiles (`powerprofilesctl`), printing (CUPS),
  firmware updates (`fwupdmgr`), Flatpak (Flathub added automatically at install), and a
  default-deny-inbound nftables firewall — all systemd services, fetched from
  nixpkgs by `tools/base-overlay/`. **systemd-logind** provides session/seat tracking and
  `loginctl suspend` even without a desktop; **polkit** authorizes privileged actions for
  NetworkManager, UDisks2, power-profiles-daemon and CUPS. None of this needs a desktop
  environment — it's all present in the console-only image.
* **Installer:** `systemlinux-install`, an interactive terminal tool (no GUI) — erase a
  whole disk, or install onto an existing partition you already freed up yourself (the safe
  way to dual-boot: no automatic resizing). Optional LUKS full-disk encryption. The
  Handbook documents the same steps by hand, for anyone who'd rather not trust a script (or
  can't run one).
* **Updates:** `goget upgrade` fetches the newest Ed25519-signed image (`latest.json`, SHA-256 per file),
  adds it to GRUB as a one-shot trial and returns to the old image if it fails to boot. The
  persistent layer (`/persist`) keeps your files and settings across updates.
* **Packages:** `goget` installs prebuilt, signed nixpkgs packages (cache.nixos.org) with their dependencies into `/nix/store`,
  exposed through per-user and system profiles with generations: `goget install|remove|list|find|update|run|shell|apply|generations|rollback|gc|channel`.
  `owner/repo` names build from GitHub / GitLab / Codeberg source. `goget graphics` adds GPU drivers for Nix programs.
* **Boot/disk tools:** GRUB 2.12 (UEFI x86_64 only), `efibootmgr`, `dosfstools`,
  util-linux, e2fsprogs, `cryptsetup` (for LUKS). GRUB, efibootmgr, dosfstools and cryptsetup
  are all fetched from nixpkgs by `goget` itself at build time — not from any host distro's
  package manager.

## Services

systemd starts everything; use the usual tools (as root):

```sh
systemctl status [unit]             # what is running (and what failed)
journalctl -b [-u unit]             # this boot's log, or one service's
systemctl start|stop|restart <unit>
systemctl list-timers               # goget-check and the trial-boot check
reboot | poweroff | halt
```

The base image's units live in `/etc/systemd/system/` (sources in
`tools/base-overlay/session/etc/systemd/system/`): `polkit`, `bluetooth`, `chronyd`,
`power-profiles-daemon`, `audio` (system-wide PipeWire), `cups`, `fwupd` and `nftables`, plus
two timers: `goget-check.timer` (runs `goget upgrade --check` every 12h; it only looks, never
installs) and `systemlinux-boot-good.timer` (a minute after boot, makes a trial image from
`goget upgrade` GRUB's default). Add your own units there and `systemctl enable` them.

The live ISO logs root in on tty1 automatically; an installed system asks for a login. Add
`console=ttyS0` to the kernel command line for a login prompt on the first serial port, and
use the *debug* GRUB entry (or drop `quiet`) to see systemd's boot messages.

## Building the ISO

Run on any Linux host with `grub2`, `xorriso`, `mtools`, `squashfs-tools` and `cpio` on
`PATH` — install them with your own package manager (e.g. `emerge sys-boot/grub
app-cdr/xorriso sys-fs/mtools sys-fs/squashfs-tools app-arch/cpio` on Gentoo, `apt install
grub2 xorriso mtools squashfs-tools cpio` on Debian, or the equivalent elsewhere). No
particular host distro is required for anything else: GRUB/efibootmgr/dosfstools/fastfetch
for the *target* image, the firmware overlay, and the base services overlay are all fetched
straight from nixpkgs by `goget` itself, not from a host package manager.

```sh
./build_iso.sh    # systemlinux-v1.2.iso
```

The script builds `goget` and (once) the full kernel, installs them into
`rootfs/`, links `init` to systemd, fixes the D-Bus launch helper permissions, brands
the image with `goget provision`, fetches GRUB/efibootmgr/dosfstools/fastfetch from nixpkgs
(checking nothing against the tracked `rootfs/` — these land in a cached, gitignored work
directory, merged into the squashfs stage only), builds the firmware overlay and the base
services overlay (Bluetooth/audio/chrony/power/printing/firewall/locales, also from
nixpkgs). It then compresses everything into `rootfs.squashfs` (zstd), builds the small
initramfs (which now also carries `cryptsetup`, for LUKS-encrypted installs), and masters
the ISO with `grub-mkrescue`.

## Installing to disk

1. Write the ISO to a USB stick (`dd if=systemlinux-v1.2.iso of=/dev/sdX bs=4M status=progress conv=fsync`,
   or copy it onto a Ventoy stick) and boot it in **UEFI mode**.
2. At the live console, run `sudo systemlinux-install` and answer its prompts (disk or
   existing partition, computer name, your account, timezone, keymap, optional LUKS
   encryption). Or follow the fully manual steps in the Handbook on the website if you'd
   rather not run a script. Either way: erasing a whole disk is one option; installing onto
   an existing partition you've already freed up yourself (shrink Windows or another Linux
   first, with their own tools) is the other — there is no automatic resizing.
3. The disk gets a 512 MB EFI partition and one ext4 (optionally LUKS-encrypted) partition
   holding the system images, GRUB and your files (`/persist`). Update later with `goget
   upgrade` (add `--check` to only look); a new image boots as a trial and the previous one
   is picked again automatically if it fails. Older images can be chosen from the GRUB menu.

The full guide, including troubleshooting and recovery, is the Handbook on the website.

## Known limitations

* The live system keeps your changes only in RAM: they are lost on reboot until installed to disk.
* **UEFI only.** Legacy BIOS boot is not supported at all (the GRUB build shipped here has
  no BIOS/i386-pc modules).
* `systemlinux-install` erases a whole disk or a partition you name; there is no automatic
  partition resizing. Shrink an existing Windows or Linux partition yourself first if you
  want to dual-boot.
* The kernel includes Intel, AMD and the open NVIDIA (nouveau) graphics drivers, but not
  NVIDIA's proprietary driver — there's no packaging path for it (no proprietary blobs are
  bundled), so a driver whose firmware is not in the bundled set will not start.
* **Secure Boot is not supported.** The kernel is structurally ready for it (module
  signing, EFI stub, lockdown LSM are all enabled), but there is no shim/MOK signing
  pipeline in this repo yet — Secure Boot must be turned off in firmware to boot this ISO.
* Programs from nixpkgs that need OpenGL/Vulkan need `sudo goget graphics` once.
* Only `en_US.UTF-8` is pre-baked; see `/etc/profile.d/locale.sh` in `tools/base-overlay/`
  for how to add more from the `glibc-locales` archive. The installer/website UI itself is
  English-only — no translations yet.
* `fcitx5` is installed but not auto-started (there's no desktop session to launch it from) —
  run `fcitx5` by hand, or from a window manager's own startup file, once one is installed via
  `goget`.
* A week of daily use on real hardware, and real hardware validation of suspend/resume,
  lid/power keys and battery/brightness, hasn't happened yet — see `ROADMAP.md`.

## Repository layout

```text
├── goget/                # package manager (Go), README inside; includes `goget provision`
├── tools/base-overlay/   # builds the base services overlay (systemd units for Bluetooth, audio, chrony, power,
│                         #   printing, fwupd, Flatpak, firewall, locales) and ships
│                         #   systemlinux-install, systemlinux-grubcfg, systemlinux-post
├── tools/overlay-common/ # shared overlay helpers (mkcpio.py, goget-profile.sh, strip-gentoo.sh)
├── tools/imagesign/      # signs update indexes (latest.json)
├── tools/kernel-full/    # builds the full-driver kernel (extra-config.txt applied to the base config)
├── tools/firmware-overlay/ # linux-firmware/sof-firmware from nixpkgs, xz-compressed
├── tools/live-image/     # live initramfs (busybox + cryptsetup + init script)
├── website/index.html    # project site + Handbook
├── build_iso.sh           # ISO build pipeline
├── kernel_7.2.6.config     # original kernel configuration
├── kernel_7.2.6-full.config # full-driver kernel configuration
└── rootfs/               # distribution staging filesystem
```
