#!/usr/bin/env bash
# Michael Weber xmw at gentoo dot org 2013
# vim: tabstop=4

RUN_QEMU=0

usage() {
	[ -n "${@:2}" ] && echo "${@:2}"
	echo "Usage: $(basename ${0}) [-v] [-h|--help] <image> [mountpoint]"
	[ -n "${1}" ] && exit ${1}
}

while true ; do
	case "${1}" in
		-h|--help)
			usage 0
			;;
		-v|--verbose)
			set +x
			shift
			;;
#		-r|--run)
#			RUN_QEMU=1
#			shift
#			;;
		*)
			break
			;;
	esac
done

if [ "${RUN_QEMU}" -eq 1 ] ; then
	if ! qemu-system-arm -version || \
		! qemu-system-arm -cpu ? | grep arm1176 >/dev/null ; then
		quit 1 "Please install qemu-system-arm with arm1176 support." 
	fi
fi

IMAGE=${1}
MOUNTPOINT=${2}
[ -z "${IMAGE}" ] && usage 1 "specify image file"
[ -n "${3}" ] && usage 1 "too many arguments"
if [ -n "${MOUNTPOINT}" ] ; then
	[ -d "${MOUNTPOINT}" ] || usage 1 "mountpoint is not a directory"
	if mountpoint -q "${MOUNTPOINT}" ; then
		usage 1 "${MOUNTPOINT} already mounted"
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

if [ "${RUN_QEMU}" -eq 1 ] ; then
	mount "${LOOP}"p1 "${MOUNTPOINT}"
	pushd "${MOUNTPOINT}"
	echo "fix me"
	popd >/dev/null
else 
	mount "${LOOP}"p3 "${MOUNTPOINT}"
	mount "${LOOP}"p1 "${MOUNTPOINT}"/boot
	[ -e "${MOUNTPOINT}"/var/cache/portage/latest.squashfs ] && \
		mount "${MOUNTPOINT}"/var/cache/portage/latest.squashfs \
			"${MOUNTPOINT}"/usr/portage
	pushd "${MOUNTPOINT}"
	$SHELL
	popd >/dev/null

	while mountpoint "${MOUNTPOINT}"/usr/portage >/dev/null ; do
		umount "${MOUNTPOINT}"/usr/portage || sleep 1
	done
	while mountpoint "${MOUNTPOINT}"/boot >/dev/null ; do
		umount "${MOUNTPOINT}"/boot || sleep 1
	done
fi

while mountpoint "${MOUNTPOINT}" >/dev/null ; do
	umount "${MOUNTPOINT}" || sleep 1
done

while losetup -a | grep "${IMAGE}" | grep "${LOOP}" >/dev/null ; do
	losetup -d "${LOOP}" || sleep 1
done
