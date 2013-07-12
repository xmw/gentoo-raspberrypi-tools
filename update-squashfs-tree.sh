#!/bin/bash
# copyright Michael Weber xmw at gentoo dot org 2013
# vim: tabstop=4 :

SNAPSHOT_DIR=/srv/gentoo/snapshots
SNAPSHOT_GPG_KEYID=C9189250
SQUASHFS_DIR=/srv/gentoo/genberry/snapshots

# load some fancy output
if [ -f /etc/init.d/functions.sh ] ; then
	source /etc/init.d/functions.sh
else
	ebegin() { echo -n ">>> $@" ; }
	eend() { [ ${1:-0} -eq 0 ] && echo " ok" || echo " failed" ; }
	fi
quit() {
	local ret=${1:-0}
	eend $ret
	shift
	[ -n "${@}" ] && echo "${@}"
	exit $ret
}

ERR=$( {
	gpg --list-keys "${SNAPSHOT_GPG_KEYID}" >/dev/null || \
		echo "need gpg --keyserver pgp.mit.edu --recv-keys ${GPG_KEYID}"	
	[ -d "${SNAPSHOT_DIR}" ] || echo "SNAPSHOT_DIR=${SNAPSHOT_DIR} is missing"
	[ -d "${SQUASHFS_DIR}" ] || echo "SQUASHFS_DIR=${SQUASHFS_DIR} is missing"
	mksquashfs -version >/dev/null || quit 1 "mkquashfs is missing" ; } )
[ -z "${ERR}" ] || quit 1 "${ERR}"

for src in "${SNAPSHOT_DIR}"/*.tar.xz ; do
	tgt_gz=${SQUASHFS_DIR}/$(basename "${src%.tar.xz}").gz.squashfs
	tgt_xz=${SQUASHFS_DIR}/$(basename "${src%.tar.xz}").xz.squashfs
	[ -e "${tgt_gz}" -a "${src}" -nt "${tgt_gz}" ] && rm -v "${tgt_gz}"
	[ -e "${tgt_xz}" -a "${src}" -nt "${tgt_xz}" ] && rm -v "${tgt_xz}"
	[ -e "${tgt_gz}" -a -e "${tgt_xz}" ] && continue
	ebegin "update ${src}"
	gpg --verify "${src}".gpgsig "${src}" || quit 1 "failed to verify ${src}"
	tmp=$(mktemp -d /dev/shm/portage.XXXXXX)
	[ -n "${tmp}" ] || quit 2 "Failed to create tempdir."
	trap 'rm -rf "${tmp}"' EXIT
	pv "${src}" | tar xJC "${tmp}" || quit 1 "tar failed"
	[ -e "${tgt_gz}" ] || \
		mksquashfs ${tmp}/portage ${tgt_gz} -comp gzip -processors 4
	[ -e "${tgt_xz}" ] || \
		mksquashfs ${tmp}/portage ${tgt_xz} -comp xz -Xbcj arm -processors 4
	rm -rf "${tmp}" EXIT
	eend
done

for src in "${SQUASHFS_DIR}"/*.gz.squashfs ; do
	echo "${src}" | grep "latest" >/dev/null && continue
	echo "$(basename "${src}")"
done | sort | tail -n 1 | tee "${SQUASHFS_DIR}"/LATEST.gz.txt
for src in "${SQUASHFS_DIR}"/*.xz.squashfs ; do
	echo "${src}" | grep "latest" >/dev/null && continue
	echo "$(basename "${src}")"
done | sort | tail -n 1 | tee "${SQUASHFS_DIR}"/LATEST.xz.txt

