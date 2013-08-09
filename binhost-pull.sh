#!/bin/sh

rsync --bwlimit=80 -avP --chmod=a+rX --no-owner --no-group lore.xmw.de:/srv/gentoo/genberry/experimental/ /var/cache/packages/
