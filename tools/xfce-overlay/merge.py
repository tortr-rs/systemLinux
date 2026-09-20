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
print('lib64 symlinks', n)

# prune bulk that a live XFCE session never uses (spell-check dictionaries, TeX, perl/python libs)
for junk in ('usr/share/hunspell', 'usr/share/hunspell-bdic', 'usr/share/ispell', 'usr/lib/ispell',
             'usr/share/aspell', 'usr/lib/aspell', 'usr/share/texmf', 'usr/share/perl', 'usr/lib/python3',
             'usr/lib/python3.13', 'usr/share/python3', 'usr/share/dict', 'usr/share/enchant-2/hunspell'):
    shutil.rmtree(OV + '/' + junk, ignore_errors=True)
for f in ('usr/bin/aspell', 'usr/bin/aspell-import', 'usr/bin/word-list-compress', 'usr/bin/preunzip', 'usr/bin/prezip', 'usr/bin/prezip-bin'):
    try: os.remove(OV + '/' + f)
    except FileNotFoundError: pass
# drop dangling symlinks left by the pruning
for dp, dns, fns in os.walk(OV):
    for n in fns:
        p = os.path.join(dp, n)
        if os.path.islink(p) and not os.path.exists(p) and os.readlink(p).startswith('..'):
            os.remove(p)
