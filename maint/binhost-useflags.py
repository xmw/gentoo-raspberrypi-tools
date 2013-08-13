#!/usr/bin/python
# vim: expandtab tabstop=4

from portage.emaint.modules.binhost.binhost import BinhostHandler
import sys

sys.stderr.write('Loading ...')
sys.stderr.flush()
bh = BinhostHandler()
sys.stderr.write(' done')
sys.stderr.flush()

lines = []
for i in bh._pkgindex.packages:
    iuses = i.get('IUSE', '').split()
    if not iuses:
        continue
    for j in range(len(iuses)):
        if iuses[j][0] in ('+', '-'):
            iuses[j] = iuses[j][1:]
    uses = i.get('USE', '').split()
    flags = map(lambda iuse: (not iuse in uses and '-' or '' ) + iuse, iuses)
    lines.append((i.get('BUILD_TIME'), '=%s %s' % (i.get('CPV'), ' '.join(flags))))

for bt, line in sorted(lines):
    print(line)

