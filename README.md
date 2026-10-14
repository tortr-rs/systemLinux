
## if you wanna support me please donate here [![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/L6N725GI1V)


<p align="center">
  <img src="assets/logo.png" alt="systemLinux logo: a golden wheat ear on a dark green circle" width="160">
</p>

# systemLinux 0.2.2

A minimal x86_64 GNU/Linux distribution built on a custom monolithic kernel, dinit, and a
GNU userland (GNU bash 5.3 is `/bin/bash` and `/bin/sh`, GNU coreutils, tar, sed, gawk, findutils; the `bbash` fork stays
installed as its own command). The live ISO is **minimal installer media only**: the kernel plus the
bare minimum needed to boot and run `systemlinux-install` (dinit, NetworkManager for a network
install, disk/boot tools). No desktop, daemons, firmware bundles, docs, man pages or locale packs.
It boots like any live ISO (a compressed `rootfs.squashfs` on the ISO with a RAM layer on top) and
can be installed to disk with the `systemlinux-install` command-line tool or, step by step
by hand, with the Handbook below.

Software is added with `get`, a small POSIX `sh` script that downloads a source tarball, builds it
and installs it:

```sh
get https://ftp.gnu.org/gnu/hello/hello-2.12.tar.gz                 # into /usr/local
get -p "$HOME/.local" https://example.org/foo-1.0.tar.xz            # into your home
get -d /tmp/stage -c "--disable-nls" https://example.org/bar-2.0.tgz # staged under DESTDIR
```

`get` runs `./configure --prefix=PREFIX` (if present), `make` and `make install`; it handles
`.tar.gz`, `.tgz`, `.tar.bz2`, `.tar.xz` and `.tar`. See `get --help`.

The live ISO deliberately has no compiler or build tools. They are **profiles** you add after installing.

Website: `website/` (plain HTML; the Handbook is `website/handbook.html`) · Download: [GitHub release `v0.2.2`](https://github.com/tortr-rs/systemLinux/releases/tag/v0.2.2)

The `v0.2.2` release currently publishes this file:

| File | Size |
|---|---:|
| [`systemLinux-0.2.2-x86_64.iso`](https://github.com/tortr-rs/systemLinux/releases/download/v0.2.2/systemLinux-0.2.2-x86_64.iso) | about 401 MiB |

The release includes a separate checksum file. After downloading both files, verify the ISO with:

```sh
sha256sum -c systemLinux-0.2.2-x86_64.iso.sha256
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
* **Packages:** `get` is the package tool: `get URL` builds a source tarball, and `get --profile NAME` installs a
  package profile (see "Package profiles"). There is no other package manager.
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

Generic workflow after installing the minimal base from the ISO:

```sh
sudo get --profile build-toolchain          # compilers + headers (downloads the profile for this image version)
sudo get --profile common-build-deps        # cmake, ninja, meson, autotools, pkgconf, ...
sudo get --profile lang-runtimes            # Perl, Python, Go, when a package needs them
validate-build-ready                      # compiles autotools, CMake and Meson test projects; prints "build-ready: yes"
```

Then install software with `get` (an offline mirror works too: `GET_PROFILE_URL=http://host/dir get --profile …`):

```sh
sudo get https://ftp.gnu.org/gnu/coreutils/coreutils-9.5.tar.xz        # autotools, a large package
get -p "$HOME/.local" https://ftp.gnu.org/gnu/hello/hello-2.12.tar.gz  # a small one, no root needed
sudo get -c "--disable-docs" https://example.org/libfoo-1.2.tar.gz     # a library, with configure options
sudo get https://sqlite.org/2024/sqlite-autoconf-3460000.tar.gz        # a library others build against
```

`get` runs `./configure` when a tarball has one; CMake and Meson projects are built by hand with the
installed tools (`cmake -S . -B build -G Ninja && cmake --build build && cmake --install build`, or
`meson setup build && meson install -C build`). A tarball with neither is built with plain `make`.

## Ports tree (`get category/name`)

`get` is now a bash script (`#!/bin/bash`) and resolves non-URL arguments from a ports tree, in the style of BSD ports / Gentoo atoms. Full URLs keep working exactly as before.

```sh
get sys-app/grub        # category/name atom
get dev-apps/cmake
get x11/kde             # meta-package: no url, only requires=
get grub                # bare name, only if exactly one category has it
get https://ftp.gnu.org/gnu/hello/hello-2.12.tar.gz   # raw URL
get --sync              # refresh the ports tree
```

The ports root is `$GET_PORTS`, else `ports/` next to the `get` script (repo checkout), else `/usr/ports`. A bare name that exists in several categories is refused with a list of candidates. The tree currently holds about 534 recipes in `sys-app`, `dev-apps`, `dev-libs`, `shells`, `net`, `x11`, `lang`, `games`, `sec` and `text`.

### Recipe format

`ports/<category>/<name>/recipe` is plain `key=value`, one per line:

| key | meaning |
| --- | --- |
| `url` | source archive (omit for a meta-package) |
| `sha256` | checksum of the archive; verified, mismatch is fatal (strongly recommended) |
| `requires` | space-separated atoms installed first |
| `build` | `configure` (default: `./configure`, `make`, `make install`), `cmake` or `meson` |
| `configure_args` | extra arguments for configure / cmake / meson |

Every recipe added in the large ports expansion (see CHANGELOG) has a verified `sha256`; the original starter recipes still lack one (add it as you verify them with `sha256sum file.tar.xz`). `tools/ports-check.sh` validates the whole tree (layout, keys, checksum format, `requires` targets, cycles); `tools/ports-check.sh --verify [ATOM...]` also downloads the sources and compares the checksums, and `--strict` makes a missing `sha256` an error. CI runs it for every change under `ports/`.

### Dependencies

`requires` entries are installed first by re-invoking `get`. Installed atoms are recorded in `$GET_DB` (default `/var/db/get/installed`) and skipped next time; cycles are detected (`GET_STACK`) and abort. Note that `get` has no file tracking or uninstall yet, and packages whose build system is not make/configure/cmake/meson (or that need patches) will not build from a plain recipe.

### Updating ports

In a git checkout run `get --sync` (or `git pull`). Otherwise set `GET_PORTS_URL` to a `ports.tar.xz` that has a `ports.tar.xz.sha256` next to it; the checksum is verified before unpacking.

### Security model

Ports are untrusted input, and `get` often runs as root. Recipes are therefore **parsed** (a fixed set of keys is read with `sed`) and never `source`d, so a recipe cannot run code. Atoms and `requires` are restricted to `[A-Za-z0-9._+/-]` with no `..`, and `build` is limited to a known list. Add `sha256` so a tampered or changed tarball is rejected.
### IF there is a ports update but no new release. Run
```sh
 get --sync
```
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
./build_iso.sh    # systemLinux-0.2.2-x86_64.iso and systemLinux-0.2.2-x86_64.iso.sha256   (or: make iso)
```

It also writes `profiles-out/profile-*.tar.xz` for the release (upload them next to the ISO; `get --profile`
downloads them from the release matching the image version). The script builds (once) the full kernel, installs `get` into `rootfs/`, builds dinit with `tools/dinit/build.sh` and links `init` to it,
fixes the D-Bus launch helper permissions, brands the image with `systemlinux-provision`, copies the
installer and its boot tools into the squashfs stage, strips the stage with
`tools/live-image/strip-live.sh`, compresses everything into `rootfs.squashfs` (zstd), builds the small
initramfs (busybox + `cryptsetup`) and masters the ISO with `grub-mkrescue`.

CI (`.github/workflows/build-iso.yml`) runs the same script and uploads the ISO, profiles and `SHA256SUMS`
as artifacts.

### Cutting a release

1. Make sure `VERSION` and `CHANGELOG.md` are right on `main`.
2. Tag and push: `git tag v0.2.2 && git push origin v0.2.2` (`v0.2` also triggers it; `get --profile` maps
   `VERSION` 0.2.2 to the `v0.2.2` release, so prefer `v0.2.2`).
3. `.github/workflows/release.yml` builds the ISO and creates the GitHub Release with the ISO, profiles,
   `SHA256SUMS` and the changelog entry as notes (it verifies the checksums first). The website links point at
   `releases/download/v0.2.2/`.

The full ISO build needs a real Linux host with sudo, ~30 GB of disk and the tools listed above
(xorriso, mtools, pahole, ...); it is not verified in the restricted agent sandbox, so run `./build_iso.sh`
locally or via the `Build ISO` workflow (`workflow_dispatch`) before pushing the tag.

## Installing to disk

1. Write the ISO to a USB stick (`dd if=systemLinux-0.2.2-x86_64.iso of=/dev/sdX bs=4M status=progress conv=fsync`,
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
