import os, subprocess, sys
R = os.environ['ROOTFS']
out = sys.argv[1]; roots = sys.argv[2:]
gz = subprocess.Popen(['gzip', '-6'], stdin=subprocess.PIPE, stdout=open(out, 'wb'))
for base in roots:
    ents = []
    for dp, dns, fns in os.walk(base):
        rel = os.path.relpath(dp, base)
        for d in dns:
            p = os.path.join(dp, d)
            r = os.path.normpath(os.path.join(rel, d))
            if os.path.islink(p): ents.append(r)              # symlink to dir
            elif not os.path.lexists(os.path.join(R, r)): ents.append(r)  # new dir only
        for f in fns:
            ents.append(os.path.normpath(os.path.join(rel, f)))
    ents.sort()
    cp = subprocess.run(['cpio', '-o', '-H', 'newc', '-R', '0:0', '--quiet'], input=('\n'.join(ents) + '\n').encode(),
                        cwd=base, capture_output=True, check=True)
    gz.stdin.write(cp.stdout)
gz.stdin.close(); gz.wait()
print(out, os.path.getsize(out) // 1048576, 'MB')
