
## HAIIIII :3 if you wanna suppoirt me please donate here [![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/L6N725GI1V)


<p align="center">
  <img src="assets/logo.png" alt="systemLinux logo: a white cat face on a purple circle" width="160">
</p>

# systemLinux v0.5

A minimal x86_64 GNU/Linux distribution built on a custom monolithic kernel, a
from-scratch Go init (`systemL`), and a GNU userland on a Gentoo base (GNU bash 5.3 is
`/bin/bash` and `/bin/sh`, GNU coreutils, tar, sed, gawk, findutils; the `bbash` fork stays
installed as its own command). It boots like any live
ISO (a compressed `rootfs.squashfs` on the ISO with a RAM layer on top), in a
**minimal** console edition or a live **GNOME** desktop edition, and can be
installed to disk with the graphical installer or the handbook below. Installed systems update with
`goget upgrade`: a signed system image is downloaded, swapped in at the next reboot with your files kept,
and a failed trial boot rolls back on its own.

Website: `website/index.html` · Downloads: GitHub release `v0.5`

| Edition | File | Size | RAM needed |
|---|---|---|---|
| GNOME | `systemlinux-v0.5-gnome.iso` | 2.1 GB | about 6 GB recommended |
| Minimal | `systemlinux-v0.5-minimal.iso` | 1.8 GB | about 2 GB |

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
* **Base:** Gentoo stage3 (glibc, systemd profile), with Portage and the Gentoo
  tree available for `emerge`.
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
* **Packages:** `goget` for normal, self-contained programs (built from GitHub /
  GitLab / Codeberg source or a prebuilt release); `emerge` for large packages.
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
VARIANT=minimal ./build_iso.sh    # systemlinux-v0.5-minimal.iso
VARIANT=gnome   ./build_iso.sh    # systemlinux-v0.5-gnome.iso
```

The script builds `systemL`, `goget` and (once) the full kernel, installs them into
`rootfs/`, links `init` to systemL, fixes the D-Bus launch helper permissions, brands
the image with `goget provision`, injects GRUB, `efibootmgr` and `dosfstools` from Debian
(checking that all their shared libraries resolve), builds the firmware overlay, and for
the GNOME edition the desktop overlay (`tools/gnome-overlay/build-overlay.sh`). It then
compresses everything into `rootfs.squashfs` (zstd), builds the small initramfs, and
masters the ISO with `grub-mkrescue`.

## Installing to disk (handbook)

Run as root from the live system. **The target disk is erased.** The commands
assume an NVMe drive; adjust device names for SATA.

```sh
# 0. Partition: GPT with a 512MB ESP and a root partition
sfdisk /dev/nvme0n1 <<'EOF'
label: gpt
,512M,U
,,L
EOF

# 1. Format
mkfs.vfat -F32 /dev/nvme0n1p1
mkfs.ext4 /dev/nvme0n1p2

# 2. Mount root, then the ESP inside it
mkdir -p /mnt/target
mount /dev/nvme0n1p2 /mnt/target
mkdir -p /mnt/target/boot/efi
mount /dev/nvme0n1p1 /mnt/target/boot/efi

# 3. Copy the live system (-x stays on one filesystem), recreate mount points
cp -ax / /mnt/target/
mkdir -p /mnt/target/proc /mnt/target/sys /mnt/target/dev /mnt/target/run /mnt/target/tmp
chmod 1777 /mnt/target/tmp

# 4. fstab
cat << 'EOF' > /mnt/target/etc/fstab
/dev/nvme0n1p2  /         ext4  errors=remount-ro  0  1
/dev/nvme0n1p1  /boot/efi vfat  defaults           0  2
EOF

# 5. GRUB config (no initramfs: give the root device directly; rootwait waits for
#    the drive to appear; use root=PARTUUID=<uuid> if the device path does not mount)
mkdir -p /mnt/target/boot/grub
cat << 'EOF' > /mnt/target/boot/grub/grub.cfg
set default=0
set timeout=3

menuentry "systemLinux v0.5 (Bare Metal)" {
    linux /boot/vmlinuz root=/dev/nvme0n1p2 rootwait rw console=tty0 init=/sbin/systemL quiet loglevel=3
}
EOF

# 6. Kernel and bootloader
cp /boot/vmlinuz /mnt/target/boot/vmlinuz
grub-install --target=x86_64-efi --efi-directory=/mnt/target/boot/efi \
  --boot-directory=/mnt/target/boot --removable

# 7. Optional: brand the install and create a first user (wheel, portage,
#    networkmanager, sudo rule; prompts for a password). With a user set up,
#    have tty1 ask for a login instead of opening a root shell.
goget provision --user yourname /mnt/target
mkdir -p /mnt/target/etc/systemL && touch /mnt/target/etc/systemL/login

# 8. Finish
umount -R /mnt/target
reboot
```

## Known limitations

* The live system keeps your changes only in RAM: they are lost on reboot until installed to disk.
* Boot in UEFI mode; legacy BIOS boot has not been tested with the current live layout.
* The graphical installer erases a whole disk; no resizing or dual boot yet.
* The kernel includes Intel, AMD and the open NVIDIA (nouveau) graphics drivers, but not
  NVIDIA's proprietary driver; a driver whose firmware is not in the bundled set will not start.
* The v0.2 `zram` swap unit and Plymouth splash are systemd-based and are not
  started by systemL. `systemctl` remains in the rootfs but does nothing.
* `goget` does not track installed packages or resolve dependencies; use `emerge`
  for large packages.

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
