# systemLinux roadmap to 1.0 (a distribution you can daily-drive)

1.0 means: install it on a laptop, use it every day for browsing, mail, media, calls and development, and
update it without fear. Status is honest: done means tested in a VM, not just written.

## Done (0.4 - 0.6)
- Live GNOME desktop, native installer, persistent installs, signed image updates with rollback (`goget upgrade`)
- Full-driver kernel, firmware, Wi-Fi via NetworkManager
- goget as the package manager: Debian, Ubuntu, Arch, Gentoo binaries or Git, chosen at install

## 0.7: everyday hardware and services (in progress)
- [x] power off / reboot from GNOME through elogind
- [ ] audio: PipeWire + WirePlumber + PulseAudio compatibility started with the session
- [ ] Bluetooth (bluez) and the GNOME Bluetooth panel
- [ ] time sync (chrony), power profiles, Flatpak + Flathub, GNOME Software
- [ ] suspend/resume and lid/power keys, battery and brightness on real laptops
- [ ] clean shutdown path (unmount, sync) verified on real hardware

## 0.8: sign-in and security
- [ ] login screen, lock screen, user switching (GDM on elogind)
- [ ] LUKS full-disk encryption in the installer
- [ ] Secure Boot (signed shim + GRUB) so it installs on locked-down laptops
- [ ] firewall on by default; automatic security updates prompt

## 0.9: polish
- [ ] languages: locales and translations, input methods, CJK fonts
- [ ] printing (CUPS) and scanners, fwupd firmware updates
- [ ] graphical update notifier for `goget upgrade` and packages
- [ ] dual-boot / resize-free install next to Windows or another Linux
- [ ] NVIDIA proprietary driver option, hybrid graphics

## 1.0
- [ ] a week of daily use on real hardware (ThinkPad, IdeaPad, a desktop) with no reinstall
- [ ] documented recovery: boot menu rollback, live-ISO repair, backups
