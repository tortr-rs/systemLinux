#!/usr/bin/env python3
"""Extract the downloaded Debian XFCE closure and build an overlay tree
(ov3/) that never overwrites anything already present in the Gentoo rootfs."""
import os, shutil, subprocess, sys, glob
HOME = os.environ['WORK']
ROOTFS = os.environ['ROOTFS']
STAGE, OV = HOME + '/stage', HOME + '/ov3'
shutil.rmtree(STAGE, ignore_errors=True); shutil.rmtree(OV, ignore_errors=True)
os.makedirs(STAGE); os.makedirs(OV)
for deb in sorted(glob.glob(HOME + '/debs/*.deb')):
    subprocess.run(['dpkg-deb', '-x', deb, STAGE], check=True)

# usr-merge mapping (Gentoo: /bin,/sbin,/lib -> usr/..., usr/sbin -> usr/bin)
def target(rel):
    for src, dst in (('bin/', 'usr/bin/'), ('sbin/', 'usr/bin/'), ('usr/sbin/', 'usr/bin/'), ('lib/', 'usr/lib/')):
        if rel.startswith(src):
            return dst + rel[len(src):]
    return rel
SKIP_PREFIX = ('usr/share/doc/', 'usr/share/man/', 'usr/share/info/', 'usr/share/lintian/',
               'usr/share/locale/', 'usr/share/bug/', 'usr/share/menu/', 'usr/share/gdb/',
               'var/lib/dpkg/', 'usr/share/bash-completion/', 'usr/share/pixmaps/debian')
copied = skipped = 0
for dp, dns, fns in os.walk(STAGE):
    for name in fns + [d for d in dns if os.path.islink(os.path.join(dp, d))]:
        src = os.path.join(dp, name)
        rel = os.path.relpath(src, STAGE)
        rel2 = target(rel)
        if rel2.startswith(SKIP_PREFIX) or rel2.startswith('usr/share/doc'):
            continue
        dst = os.path.join(OV, rel2)
        if os.path.lexists(os.path.join(ROOTFS, rel2)) or os.path.lexists(dst):
            skipped += 1; continue
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if os.path.islink(src):
            os.symlink(os.readlink(src), dst)
        else:
            shutil.copy2(src, dst)
        copied += 1
for junk in ('usr/lib/i386-linux-gnu','usr/lib32','usr/lib/cdebconf','usr/lib/systemd','usr/lib/x86_64-linux-gnu/systemd','usr/lib/aspell/i386-linux-gnu'):
    shutil.rmtree(OV + '/' + junk, ignore_errors=True)
print('copied', copied, 'skipped (already in rootfs)', skipped)

# expose top-level multiarch shared libs to the default loader path (/usr/lib64)
ma = OV + '/usr/lib/x86_64-linux-gnu'
n = 0
if os.path.isdir(ma):
    os.makedirs(OV + '/usr/lib64', exist_ok=True)
    for f in sorted(os.listdir(ma)):
        if '.so' not in f: continue
        if os.path.lexists(ROOTFS + '/usr/lib64/' + f) or os.path.lexists(ROOTFS + '/lib64/' + f): continue
        dst = OV + '/usr/lib64/' + f
        if not os.path.lexists(dst):
            os.symlink('../lib/x86_64-linux-gnu/' + f, dst); n += 1
# Gentoo's cairo is built without X11; the Debian GTK stack needs the xlib backend
for lib in ('libcairo.so.2', 'libcairo-gobject.so.2', 'libcairo-script-interpreter.so.2'):
    dst = OV + '/usr/lib64/' + lib
    if os.path.exists(OV + '/usr/lib/x86_64-linux-gnu/' + lib):
        if os.path.lexists(dst): os.remove(dst)
        os.makedirs(OV + '/usr/lib64', exist_ok=True)
        os.symlink('../lib/x86_64-linux-gnu/' + lib, dst); n += 1
# LIB_OVERRIDE=1 (GNOME): the Debian GTK/GNOME stack must load its own libraries, not same-named ones
# from the base that were built without X11/Wayland/GL features. Every top-level Debian library that
# none of the base system's own programs needs is pointed at Debian's copy; libraries the base's boot,
# network, login and installer tools use keep the base's (newer) version.
if os.environ.get('LIB_OVERRIDE') == '1' and os.path.isdir(ma):
    import subprocess as sp
    libdirs = [ROOTFS + '/usr/lib64', ROOTFS + '/lib64', ROOTFS + '/usr/lib/gcc/x86_64-pc-linux-gnu/15',
               ROOTFS + '/usr/lib/systemd', ROOTFS + '/lib/systemd']
    def find_lib(name):
        for d in libdirs:
            p = os.path.join(d, name)
            if os.path.exists(p): return os.path.realpath(p)
        return None
    def needed(path):
        out = sp.run(['readelf', '-d', path], capture_output=True, text=True).stdout
        return [l.split('[')[1].rstrip(']') for l in out.splitlines() if 'NEEDED' in l]
    essential_bins = ('systemL bash sh login agetty runuser useradd usermod userdel groupadd chpasswd mount umount blkid lsblk '
                      'sfdisk wipefs mkfs.ext4 mke2fs mkfs.fat grub-install grub-probe efibootmgr NetworkManager nmcli dbus-daemon '
                      'dbus-launch dbus-run-session dbus-send udevadm ls cp mv rm cat find xargs sed awk gawk grep tar gzip xz less nano '
                      'ps top free sudo wpa_supplicant ip ping sync sleep tr sort date env id dd chown chmod ln mkdir tail head cut '
                      'goget kmod loadkeys setxkbmap').split()
    seen, todo = set(), []
    for b in essential_bins:
        for d in ('usr/bin', 'usr/sbin', 'bin', 'sbin'):
            p = os.path.join(ROOTFS, d, b)
            if os.path.isfile(p):
                todo.append(os.path.realpath(p)); break
    for extra in ('lib/systemd/systemd-udevd', 'usr/lib/systemd/systemd-udevd'):
        p = os.path.join(ROOTFS, extra)
        if os.path.isfile(p): todo.append(p)
    done = set()
    while todo:
        p = todo.pop()
        if p in done: continue
        done.add(p)
        try:
            if open(p, 'rb').read(4) != b'\x7fELF': continue
        except OSError:
            continue
        for lib in needed(p):
            seen.add(lib)
            q = find_lib(lib)
            if q:
                seen.add(os.path.basename(q))   # the versioned file behind the soname must stay the base's too
                todo.append(q)
    keep = forced = 0
    os.makedirs(OV + '/usr/lib64', exist_ok=True)
    for f in sorted(os.listdir(ma)):
        if '.so' not in f:
            continue
        if f in seen:
            keep += 1
            continue
        if not os.path.exists(os.path.join(ma, f)):
            continue
        if not os.path.lexists(ROOTFS + '/usr/lib64/' + f) and not os.path.lexists(ROOTFS + '/lib64/' + f):
            continue   # the base has none: the plain symlink above already covers it
        dst = OV + '/usr/lib64/' + f
        if os.path.lexists(dst): os.remove(dst)
        os.symlink('../lib/x86_64-linux-gnu/' + f, dst); forced += 1
    print('LIB_OVERRIDE: base keeps', keep, 'shared libs its own programs need; Debian forced for', forced)
print('lib64 symlinks', n)

# prune bulk that a live XFCE session never uses (spell-check dictionaries, TeX, perl/python libs)
for junk in ('usr/share/hunspell', 'usr/share/hunspell-bdic', 'usr/share/ispell', 'usr/lib/ispell',
             'usr/share/aspell', 'usr/lib/aspell', 'usr/share/texmf', 'usr/share/perl',
             'usr/share/dict', 'usr/share/enchant-2/hunspell', 'usr/lib/python3', 'usr/lib/python3.13', 'usr/share/python3',
             # os-prober makes Calamares' partitioner wait (up to 5 minutes) while it mounts and scans disks
             'usr/lib/os-probes', 'usr/lib/linux-boot-probes', 'usr/share/os-prober'):
    shutil.rmtree(OV + '/' + junk, ignore_errors=True)
for f in ('usr/bin/os-prober', 'usr/bin/linux-boot-prober', 'usr/bin/aspell', 'usr/bin/aspell-import', 'usr/bin/word-list-compress', 'usr/bin/preunzip', 'usr/bin/prezip', 'usr/bin/prezip-bin'):
    try: os.remove(OV + '/' + f)
    except FileNotFoundError: pass
# drop dangling symlinks left by the pruning
for dp, dns, fns in os.walk(OV):
    for n in fns:
        p = os.path.join(dp, n)
        if os.path.islink(p) and not os.path.exists(p) and os.readlink(p).startswith('..'):
            os.remove(p)
