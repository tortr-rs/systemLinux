# systemLinux roadmap (a distribution you can daily-drive)

1.0/1.1 together mean: install it on a laptop, use it every day for browsing, mail, media, calls and
development, and update it without fear. Status is honest: done means tested (in a VM, or here,
a real rebuilt kernel and a real `goget install` against live nixpkgs), not just written. Items
that fundamentally need real hardware or real UEFI firmware to verify are marked as such and left
open, not checked off on faith.

## Done (0.4 - 0.6)
- Live console system, native CLI installer (`systemlinux-install`), persistent installs, signed
  image updates with rollback (`goget upgrade`)
- Full-driver kernel, firmware, Wi-Fi via NetworkManager
- goget as the package manager: nixpkgs binaries with full dependency-closure resolution, no host
  distro package manager involved anywhere, including at build time

## 1.1: minimal-only, no GUI installer, everyday hardware
The GNOME live edition and its GTK4 graphical installer are gone entirely — one console-only ISO,
installed with `systemlinux-install` (a terminal tool) or by hand from the Handbook. Everything
below that used to be GNOME-desktop-only now runs as plain `lenine`-supervised services instead.

- [x] power off / reboot (lenine's own, not GNOME/elogind-mediated)
- [x] audio: PipeWire + WirePlumber + PulseAudio compatibility, system-wide (reworked off the old
      GNOME-session-only autostart)
- [x] Bluetooth (bluez) — no GNOME panel, `bluetoothctl` is the console-edition's interface
- [x] time sync (chrony), power profiles (`powerprofilesctl`), Flatpak + Flathub (remote added
      automatically at install) — no GNOME Software, that was GNOME-specific and is dropped
- [x] firewall on by default (nftables, default-deny-inbound) — this needed a real kernel config
      fix (`NF_TABLES_INET/IPV4/IPV6/ARP/BRIDGE` were compiled out) and a real kernel rebuild, both
      done; not just a config file edit
- [x] LUKS full-disk encryption, in `systemlinux-install` and the manual Handbook steps, with the
      live initramfs able to unlock an encrypted installed system at boot
- [x] dual-boot / resize-free install: `systemlinux-install --partition` installs onto an existing
      partition you've already freed up yourself (GParted/Disk Management beforehand) instead of
      erasing a whole disk — deliberately *not* automatic resizing, which would be a genuinely
      risky thing to do unattended to someone's existing Windows/Linux partitions
- [x] printing (CUPS), firmware updates (fwupd)
- [x] locales (glibc-locales, `en_US.UTF-8` pre-baked, others addable), CJK fonts, fcitx5
      installed (not auto-started — no desktop session to launch it from yet; ibus was dropped —
      its prebuilt closure drags in a GTK+Python setup GUI that can't run without a desktop
      session anyway, and fcitx5 alone covers the same need much more cheaply)
- [x] a CLI update notifier: `lenine` gained a real timers.conf capability (periodic, non-daemon
      commands) for this — `goget upgrade --check` runs every 12h, visible in `lenine status`
- [x] documented recovery: a real Recovery chapter in the Handbook (GRUB older-image rollback,
      live-ISO chroot repair, `/persist` backup guidance)
- [ ] suspend/resume and lid/power keys, battery and brightness **verified on real laptops** —
      elogind (session/seat tracking, `loginctl suspend`) and kernel-level suspend support
      (`CONFIG_SUSPEND`, `CONFIG_ACPI_SLEEP`) are both in place, but nothing wires a lid-switch or
      power-button *event* to `loginctl suspend` automatically yet, and none of it has been tried
      on real hardware
- [ ] clean shutdown path **verified on real hardware** — the code path itself (unmount, remount
      read-only, sync) has existed since before 1.0; "verified on real hardware" specifically is
      still open
- [ ] NVIDIA proprietary driver, hybrid graphics — no packaging path exists (no proprietary blobs
      bundled); open nouveau is what's in the kernel today
- [ ] Secure Boot (signed shim + GRUB) — the kernel is structurally ready (module signing, EFI
      stub, lockdown LSM), but there is no shim/MOK signing pipeline in this repo. Not started,
      not half-done — genuinely nothing here yet. Needs real UEFI firmware to verify enrollment
      even once it exists.
- [ ] scanners (SANE) — not addressed at all yet
- [ ] translations of the installer/website UI itself — only the locale *mechanism* is in place;
      the actual English-only strings haven't been translated
- [x] **ISO size**: fixed. Root cause was nixpkgs' `linux-firmware` bundling firmware for
      every device that has ever existed, included *twice* (initramfs + squashfs), where the
      old Debian-based build cherry-picked ~17 relevant per-vendor packages instead. Tried
      the surgical fix first (filter to only what this kernel's drivers reference via
      `MODULE_FIRMWARE()` in the kernel source) and abandoned it: `iwlwifi` — extremely
      common Intel WiFi hardware — builds its firmware filenames entirely at runtime with
      zero literal strings in source, so that approach would have silently broken WiFi for a
      large share of real laptops. Used a categorical exclusion instead: dropped vendor
      directories that cannot run on x86_64 *at all* (Qualcomm Snapdragon/Adreno SoC
      firmware — 450 MB alone — plus other ARM/embedded-only vendors) and enterprise
      datacenter NICs outside this project's laptop/desktop target (Netronome, Mellanox).
      Real PC WiFi/BT/GPU vendors (MediaTek, Marvell, Atheros, AMD, Intel, NVIDIA) untouched.
      Final measured ISO: 1.9 GB, under GitHub's 2 GB release-asset limit with real margin —
      attached directly to the `v1.1` release, no split files, no external hosting needed.

## 1.2 and beyond
- [ ] a week of daily use on real hardware (ThinkPad, IdeaPad, a desktop) with no reinstall
- [ ] Secure Boot: build the actual signing pipeline once someone can test real enrollment
- [ ] suspend/resume wired to lid/power-key events, then validated on real hardware
- [ ] scanners, UI translations
- [ ] a real per-driver firmware trim (matching this kernel's actual driver set, not just
      whole-vendor exclusion) — safe to attempt now that there's ISO-size headroom again, no
      rush
