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
    
    cmd = ['emerge', '-v1K', '=%s' % cpv]
    print(cmd)
    subprocess.Popen(cmd).wait()
    

