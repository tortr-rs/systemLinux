# systemLinux v0.3

A minimal x86_64 Linux distribution built on a custom monolithic kernel, a
from-scratch Go init (`systemL`), and a Gentoo userland. It boots entirely
into RAM (`/dev/ram0`) and can be installed to disk by following the handbook
below.

Website: `website/index.html` · Release ISO: GitHub release `v0.3`

## System specifications

* **Kernel:** monolithic Linux 7.2.6 with drivers built in for Lenovo IdeaPad and
  MSI targets (`kernel_7.2.6.config`). No initramfs modules: the kernel must be
  able to mount its root device directly.
* **Init:** `systemL`, a static Go binary running as PID 1 (`systemL/`). systemd
  is not used.
* **Base:** Gentoo stage3 (glibc, systemd profile), with Portage and the Gentoo
  tree available for `emerge`.
* **Networking:** NetworkManager, started by systemL together with udev and D-Bus.
* **Packages:** `goget` for normal, self-contained programs (built from GitHub /
  GitLab / Codeberg source or a prebuilt release); `emerge` for large packages
  such as desktop environments.
* **Boot/disk tools:** GRUB 2.12 (BIOS + UEFI x86_64), `efibootmgr`, `dosfstools`,
  util-linux, e2fsprogs. GRUB, efibootmgr and dosfstools are Debian builds
  injected into the rootfs by the build script.

## systemL

systemL mounts `/proc`, `/sys`, `/dev`, `/dev/pts`, `/dev/shm`, `/run` and `/tmp`,
lowers the kernel console log level to errors only, brings up loopback, starts
`udevd` (with a coldplug trigger), runs `mount -a`, starts D-Bus and
NetworkManager under supervision (restart with backoff), then runs a respawning
root shell on tty1. It also reaps orphaned processes and handles shutdown.

Control commands (root):

```sh
systemL status                       # list supervised services
systemL start|stop|restart <service>
systemL reboot | poweroff | halt     # also available as reboot, poweroff, halt, shutdown [-r]
```

Optional configuration under `/etc/systemL/`:

* `login` (empty file): tty1 runs `agetty`/`login` instead of a root shell.
* `services.conf`: extra daemons to supervise, one `<name> <command> [args...]` per line.

Service logs are written to `/run/log/systemL/<name>.log`. `$SYSTEML_TTY`
overrides the console TTY (default `/dev/tty1`).

## Building the ISO

Run on a Debian host, from a normal terminal (it uses `sudo`):

```sh
./build_iso_v0.3.sh
```

The script builds `systemL` and `goget`, installs them into `rootfs/`, links
`init` to systemL, injects GRUB, `efibootmgr` and `dosfstools` from Debian
(checking that all their shared libraries resolve), packs the rootfs into an
initrd, and masters `systemlinux-v0.3.iso` with `grub-mkrescue`. Set
`COMPRESS=zstd` for a much faster (multi-core) initrd pack; gzip is the default.

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

# 5. GRUB config (no initramfs: give the root device directly;
#    use root=PARTUUID=<uuid> if the device path does not mount)
mkdir -p /mnt/target/boot/grub
cat << 'EOF' > /mnt/target/boot/grub/grub.cfg
set default=0
set timeout=3

menuentry "systemLinux v0.3 (Bare Metal)" {
    linux /boot/vmlinuz root=/dev/nvme0n1p2 rw console=tty0 init=/sbin/systemL quiet loglevel=3
}
EOF

# 6. Kernel and bootloader
cp /boot/vmlinuz /mnt/target/boot/vmlinuz
grub-install --target=x86_64-efi --efi-directory=/mnt/target/boot/efi \
  --boot-directory=/mnt/target/boot --removable

# 7. Finish
umount -R /mnt/target
reboot
```

## Known limitations

* The live system runs from RAM: changes are lost on reboot until installed to disk.
* The v0.2 `zram` swap unit and Plymouth splash are systemd-based and are not
  started by systemL.
* `systemctl` remains in the rootfs but does nothing without systemd.
* Desktop environments must be installed with `emerge`; they need a session
  manager (`elogind`) that is not set up yet, and the kernel only has Intel and
  legacy NVIDIA graphics drivers built in (no AMD).
* `goget` does not track installed packages or resolve dependencies.

## Repository layout

```text
├── systemL/              # PID 1 init (main.go, control.go)
├── goget/                # package manager (Go), README inside
├── website/index.html    # project site + handbook
├── build_iso_v0.3.sh     # ISO build pipeline
├── mega_build_v0.2.sh    # older v0.2 build pipeline
├── kernel_7.2.6.config   # monolithic kernel configuration
└── rootfs/               # distribution staging filesystem
```
