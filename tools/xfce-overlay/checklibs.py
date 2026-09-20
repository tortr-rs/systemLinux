import os, subprocess, sys
OV=os.environ['WORK']+'/ov3'; R=os.environ['ROOTFS']
have=set()
for d in (OV+'/usr/lib/x86_64-linux-gnu', OV+'/usr/lib64', R+'/usr/lib64', R+'/lib64', R+'/usr/lib', OV+'/usr/lib'):
    if os.path.isdir(d):
        for f in os.listdir(d): have.add(f)
missing={}
for dp,dn,fn in os.walk(OV):
    for f in fn:
        p=os.path.join(dp,f)
        if os.path.islink(p): continue
        try:
            with open(p,'rb') as fh:
                if fh.read(4)!=b'\x7fELF': continue
        except Exception: continue
        out=subprocess.run(['readelf','-d',p],capture_output=True,text=True).stdout
        for l in out.splitlines():
            if 'NEEDED' in l:
                lib=l.split('[')[1].rstrip(']')
                if lib not in have: missing.setdefault(lib,set()).add(os.path.relpath(p,OV))
for lib,users in sorted(missing.items()):
    print(lib, '<-', sorted(users)[:2], len(users))
print('missing libs:',len(missing))
