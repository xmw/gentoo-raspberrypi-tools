#!/bin/sh

rsync --bwlimit=80 -avPL --delete --chmod=a+rX --no-owner --no-group /var/cache/packages/ lore.xmw.de:/srv/gentoo/genberry/experimental/
