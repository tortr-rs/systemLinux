
## if you wanna support me please donate here [![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/L6N725GI1V)


<p align="center">
  <img src="assets/logo.png" alt="systemLinux logo: a golden wheat ear on a dark green circle" width="160">
</p>

# systemLinux 0.2.5

A small source-based x86_64 GNU/Linux distribution: **dinit** as init (no systemd anywhere, eudev for devices),
Ubuntu's newest generic kernel with its full module tree, and a GNU userland on glibc (GNU bash 5.3 is `/bin/bash`
and `/bin/sh`, coreutils, tar, sed, gawk, findutils). The live ISO boots in UEFI and legacy BIOS mode and installs
with `systemlinux-install` or step by step with the Handbook. It ships the build tools, so software is built from
source with `get` and the ports tree of over a thousand recipes.

**New in 0.2.5** (see `CHANGELOG.md`):
* **Desktop sessions without elogind:** your runtime directory is created at login, and a per-user dinit starts the
  session D-Bus, PipeWire and WirePlumber (`exec dinit` in your sway or i3 config).
* **`linux-firmware`:** kernel.org's firmware for Wi-Fi cards, GPUs and Bluetooth, one `get install` away.

## Mascot

<img src="assets/tux/tux.svg" alt="Tux, the Linux penguin" width="110" align="right">

systemLinux's mascot is **Tux**, the Linux penguin; `fastfetch` greets you with him. Tux was drawn by
[Larry Ewing](https://isc.tamu.edu/~lewing/linux/) (lewing@isc.tamu.edu) with [The GIMP](https://www.gimp.org/); the
vector version is by Simon Budig and the SVG used here was cleaned up by Garrett LeSage. Full credits and the
copyright notice that comes with the drawing: [`assets/tux/COPYRIGHT`](assets/tux/COPYRIGHT). (The wheat ear above is
the systemLinux logo.)

Software is added with `get`, the package tool. It builds from source and keeps track of what it installed:

```sh
get install fastfetch      # builds fastfetch and every dependency it needs, in order
get remove fastfetch       # deletes exactly the files fastfetch installed
get autoremove             # removes dependencies nothing needs any more
get list                   # installed packages (* = installed on request)
get search fetch           # find packages in the ports tree
get info fastfetch         # recipe, dependencies, status
get sync                   # update the ports tree from the latest release
get install https://example.org/foo-1.0.tar.gz   # a tarball without a recipe
```

No prefixes or flags: packages go to `/usr` (configuration in `/etc`), like the base system. Dependencies the base
system already provides are not rebuilt, and the build system (configure, autotools, CMake, Meson or make) is detected automatically.
`get remove` refuses while another installed package still needs the package (`-f` overrides).

The ISO ships the build tools a source-based system needs: gcc/g++, make, binutils, cmake, meson, ninja, autotools, pkg-config, perl and python. The ports tree is in `/usr/ports`; `get sync` updates it from the latest release.

Website: `website/` (plain HTML; the Handbook is `website/handbook.html`) · Download: [GitHub release `v0.2.5`](https://github.com/tortr-rs/systemLinux/releases/tag/v0.2.5)

The `v0.2.5` release publishes the ISO, its checksum and the ports tree:

| File | |
|---|---|
| [`systemLinux-0.2.5-x86_64.iso`](https://github.com/tortr-rs/systemLinux/releases/download/v0.2.5/systemLinux-0.2.5-x86_64.iso) | the live and installer ISO |
| [`systemLinux-0.2.5-x86_64.iso.sha256`](https://github.com/tortr-rs/systemLinux/releases/download/v0.2.5/systemLinux-0.2.5-x86_64.iso.sha256) | its checksum |
| [`ports.tar.xz`](https://github.com/tortr-rs/systemLinux/releases/download/v0.2.5/ports.tar.xz) | the ports tree (`get sync`) |

The release includes a separate checksum file. After downloading both files, verify the ISO with:

```sh
sha256sum -c systemLinux-0.2.5-x86_64.iso.sha256
```

See `ROADMAP.md` for what's still deliberately not done (NVIDIA proprietary, Secure Boot, etc.).

Boots in **UEFI mode and in legacy BIOS mode**: the ISO is a hybrid image (GRUB `i386-pc` for BIOS, GRUB
`x86_64-efi` for UEFI; see `docs/BIOS.md`). Each ISO has four GRUB entries: normal, *copy to RAM* (loads the
whole system into memory so the stick can be removed), *serial console* (kernel and init messages on `ttyS0`,
used by the CI smoke test) and *debug shell* (stops just before the real system starts).

## System specifications

* **Kernel:** the newest Ubuntu `linux-image-generic` (currently 7.3.0 from Ubuntu 26.10), downloaded from the Ubuntu
  archive and checksum-verified at build time by `tools/ubuntu-kernel/fetch.sh` (pin a series with
  `UBUNTU_SERIES=...`). Its full module tree ships in the image. No firmware is bundled. The old custom monolithic
  configs (`kernel_7.2.6*.config`, `tools/kernel-full/`) are kept for reference.
* **Live boot:** a small busybox initramfs (`tools/live-image/`) finds the medium
  (also inside an ISO file on a Ventoy stick), mounts `/live/rootfs.squashfs`, adds a
  tmpfs overlay and switches to dinit. It can also unlock a LUKS-encrypted installed
  system (see "Installing to disk").
* **Shell:** GNU bash 5.3, built static by `tools/gnu-bash/build.sh` and installed as
  `/bin/bash` and `/bin/sh`. BSD tar (`bsdtar`) and friends are not installed: GNU tar is the tar.
* **Init:** [dinit](https://github.com/davmac314/dinit) 0.20.0 (PID 1; built by `tools/dinit/build.sh`). The base
  image's services are dinit service files in `/etc/dinit.d/` — see "Services" below and `docs/DINIT.md`.
  systemd is **removed completely**: no service manager, journal, logind, `systemctl` or systemd-udevd. The device
  manager is eudev (`tools/eudev/build.sh`), and `libsystemd.so.0` is a no-op stub (`tools/libsystemd-stub`) for the
  prebuilt programs still linked to it.
* **Base:** a glibc userland with GNU bash, coreutils, tar, sed and gawk, plus the C toolchain `get`
  needs. Portage and the Gentoo tree are gone; `tools/live-image/strip-live.sh` removes docs, man pages,
  translations, the Go toolchain and other bloat from the image.
* **Networking:** NetworkManager (`NetworkManager.service`), only so the installer and `get` can fetch.
* **Installer:** `systemlinux-install`, an interactive terminal tool (no GUI) — erase a
  whole disk, or install onto an existing partition you already freed up yourself (the safe
  way to dual-boot: no automatic resizing). Optional LUKS full-disk encryption. The
  Handbook documents the same steps by hand, for anyone who'd rather not trust a script (or
  can't run one).
* **Packages:** `get` is the package tool: `get install NAME` builds a port and its dependencies, `get remove NAME`
  uninstalls it, and `get profile NAME` unpacks a prebuilt package profile (see "Package profiles").
* **Boot/disk tools:** GRUB (`i386-pc` and `x86_64-efi`), `efibootmgr`, `dosfstools`, util-linux, e2fsprogs,
  `cryptsetup` (for LUKS). `build_iso.sh` copies these from the build host (with their libraries).

## Package profiles

Profiles are the post-install way to get a full build environment without bloating the live media. Each
manifest in `profiles/*.list` names the paths of one group; `tools/profiles/profiles.sh` strips those groups out
of the live image and publishes them as `profile-NAME.tar.xz` (+ `.sha256`, `.requires`) beside the ISO.

| Profile | Contents | Requires |
|---|---|---|
| `base-system` | sudo, pager/editors, zoneinfo, terminfo (stays in the base image) | |
| `network-runtime` | curl, wget, tar, xz, bzip2, CA certificates (stays in the base image, `get` needs them) | base-system |
| `build-toolchain` | gcc/g++, binutils, make, patch, glibc headers, crt files and static libs | base-system |
| `common-build-deps` | cmake, ninja, meson, pkgconf, autoconf/automake/libtool/m4, bison, flex, gettext, texinfo, `.pc`/cmake data | build-toolchain |
| `lang-runtimes` | Perl, Python, Go | common-build-deps |
| `desktop-runtime` | optional: fonts, icons, themes, mime/X11 data | network-runtime |

Rust is not part of the image yet; install it after `build-toolchain` with its own bootstrap
(`curl -fsSL https://sh.rustup.rs | sh`) or build it from a source tarball with `get`.

Everything needed to build is already in the ISO (gcc/g++, make, binutils, cmake, meson, ninja, autotools,
pkg-config, perl, python), so `get install NAME` works straight away. `validate-build-ready` compiles
autotools, CMake and Meson test projects and prints "build-ready: yes".

## Ports tree

`get` takes packages from a ports tree, in the style of BSD ports / Gentoo atoms:

```sh
get install sys-app/grub    # category/name atom
get install fastfetch       # bare name, when exactly one category has it
get install x11/kde         # meta-package: no url, only requires=
get sync                    # update the ports tree
```

The ports root is `$GET_PORTS`, else `ports/` next to the `get` script (repo checkout), else `/usr/ports`. The tree holds about 870 recipes.

### Recipe format

`ports/<category>/<name>/recipe` is plain `key=value`, one per line. **How to write a port: [docs/PACKAGING.md](docs/PACKAGING.md).**

| key | meaning |
| --- | --- |
| `version` | the package version, shown by `get list` and `get info` |
| `description` | one line, shown and searched by `get search` |
| `url` | source archive (omit for a meta-package) |
| `sha256` | checksum of the archive; verified, mismatch is fatal |
| `build` | `configure`, `autotools` (runs `autoreconf` first), `cmake`, `meson`, `make`, `python`, `cargo`, `go`, `perl`, `fonts` or `script`; detected when omitted |
| `configure_args` | extra arguments for configure / cmake / meson / pip / cargo / go / build.sh |
| `make_args` | extra arguments for `make`; for `go`, the packages to build (default `./...`) |
| `requires` | space-separated atoms installed first |
| `check` | `pkgconfig:NAME`, `cmd:NAME`, `file:/PATH` or `python:MODULE`: how to tell the system already has it |
| `srcdir` | build in this subdirectory of the source tree |

Optional files next to the recipe:

| file | meaning |
| --- | --- |
| `patches/` | every `*.patch` is applied with `patch -p1`, in name order, before building |
| `dinit/` | dinit service files, installed to `/etc/dinit.d` (then `dinitctl enable NAME`) |
| `files/` | extra files copied into place relative to `/`, e.g. `files/etc/foo.conf` |
| `build.sh` | the build itself, for `build=script` (installs into `$DESTDIR$PREFIX`) |

Service files and extra files are recorded like everything else, so `get remove` deletes them too.

Every recipe added in the large ports expansion (see CHANGELOG) has a verified `sha256`; the original starter recipes still lack one (add it as you verify them with `sha256sum file.tar.xz`). `tools/ports-check.sh` validates the whole tree (layout, keys, checksum format, `requires` targets, cycles); `tools/ports-check.sh --verify [ATOM...]` also downloads the sources and compares the checksums, and `--strict` makes a missing `sha256` an error. CI runs it for every change under `ports/`.

### Dependencies and uninstalling

`requires` entries are built first, in dependency order; cycles abort. Packages install into `/usr` like the base
system: there is one set of files, not a second copy under `/usr/local`. The image records its own packages in get's
database as `base/NAME` with their files (`tools/live-image/base-packages.sh`), so get knows who owns every file:

* a dependency the base system already provides is not rebuilt (a recipe's `check` can say what to look for);
* installing never overwrites a file another package owns, the base system's included (`-f` overrides), except that
  a port **replaces the base package with the same name** in place (when the base copy lacks a feature, e.g. cairo
  without X11). Such a port is not removed without `-f`;
* configuration in `/etc` that already exists is kept; the new version is installed as `FILE.get-new`.

Every package is staged with `DESTDIR` and each installed file is recorded in `/var/db/get/pkgs/<atom>/files`, so
`get remove` deletes exactly those files and `get files NAME` lists them. Packages installed only as dependencies are
removed by `get autoremove` once nothing needs them.

### Updating ports

`get sync` downloads `ports.tar.xz` from the latest release (verified against its `.sha256`) and replaces
`/usr/ports`; `GET_PORTS_URL` points it elsewhere. In a git checkout, use `git pull`.

### Security model

`get` often runs as root. Recipes are **parsed** (a fixed set of keys is read with `sed`) and never `source`d, so a recipe file itself cannot run code. Building a port does run code: the upstream build system, and a port's `patches/` and `build.sh`, so the ports tree is trusted like the sources it builds (review those files in pull requests). Atoms and `requires` are restricted to `[A-Za-z0-9._+/-]` with no `..`, and `build` is limited to a known list. Add `sha256` so a tampered or changed tarball is rejected.
## Services

dinit starts everything (as root):

```sh
dinitctl list                       # what is running
dinitctl status <service>
dinitctl start|stop|restart <service>
dinitctl enable|disable <service>   # add/remove it from the boot target (/etc/dinit.d/boot.d)
reboot | poweroff | halt | shutdown # dinit's own shutdown tools
```

The services are the files in `/etc/dinit.d/`: `boot` (internal target), `early-filesystems`, `udevd`, `udev-trigger`,
`mount-fstab`, `system-identity`, `zram`, `dbus-prepare`, `dbus`, `NetworkManager`, `network` (internal),
`getty-tty1`, and on installed systems `ssh-keygen`. Add your own file there and `dinitctl enable` it. `docs/DINIT.md`
explains the types and dependencies used and how the old systemd units map to them. There is no journal: dinit logs
to the console (`/dev/console`); add `-l /var/log/dinit.log` to its command line if you want a file.

The live ISO logs root in on tty1 automatically; an installed system asks for a login. Add
`console=ttyS0` to the kernel command line for a login prompt on the first serial port, and
use the *debug* GRUB entry (or drop `quiet`) to see the boot messages.

## Building the ISO

Run on any Linux host with `grub` (both the `i386-pc` and `x86_64-efi` platform files), `xorriso`, `mtools`, `squashfs-tools`, `cpio`, `busybox`,
`cryptsetup`, `efibootmgr`, `dosfstools`, `g++` and `curl` (for dinit) on `PATH` (install them with your own package manager;
see the message `build_iso.sh` prints if something is missing). The installer's boot tools are
copied from the host into the image.

```sh
./build_iso.sh    # systemLinux-0.2.5-x86_64.iso and systemLinux-0.2.5-x86_64.iso.sha256   (or: make iso)
```

It also writes `profiles-out/profile-*.tar.xz` for the release (upload them next to the ISO; `get profile`
downloads them from the release matching the image version). The script builds (once) the full kernel, installs `get` into `rootfs/`, builds dinit with `tools/dinit/build.sh` and links `init` to it,
fixes the D-Bus launch helper permissions, brands the image with `systemlinux-provision`, copies the
installer and its boot tools into the squashfs stage, strips the stage with
`tools/live-image/strip-live.sh`, compresses everything into `rootfs.squashfs` (zstd), builds the small
initramfs (busybox + `cryptsetup`) and masters the ISO with `grub-mkrescue`.

CI (`.github/workflows/build-iso.yml`) runs the same script and uploads the ISO, profiles and `SHA256SUMS`
as artifacts.

### Cutting a release

1. Make sure `VERSION` and `CHANGELOG.md` are right on `main`.
2. Tag and push: `git tag v0.2.5 && git push origin v0.2.5` (`v0.2` also triggers it; `get profile` maps
   `VERSION` 0.2.5 to the `v0.2.5` release, so prefer `v0.2.5`).
3. `.github/workflows/release.yml` builds the ISO and creates the GitHub Release with the ISO, profiles,
   `SHA256SUMS` and the changelog entry as notes (it verifies the checksums first). The website links point at
   `releases/download/v0.2.5/`.

The full ISO build needs a real Linux host with sudo, ~30 GB of disk and the tools listed above
(xorriso, mtools, pahole, ...); it is not verified in the restricted agent sandbox, so run `./build_iso.sh`
locally or via the `Build ISO` workflow (`workflow_dispatch`) before pushing the tag.

## Installing to disk

1. Write the ISO to a USB stick (`dd if=systemLinux-0.2.5-x86_64.iso of=/dev/sdX bs=4M status=progress conv=fsync`,
   or copy it onto a Ventoy stick) and boot it in UEFI or legacy BIOS mode.
2. At the live console, run `sudo systemlinux-install` and answer its prompts (disk or
   existing partition, computer name, your account, timezone, keymap, optional LUKS
   encryption). Or follow the fully manual steps in the Handbook on the website if you'd
   rather not run a script. Either way: erasing a whole disk is one option; installing onto
   an existing partition you've already freed up yourself (shrink Windows or another Linux
   first, with their own tools) is the other — there is no automatic resizing.
3. The disk gets a 512 MB EFI partition and one ext4 (optionally LUKS-encrypted) partition
   holding the system images, GRUB and your files (`/persist`). Images live under
   `/boot/images/<version>/` and are listed in the GRUB menu.

The full guide, including troubleshooting and recovery, is the Handbook on the website.

## Known limitations

* The live system keeps your changes only in RAM: they are lost on reboot until installed to disk.
* BIOS boot of a `--partition` install needs a disk GRUB can embed into: an MBR disk, or a GPT disk that has a
  BIOS boot partition (a `--disk` install creates one). See `docs/BIOS.md`.
* `systemlinux-install` erases a whole disk or a partition you name; there is no automatic
  partition resizing. Shrink an existing Windows or Linux partition yourself first if you
  want to dual-boot.
* The kernel includes Intel, AMD and the open NVIDIA (nouveau) graphics drivers, but not
  NVIDIA's proprietary driver — there's no packaging path for it (no proprietary blobs are
  bundled), so a driver whose firmware is not in the bundled set will not start.
* **Secure Boot is not supported.** The kernel is structurally ready for it (module
  signing, EFI stub, lockdown LSM are all enabled), but there is no shim/MOK signing
  pipeline in this repo yet — Secure Boot must be turned off in firmware to boot this ISO.
* Only `C.UTF-8` is available: locale packs are deliberately left out of the minimal image.
* A week of daily use on real hardware, and real hardware validation of suspend/resume,
  lid/power keys and battery/brightness, hasn't happened yet — see `ROADMAP.md`.

## Repository layout

```text
├── get                   # POSIX sh: download a source tarball, build and install it
├── profiles/             # package profile manifests (build-toolchain, common-build-deps, ...)
├── tools/profiles/       # profiles.sh: pack profiles for release / strip them from the live ISO
├── tools/validate-build-ready.sh # installed as validate-build-ready; checks an installed system can build autotools/CMake/Meson projects
├── tools/installer/      # systemlinux-install, systemlinux-grubcfg, systemlinux-post, systemlinux-provision, preset
├── tools/overlay-common/ # shared helpers (copy-bin.sh, strip-gentoo.sh)
├── tools/kernel-full/    # builds the full-driver kernel (extra-config.txt applied to the base config)
├── tools/live-image/     # live initramfs (busybox + cryptsetup + init script) and strip-live.sh
├── website/index.html    # project site + Handbook
├── build_iso.sh           # ISO build pipeline
├── kernel_7.2.6.config     # original kernel configuration
├── kernel_7.2.6-full.config # full-driver kernel configuration
└── rootfs/               # distribution staging filesystem
```
