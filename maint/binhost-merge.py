#!/usr/bin/python3
# vim: expandtab tabstop=4

from portage.emaint.modules.binhost.binhost import BinhostHandler
import os, subprocess, sys

sys.stderr.write('Loading ...')
sys.stderr.flush()
bh = BinhostHandler()
sys.stderr.write(' done')
sys.stderr.flush()

import portage
tree = portage.db[portage.root]['vartree']

missing = []
print(len(bh._pkgindex.packages))
for pkg in bh._pkgindex.packages:
    cpv = pkg.get('CPV')
    cand = tree.dbapi.match(cpv)
    if cand:
        print('found %s' % cand)
        continue
    cp = portage.getCPFromCPV(cpv)
    cand = tree.dbapi.match(cp)
    if cand:
        print('found simmilar %s' % cand)
        continue

    print('missing %s' % cpv)
    
    cmd = 'screen -S %s -X screen zsh -c "echo \\"emerge =%s\\" ; emerge -av1K \=%s ; echo \\"done\\" ; sleep 7d"\n' % (os.getenv('STY'), cpv, cpv)
    print(cmd)

    p = subprocess.Popen(['batch'], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    p.stdin.write(cmd.encode('utf-8'))
    p.stdin.close()
    print(p.stdout.read().decode('utf-8'))
    p.stdout.close()

