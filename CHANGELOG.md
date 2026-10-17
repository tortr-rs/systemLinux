# Changelog

## 0.2.5

### Added
- **Desktop sessions without elogind**: `pam_exec` creates `/run/user/UID` at login
  (`/usr/libexec/systemlinux-rundir`), `/etc/profile.d/xdg-runtime.sh` exports `XDG_RUNTIME_DIR` and
  `DBUS_SESSION_BUS_ADDRESS`, and a user-mode dinit (`exec dinit` from sway/i3) starts the services in
  `/etc/dinit.d/user/boot.d`: the session D-Bus, and PipeWire, pipewire-pulse and WirePlumber when those ports are
  installed (they now ship dinit user services).
- **`sys-app/linux-firmware`** 20260916: kernel.org's firmware release, installed zstd-compressed (951 MB).

### Changed
- New users are added to the `video`, `audio` and `input` groups (seatd, ALSA, libinput).
- PipeWire no longer starts pipewire-pulse itself (its own user service does).

## 0.2.4

### Added
- **253 Python modules** (`dev-python`): the most downloaded projects on PyPI and everything they need at run time
  (requests, httpx, rich, click, pydantic, numpy, pandas, cryptography, pillow, lxml, jinja2, ...), plus the build
  backends that projects use (poetry-core, pdm-backend, maturin, meson-python, scikit-build-core, hatch-vcs).
  Generated from PyPI: each port has the sdist's sha256 and the build backend and system libraries it needs.
- **226 Perl modules** (`dev-perl`): popular CPAN distributions (Moose, Mojolicious, DBI, DateTime, LWP,
  XML-LibXML, Template-Toolkit, Perl-Tidy, Image-ExifTool, ...) with their dependencies; modules that ship with Perl
  itself are left to the base system.
- **47 GNU packages** that were missing: a2ps, autogen, cflow, dejagnu, enscript, gnucobol, gnuchess, gnugo, inetutils,
  mailutils, mtools, recutils, xorriso, zile, GNU Hello and more.
- **11 more `-bin` ports**: the JetBrains IDEs (IntelliJ IDEA, PyCharm, WebStorm, GoLand, CLion, RustRover, Rider,
  DataGrip, PhpStorm, RubyMine) and Kdenlive.
- librsvg.

### Fixed
- **sudo and su work.** `/usr/bin/sudo` was a stub that ran the command as the calling user, and every system file
  was owned by uid 1000 with no setuid bits (git does not keep owners or special modes), so `sudo` and `su` failed
  with "operation not permitted" and `/etc/shadow` was world-readable. The image now has the real sudo 1.9.17p2,
  built in the image against its own PAM, and `tools/overlay-common/fix-perms.sh` sets root ownership, setuid bits
  and private modes before the image is packed. Existing installs need a fresh install.
- **Python ports build again.** The image has no pip, and the ISO strip removes the copy bundled with Python, so no
  `dev-python` port could build on 0.2.3. `get` now builds Python packages the way Gentoo does, with the base
  system's `gpep517` and `installer` (pip is still used where gpep517 is missing).
- **Perl modules are checked by loading them.** `check=perl:Module::Name`: the base lists some Perl modules whose files
  are not usable (they sit in the previous Perl version's folder), so ports that needed them failed at run time.
- **New `cflags=` recipe key** for extra C compiler flags, e.g. `-std=gnu17` for old C code that GCC 15's C23 default
  rejects (applies to C only, not C++).

The ports tree has 1619 recipes.

## 0.2.3

### Added
- `get` is a real package manager: `get install/remove/autoremove/list/search/info/files/sync/profile`
  (`get NAME` installs). Dependencies are resolved from the recipes' `requires`, packages the base system already
  has are not rebuilt, every installed file is recorded so `get remove` deletes exactly what was installed, and a
  package never overwrites a file another package owns.
- Recipe format: `version`, `description`, `check` (`pkgconfig:`/`cmd:`/`file:`/`python:`), `srcdir`, `make_args`;
  port folders `patches/`, `dinit/` (services), `files/` and `build.sh`. Build types: configure, autotools, cmake,
  meson, make, python, cargo, go, perl, fonts, script.
- Ports: the graphics stack and desktops: X.Org (libraries, Xorg 21.1, Xwayland, input/video drivers), Mesa with
  LLVM, Wayland, wlroots, libinput, cairo with X11, pango, fonts; i3, sway, bspwm, dwm, st, foot, xterm; seatd with
  a dinit service.
- Ports: the greetd login manager with tuigreet (dinit service), PipeWire 1.6 and WirePlumber (started together),
  swaylock, swayidle, grim, mako (with basu for sd-bus), dunst, i3lock, sxhkd, xclip, xsel, xdotool, brightnessctl,
  playerctl, pamixer, geany, nsxiv; Rust 1.99 and many popular command line tools (helix, zellij, yazi, eza,
  zoxide, bottom, delta, lazygit, gh, micro, nnn, yq, ...).
- `docs/PACKAGING.md` (and the website's Packaging page): how to write, test and submit a port.
- One package world: get installs into `/usr` and `/etc` like the base system, and the image records its own
  packages in get's database (`base/NAME`, with their files). A port can no longer shadow or silently overwrite a base
  package: it either replaces the base package of the same name in place or is refused. Existing `/etc` configuration
  is kept (the new file is installed as `.get-new`).

### Fixed
- `help2man` works (it needed `Locale::gettext`, whose compiled module did not match the image's Perl).
- Ports: duplicate `dev-libs/xcb-util` removed; the Python `mako` port is now `dev-python/python-mako`, so
  `get install mako` means the notification daemon.

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
