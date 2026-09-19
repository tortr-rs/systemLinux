#!/bin/bash
# systemLinux v0.2 Automated Monolithic Construction Pipeline
set -e

# Establish core system path anchors
export BUILD_DIR=~/systemlinux
export ROOTFS=$BUILD_DIR/rootfs
export WORKSPACE=$BUILD_DIR/iso_workspace

echo "=== [1/7] WIPING PREVIOUS STAGING BLOCKS ==="
sudo rm -rf "$WORKSPACE" "$BUILD_DIR/systemlinux-v0.2.iso" "$BUILD_DIR/bbash_source" "$BUILD_DIR/evim_source"
mkdir -p "$WORKSPACE/live" "$WORKSPACE/boot/grub"

echo "=== [2/7] FETCHING AND NATIVELY COMPILING BBASH SOURCE ==="
sudo apt-get update && sudo apt-get install -y libarchive-dev

# COMPLETELY FLAT URL WITH NO BLANK VARIABLES
git clone https://github.com /home/torter/systemlinux/bbash_source

cd /home/torter/systemlinux/bbash_source
./configure --prefix=/
make -j$(nproc)
sudo cp ./bash /home/torter/systemlinux/rootfs/bin/bbash
sudo chmod +x /home/torter/systemlinux/rootfs/bin/bbash
cd /home/torter/systemlinux

# Force establish internal system identity shell links to bbash
cd /home/torter/systemlinux/rootfs/bin
sudo ln -sf bbash bash
sudo ln -sf bbash sh
cd /home/torter/systemlinux

echo "=== [3/7] INJECTING EVIM MODAL TEXT EDITOR RUNTIME ==="
# COMPLETELY FLAT URL WITH NO BLANK VARIABLES
git clone https://github.com /home/torter/systemlinux/evim_source

sudo cp /home/torter/systemlinux/evim_source/evim.py /home/torter/systemlinux/rootfs/usr/bin/evim
sudo chmod +x /home/torter/systemlinux/rootfs/usr/bin/evim

echo "=== [4/7] MOUNTING CORE INTERFACES AND DEPLOYING COMPILERS ==="
# 1. Bind host virtual subsystems to unlock chroot network and device tracking loops
sudo mount --bind /dev /home/torter/systemlinux/rootfs/dev
sudo mount --bind /dev/pts /home/torter/systemlinux/rootfs/dev/pts
sudo mount --bind /proc /home/torter/systemlinux/rootfs/proc
sudo mount --bind /sys /home/torter/systemlinux/rootfs/sys

# 2. Force stable fallback C local descriptors to mute interface warnings
export LC_ALL=C
export LANG=C

# 3. Execution Trap: Guarantee clean host unmounting if compiler loops crash
trap 'sudo umount /home/torter/systemlinux/rootfs/dev/pts 2>/dev/null || true; sudo umount /home/torter/systemlinux/rootfs/dev 2>/dev/null || true; sudo umount /home/torter/systemlinux/rootfs/proc 2>/dev/null || true; sudo umount /home/torter/systemlinux/rootfs/sys 2>/dev/null || true' EXIT

# 4. Stream stable language runtimes using updated Gentoo categories
sudo chroot /home/torter/systemlinux/rootfs emerge --oneshot --usepkg \
    sys-devel/gcc \
    dev-build/make \
    dev-build/cmake \
    dev-build/autoconf \
    dev-lang/go \
    dev-lang/rust-bin \
    dev-lang/python \
    dev-lang/typescript \
    net-libs/nodejs \
    dev-lang/php \
    dev-lang/ruby \
    dev-lang/perl \
    dev-lang/tcl

# 5. Cleanly tear down interface loops
sudo umount /home/torter/systemlinux/rootfs/dev/pts
sudo umount /home/torter/systemlinux/rootfs/dev
sudo umount /home/torter/systemlinux/rootfs/proc
sudo umount /home/torter/systemlinux/rootfs/sys
trap - EXIT

echo "=== [5/7] BAKING IN MEMORY ALLOCATOR ZRAM 3:1 DEPLOYMENT ==="
cat << 'EOF' | sudo tee /home/torter/systemlinux/rootfs/etc/systemd/system/zram.service
[Unit]
Description=systemLinux Dynamic Zram 3:1 Compression Allocator
Before=local-fs.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'modprobe zram && echo zstd > /sys/block/zram0/comp_algorithm && echo 4G > /sys/block/zram0/disksize && mkswap /dev/zram0 && swapon /dev/zram0 -p 32767'

[Install]
WantedBy=multi-user.target
EOF
sudo ln -sf /etc/systemd/system/zram.service /home/torter/systemlinux/rootfs/etc/systemd/system/multi-user.target.wants/zram.service

echo "=== [6/7] LAYING DOWN PLYMOUTH BOOT SPLASH AND FASTFETCH MASCOT ==="
# Configure the visual text mode initialization screens (GNU Horns)
sudo mkdir -p /home/torter/systemlinux/rootfs/usr/share/plymouth/themes/systemlinux-gnu

cat << 'EOF' | sudo tee /home/torter/systemlinux/rootfs/usr/share/plymouth/themes/systemlinux-gnu/systemlinux-gnu.plymouth
[Plymouth Theme]
Name=systemLinux GNU Text
Description=Brutalist text mode splash displaying the GNU Horns mascot logo
ModuleName=ubuntu-text

[ubuntu-text]
title=systemLinux v0.2
black=0x000000
white=0xffffff
light_cyan=0x00ffff
EOF

cat << 'EOF' | sudo tee /home/torter/systemlinux/rootfs/usr/share/plymouth/themes/systemlinux-gnu/systemlinux-gnu.script
    .-_..---.._-.
   (_..-''   ''-.._)
        /     \
       /       \

      |   O   O |
      |    \_/  |
       \       /
        '-...-'
     systemLinux
EOF

# Inject the clean feline system definition configurations
sudo mkdir -p /home/torter/systemlinux/rootfs/root/.config/fastfetch

cat << 'EOF' | sudo tee /home/torter/systemlinux/rootfs/root/.config/fastfetch/logo.txt
  /\_/\
 ( o.o )
  > ^ <
systemLinux
EOF

cat << 'EOF' | sudo tee /home/torter/systemlinux/rootfs/root/.config/fastfetch/config.jsonc
{
    "$schema": "https://github.com",
    "logo": {
        "source": "/root/.config/fastfetch/logo.txt",
        "color": {
            "1": "cyan"
        },
        "padding": {
            "top": 1,
            "left": 2,
            "right": 4
        }
    },
    "modules": [
        "title",
        "separator",
        "os",
        "host",
        "kernel",
        "uptime",
        "memory",
        "shell"
    ]
}
EOF

# Overwrite terminal interaction welcome banners to match bbash properties
cat << 'EOF' | sudo tee /home/torter/systemlinux/rootfs/root/.bash_profile
export PATH=/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/bin
export PS1='systemLinux:\w\$ '
clear
echo -e "\033[0;36m" # Cyan
echo "       /\_/\  "
echo "      ( o.o ) "
echo "       > ^ <  "
echo -e "\033[0;34m" # Blue
echo "=================================================="
echo " systemLinux v0.2 (Source-First Build)           "
echo " Monolithic Kernel 7.2.6 // Pure systemd Ramdisk "
echo " Default Shell: bbash (Better Bash 5.3 Active)    "
echo "=================================================="
echo -e "\033[0m"
EOF

# Enforce systemd initialization processes to feed directly to bbash
sudo mkdir -p /home/torter/systemlinux/rootfs/etc/systemd/system/getty@tty1.service.d
cat << 'EOF' | sudo tee /home/torter/systemlinux/rootfs/etc/systemd/system/getty@tty1.service.d/override.conf
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I 38400 linux --shell /bin/bbash
Type=idle
EOF

echo "=== [7/7] SQUEEZING FINAL MEMORY PAYLOAD AND GENERATING ISO ==="
# Compress complete userland layout configurations directly into rootfs archive format
cd /home/torter/systemlinux/rootfs
sudo find . -print0 | sudo cpio --null -ov --format=newc | gzip -9 > /home/torter/systemlinux/iso_workspace/live/initrd.img
cd /home/torter/systemlinux

# Carry over your finalized Kernel 7.2.6 monolithic image asset
cp /home/torter/systemlinux/linux-7.2.6/arch/x86/boot/bzImage /home/torter/systemlinux/iso_workspace/live/vmlinuz

# Set up standard systemd GRUB boot directives linking bbash natively
cat << 'EOF' > /home/torter/systemlinux/iso_workspace/boot/grub/grub.cfg
set default=0
set timeout=3

menuentry "systemLinux v0.2 (Source-First bbash Workspace)" {
    search --no-floppy --set=root --file /live/vmlinuz
    linux /live/vmlinuz ramdisk_size=4000000 root=/dev/ram0 rw console=tty0 systemd.show_status=true systemd.unit=multi-user.target
    initrd /live/initrd.img
}
EOF

# Build final bootable media image
grub-mkrescue -o ./systemlinux-v0.2.iso /home/torter/systemlinux/iso_workspace
sudo rm -rf /home/torter/systemlinux/iso_workspace

echo "================================================================"
echo "  SUCCESS: systemLinux v0.2 Monolithic Media Asset Completed! "
echo " Move systemlinux-v0.2.iso to Ventoy and kick off your IdeaPad! "
echo "================================================================"
