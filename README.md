# systemLinux v0.2

A minimal, x86_64 meta-distribution built on a custom monolithic kernel configuration and a systemd-managed ramdisk (`initramfs`). The environment runs entirely out of physical volatile memory (`/dev/ram0`).

## System Specifications
* **Kernel:** Monolithic Linux 7.2.6 (Compiled with direct hardware drivers for Lenovo IdeaPad and MSI target platforms).
* **Init:** systemd acting as PID 1 handling native tty sessions and service tracking.
* **Base:** Gentoo Stage 3 (glibc userland profile).
* **Package Engine:** `goget v0.2` (Go binary using native `os/exec` libraries to parse local JSON recipe files. Includes fallback compilation matching for Makefiles, Go modules, CMake, and Autotools when manual build steps are missing).
* **Memory Management:** In-memory Zram swap service compressing active memory blocks via zstd at a 3:1 ratio to expand workspace capacity during parallel compilation tasks.
* **Visuals:** Pure text-mode custom ASCII banner for terminal logins and text-mode GNU Horns Plymouth theme configuration.

---

## Workspace Layout
```text
├── rootfs/                 # Distribution staging environment filesystem
│   ├── etc/systemd/        # Service overrides and custom unit trackers
│   ├── root/.config/       # Targeted fastfetch system profile configs
│   └── usr/share/plymouth/ # Standard text-mode Plymouth assets
├── manifest.go             # Source file for the goget v0.2 package manager
└── README.md               # Technical specification document
```

---

## Target Device Persistent Installation Steps

To deploy systemLinux onto internal storage (SSD/NVMe) from the live environment:

1. Partition the storage target:
```bash
fdisk /dev/nvme0n1
```

2. Format the primary root boundary:
```bash
mkfs.ext4 /dev/nvme0n1p2
```

3. Mount the new space and sync the running files down to the disk:
```bash
mount /dev/nvme0n1p2 /mnt
rsync -aAXv --exclude=/proc --exclude=/sys --exclude=/dev --exclude=/run / /mnt/
```

4. Map vital interfaces and switch into the physical installation to configure the boot files:
```bash
mount --bind /dev /mnt/dev
chroot /mnt
```

