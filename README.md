
## HAIIIII :3 if you wanna suppoirt me please donate here [![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/L6N725GI1V)


<p align="center">
  <img src="assets/logo.png" alt="systemLinux logo: a white cat face on a purple circle" width="160">
</p>

# systemLinux v1.0

A minimal x86_64 GNU/Linux distribution built on a custom monolithic kernel, a
from-scratch Go init (`systemL`), and a GNU userland (GNU bash 5.3 is
`/bin/bash` and `/bin/sh`, GNU coreutils, tar, sed, gawk, findutils; the `bbash` fork stays
installed as its own command). It boots like any live
ISO (a compressed `rootfs.squashfs` on the ISO with a RAM layer on top), in a
**minimal** console edition or a live **GNOME** desktop edition, and can be
installed to disk with the graphical installer or the handbook below. Installed systems update with
`goget upgrade`: a signed system image is downloaded, swapped in at the next reboot with your files kept,
and a failed trial boot rolls back on its own.

Website: `website/index.html` · Downloads: GitHub release `v1.0`

| Edition | File | Size | RAM needed |
|---|---|---|---|
| GNOME | `systemlinux-v1.0-gnome.iso` | 1.3 GB | about 4 GB recommended |
| Minimal | `systemlinux-v1.0-minimal.iso` | 1.1 GB | about 2 GB |

Boot in **UEFI mode** (legacy BIOS boot has not been tested with the current live layout).
Each ISO has three GRUB entries: normal, *copy to RAM* (loads the whole system into memory
so the stick can be removed), and *debug shell* (stops just before the real system starts).

## System specifications

* **Kernel:** monolithic Linux 7.2.6 with drivers for almost everything built in
  (`kernel_7.2.6-full.config`, over 3,200 options: Wi-Fi, Bluetooth, Intel/AMD/NVIDIA-open
  graphics, storage, sound, laptop hardware, exFAT/NTFS/btrfs/XFS). Built by
  `tools/kernel-full/`; `kernel_7.2.6.config` is the original, smaller config.
  Firmware comes from Debian's firmware packages (`tools/firmware-overlay/`) and is
  loaded by the drivers from the initramfs while the kernel starts.
* **Live boot:** a small busybox initramfs (`tools/live-image/`) finds the medium
  (also inside an ISO file on a Ventoy stick), mounts `/live/rootfs.squashfs`, adds a
  tmpfs overlay and switches to systemL.
* **Shell:** GNU bash 5.3, built static by `tools/gnu-bash/build.sh` and installed as
  `/bin/bash` and `/bin/sh`. BSD tar (`bsdtar`) and friends are not installed: GNU tar is the tar.
* **Init:** `systemL`, a static Go binary running as PID 1 (`systemL/`). systemd
  is not used.
* **Base:** a glibc userland with GNU bash, coreutils, tar, sed and gawk. Portage and the Gentoo tree are
  gone (since 1.0): `goget` is the only package manager.
* **Networking:** NetworkManager, started by systemL together with udev and D-Bus.
* **Desktop (GNOME edition):** GNOME 48 (Wayland) with Nautilus, Console, Settings and Firefox ESR,
  from Debian packages layered onto the base (`tools/gnome-overlay/`). Without systemd it runs on
  **elogind** (sessions/seats) and **polkit**, both started by systemL; the GNOME libraries take
  precedence over the base's same-named ones (`LIB_OVERRIDE` in `tools/overlay-common/merge.py`).
  The live session is an autologin user `live` on tty1 whose login shell starts GNOME
  (`/etc/profile.d/systemlinux-gnome.sh`, with a crash-loop guard); installed systems start GNOME
  from the tty1 login the same way.
* **Installer:** a native GNOME (GTK4/libadwaita) installer, `systemlinux-installer` (welcome, disk, account,
  region, summary, progress). It erases one disk, creates an EFI partition and a data partition, and installs
  the system image plus GRUB; the installed system autologins to GNOME or asks for a login on tty1.
* **Updates:** `goget upgrade` fetches the newest Ed25519-signed image (`latest.json`, SHA-256 per file),
  adds it to GRUB as a one-shot trial and returns to the old image if it fails to boot. The persistent
  layer (`/persist`) keeps your files and settings across updates.
* **Packages:** `goget` installs prebuilt, signed nixpkgs packages (cache.nixos.org) with their dependencies into `/nix/store`,
  exposed through per-user and system profiles with generations: `goget install|remove|list|find|update|run|shell|apply|generations|rollback|gc|channel`.
  `owner/repo` names build from GitHub / GitLab / Codeberg source. `goget graphics` adds GPU drivers for Nix programs.
* **Boot/disk tools:** GRUB 2.12 (BIOS + UEFI x86_64), `efibootmgr`, `dosfstools`,
  util-linux, e2fsprogs. GRUB, efibootmgr and dosfstools are Debian builds
  injected into the rootfs by the build script.

## systemL

systemL mounts `/proc`, `/sys`, `/dev`, `/dev/pts`, `/dev/shm`, `/run` and `/tmp`,
lowers the kernel console log level to errors only, sets the hostname (from
`/etc/hostname`, default `systemlinux`), brings up loopback, starts `udevd` (with
a coldplug trigger), runs `mount -a`, starts D-Bus and NetworkManager under
supervision (restart with backoff), then runs a respawning root shell on tty1.
It also reaps orphaned processes and handles shutdown.

Control commands (root):

```sh
systemL status                       # list supervised services
systemL log [service]                # systemL prints nothing to the terminal; read its log (or a service's)
systemL start|stop|restart <service>
systemL reboot | poweroff | halt     # also available as reboot, poweroff, halt, shutdown [-r]
```

Optional configuration under `/etc/systemL/`:

* `login` (empty file): tty1 runs `agetty`/`login` instead of a root shell.
* `services.conf`: extra daemons to supervise, one `<name> <command> [args...]` per line.
  The GNOME edition uses it to start elogind and polkit.

systemL's own messages go to `/run/log/systemL/systemL.log` and each service's output to
`/run/log/systemL/<name>.log`; nothing is printed to the terminal (add `systeml.verbose=1` to the
kernel command line to see it on screen, or use the "debug shell" GRUB entry). `$SYSTEML_TTY`
overrides the console TTY (default `/dev/tty1`).

## Building the ISOs

Run on a Debian host, from a normal terminal (it uses `sudo`):

```sh
VARIANT=minimal ./build_iso.sh    # systemlinux-v1.0-minimal.iso
VARIANT=gnome   ./build_iso.sh    # systemlinux-v1.0-gnome.iso
```

The script builds `systemL`, `goget` and (once) the full kernel, installs them into
`rootfs/`, links `init` to systemL, fixes the D-Bus launch helper permissions, brands
the image with `goget provision`, injects GRUB, `efibootmgr` and `dosfstools` from Debian
(checking that all their shared libraries resolve), builds the firmware overlay, and for
the GNOME edition the desktop overlay (`tools/gnome-overlay/build-overlay.sh`). It then
compresses everything into `rootfs.squashfs` (zstd), builds the small initramfs, and
masters the ISO with `grub-mkrescue`.

## Installing to disk

1. Write the GNOME ISO to a USB stick (`dd if=systemlinux-v1.0-gnome.iso of=/dev/sdX bs=4M status=progress conv=fsync`,
   or copy it onto a Ventoy stick) and boot it in UEFI mode.
2. In the live desktop open **Install systemLinux**: choose the disk (it is erased), set your account, time
   zone and keyboard, review the summary and install. Restart and remove the stick.
3. The disk gets a 512 MB EFI partition and one ext4 partition holding the system images, GRUB and your
   files (`/persist`). Update later with `goget upgrade` (add `--check` to only look); a new image boots as
   a trial and the previous one is picked again automatically if it fails. Older images can be chosen from
   the GRUB menu.

The full guide, including troubleshooting, is the Handbook on the website.

## Known limitations

* The live system keeps your changes only in RAM: they are lost on reboot until installed to disk.
* Boot in UEFI mode; legacy BIOS boot has not been tested with the current live layout.
* The graphical installer erases a whole disk; no resizing or dual boot yet.
* The kernel includes Intel, AMD and the open NVIDIA (nouveau) graphics drivers, but not
  NVIDIA's proprietary driver; a driver whose firmware is not in the bundled set will not start.
* The v0.2 `zram` swap unit and Plymouth splash are systemd-based and are not
  started by systemL. `systemctl` remains in the rootfs but does nothing.
* Programs from nixpkgs that need OpenGL/Vulkan need `sudo goget graphics` once; the sign-in screen is GDM (Wayland; no Xorg).

## Repository layout

```text
├── systemL/              # PID 1 init (main.go, control.go)
├── goget/                # package manager (Go), README inside; includes `goget provision`
├── tools/gnome-overlay/  # builds the live GNOME overlay (elogind, polkit, installer app, session files)
├── tools/overlay-common/ # shared overlay merge/post scripts
├── tools/imagesign/      # signs update indexes (latest.json)
├── tools/kernel-full/    # builds the full-driver kernel (extra-config.txt applied to the base config)
├── tools/firmware-overlay/ # Debian firmware packages, xz-compressed
├── tools/live-image/     # live initramfs (busybox + init script)
├── website/index.html    # project site + handbook
├── build_iso.sh          # ISO build pipeline (VARIANT=minimal|gnome)
├── mega_build_v0.2.sh    # older v0.2 build pipeline
├── kernel_7.2.6.config   # original kernel configuration
├── kernel_7.2.6-full.config # full-driver kernel configuration
└── rootfs/               # distribution staging filesystem
```
