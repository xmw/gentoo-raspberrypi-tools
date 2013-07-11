#!/usr/bin/env bash
# Michael Weber xmw at gentoo dot org 2013
# vim: tabstop=4


usage() {
	echo "Usage: $(basename ${0}) [-v] [-h|--help] <image> [mountpoint]"
	[ -n "${1}" ] && exit ${1}
}

while true ; do
	case "${1}" in
		-h|--help)
			usage 0
			;;
		-v)
			set +x
			shift
			;;
		*)
			break 2
			;;
	esac
done

IMAGE=${1}
MOUNTPOINT=${2}
[ -z "${IMAGE}" ] && usage 1
[ -n "${3}" ] && usage 1
if [ -n "${MOUNTPOINT}" ] ; then
	[ -d "${MOUNTPOINT}" ] || usage 1
	if mountpoint -q "${MOUNTPOINT}" ; then
		echo "${MOUNTPOINT} already mounted"
		usage 1
	fi
else
	TMP=$(mktemp -d)
	MOUNTPOINT=${TMP}
fi

set -e
LOOP=$(losetup -f)
losetup "${LOOP}" "${IMAGE}"
partx -d "${LOOP}" || true
partx -a "${LOOP}"
mount "${LOOP}"p3 "${MOUNTPOINT}"
mount "${LOOP}"p1 "${MOUNTPOINT}"/boot

pushd "${MOUNTPOINT}"
$SHELL
popd >/dev/null

while mountpoint "${MOUNTPOINT}"/boot >/dev/null ; do
	umount "${MOUNTPOINT}"/boot || sleep 1
done
while mountpoint "${MOUNTPOINT}" >/dev/null ; do
	umount "${MOUNTPOINT}" || sleep 1
done
partx -d "${LOOP}" || true
while losetup -a | grep "${IMAGE}" | grep "${LOOP}" >/dev/null ; do
	losetup -d "${LOOP}" || sleep 1
done
