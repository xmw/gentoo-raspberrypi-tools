#!/bin/bash
# vim: tabstop=4
# Michael Weber xmw at gentoo dot org 2013
#
# TODO 
#	provide update mechanism for portage.squashfs -> lore.xmw.de/gentoo
#	use PORTAGE_CONFIGROOT
# ADD
#	syslog-ng, dcron, eix, vim, ntp, slocate

WORKDIR=/rpi
IMAGE=${WORKDIR}/image.raw
TARGET=${WORKDIR}/target

VERIFY_GPG=1
GPG_KEYID=C9189250

# check shells
if [ -z "${ZSH_VERSION}" -a -z "${BASH_VERSION}" ] ; then
	echo "Unsupported shell, use zsh or bash."
	exit 1
fi

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

ebegin "check environment and tools"
ERR=$( {
	[ "$(id -u)" -eq 0 ] || echo "run as root"
	[ -d "${WORKDIR}" ] || echo "WORKDIR=${WORKDIR} does not exist"
	if [ "${VERIFY_GPG:-0}" -eq 1 ] ; then
		if ! gpg --list-keys ${GPG_KEYID} >/dev/null ; then
			echo "install key ${GPG_KEYID}, try"
			echo "  gpg --keyserver pgp.mit.edu --recv-keys ${GPG_KEYID}"
		fi
		GPG=gpg
	fi
	for tool in mkdir wget openssl pv mkfs.vfat mkswap mkfs.ext4 tar losetup \
		sfdisk dd mksquashfs mountpoint emerge ${GPG} tr ; do
		which ${tool} >/dev/null || echo "missing binary: ${tool}"
	done
	if losetup -a | grep "${IMAGE}" >/dev/null ; then
		echo "The target file ${IMAGE} is set up as loopback device."
		echo "Proceeding would cause file corruption, exiting."
	fi
	if mountpoint "${TARGET}" >/dev/null ; then
		echo "The target mountpoint ${TARGET} is already mounted."
		echo "Proceeding would overshadown the filesystem,"
		echo "and is most likely due to an unfinished previous invocation."
	fi
} )
[ -n "${ERR}" ] && quit 1 "${ERR}"

set -e

ebegin "search for newer stage3 tarball"
LATEST="20130207/20130207/armv6j-hardfloat-linux-gnueabi/stage3-armv6j_hardfp-20130207.tar.bz2"
latest=$(wget -O - http://distfiles.gentoo.org/releases/arm/autobuilds/latest-stage3-armv6j_hardfp.txt 2>/dev/null | tail -n 1)
[ "${LATEST}" != "${latest}" ] && \
	quit 1  "update stage3 tarball reference to ${latest}"
eend

ebegin "fetch stage3 tarball"
mkdir -p "${WORKDIR}"/stage3
URL=http://distfiles.gentoo.org/releases/arm/autobuilds/${LATEST}
STAGE3=${WORKDIR}/stage3/$(basename "${URL}")
[ -f "${STAGE3}"          ] || wget -O "${STAGE3}"          "${URL}"
[ -f "${STAGE3}".DIGESTS  ] || wget -O "${STAGE3}".DIGESTS  "${URL}".DIGESTS
[ -f "${STAGE3}".CONTENTS ] || wget -O "${STAGE3}".CONTENTS "${URL}".CONTENTS
eend

ebegin "verify stage3 tarball"
{	cd "$(dirname "${STAGE3}")"
	for f in "$(basename "${STAGE3}")"{,.CONTENTS} ; do
		for h in MD5 SHA1 SHA512 WHIRLPOOL ; do
			echo "# ${h} HASH"
			openssl dgst -r -$(echo $h | tr '[A-Z]' '[a-z]') "${f}"
		done
	done
} | sed 's:*stage: stage:' | diff ${STAGE3}.DIGESTS -
eend

ebegin "fetch portage"
mkdir -p "${WORKDIR}"/portage
URL=http://lore.xmw.de/gentoo/snapshots/portage-20130709.tar.xz
PORTAGE=${WORKDIR}/portage/$(basename ${URL})
[ -f "${PORTAGE}"        ] || wget -O "${PORTAGE}"        "${URL}"
[ -f "${PORTAGE}".gpgsig ] || wget -O "${PORTAGE}".gpgsig "${URL}".gpgsig
eend

if [ "${VERIFY_GPG:-0}" -eq 1 ] ; then
	ebegin "verify portage gpg signature"
	gpg --verify ${PORTAGE}.gpgsig ${PORTAGE}
	eend
fi

ebegin "create blank disk image"
dd bs=1M count=2000 if=/dev/zero | pv -s 2000M > "${IMAGE}"
eend

ebegin "set up partitions"
LOOP=$(losetup -f)
losetup ${LOOP} ${IMAGE}
{ # 4194304000 / 255 / 63 / 512 -> 509
	echo ",16,0x0C,*"
	echo ",64,0x82,-"
	echo ",,,-"
} | sfdisk -D -H 255 -S 63 -C 254 ${LOOP} #509
partx -d "${LOOP}" || true
partx -a "${LOOP}"
eend


BOOT=${LOOP}p1
SWAP=${LOOP}p2
ROOT=${LOOP}p3
trap '{ 
	set -x
	mountpoint "${TARGET}"/boot && umount -v "${TARGET}"/boot
	mountpoint "${TARGET}"/usr/portage && umount -v "${TARGET}"/usr/portage
	mountpoint "${TARGET}" && umount -v "${TARGET}"
	losetup -d "${LOOP}" ; }' EXIT

ebegin "create and mount filesystems"
mkfs.ext4 -q -L root -i 4096 "${ROOT}"
mkdir -p "${TARGET}"
mount -o noatime "${ROOT}" "${TARGET}"


mkfs.vfat -n boot "${BOOT}"
mkdir -p "${TARGET}/boot"
mount "${BOOT}" ${TARGET}/boot

mkswap -L swap "${SWAP}"
eend

ebegin "unpack stage3"
pv ${STAGE3} | tar xjC ${TARGET}
eend

PORTAGE_SQ=${PORTAGE%.tar.xz}.squashfs
if ! [ -f "${PORTAGE_SQ}" -o "${PORTAGE}" -nt "${PORTAGE_SQ}" ] ; then
	ebegin "create portage squashfs"
	mkdir -p "${WORKDIR}"/tmp
	TMP=$(mktemp -d "${WORKDIR}"/tmp/squash.XXXXX)
	pv "${PORTAGE}" | tar xJC "${TMP}"
	mksquashfs -noappend "${TMP}"/portage "${PORTAGE_SQ}"
	rm -r "${TMP}"
	eend
fi

ebegin "copy portage squashfs"
PORTAGE_SQ_TGT=${TARGET}/var/cache/$(basename "${PORTAGE_SQ}")
pv "${PORTAGE_SQ}" > "${PORTAGE_SQ_TGT}"
ln -s "${PORTAGE_SQ}" "${TARGET}"/var/cache/portage.squashfs
mkdir "${TARGET}"/usr/portage
eend

ebegin "mount portage squashfs"
mount "${TARGET}"/var/cache/portage.squashfs "${TARGET}"/usr/portage
eend

ebegin "configure filesystem"
sed -ne '/^#/p' -i "${TARGET}"/etc/fstab
cat >> "${TARGET}"/etc/fstab <<EOF
/dev/mmcblk0p1		/boot		vfat		defaults	1 2
/dev/mmcblk0p2		none		swap		sw			0 0
/dev/mmcblk0p3		/		ext4		noatime	0 1
/var/cache/portage.squashfs	/usr/portage	squashfs	ro	0 0
none			/tmp	tmpfs		size=256M	0 0
EOF
eend

ebegin "setup profile and make.conf"
cat >> "${TARGET}"/etc/portage/make.conf <<EOF
USE="\${USE} bash-completion zsh-completion"
DISTDIR=/var/cache/distfiles
PKGDIR=/var/cache/packages
PORT_LOGDIR=/var/log/portage
SYNC=squashfs
FEATURES="\${FEATURES} candy"
#BINHOST="http://lore.xmw.de/gentoo/binhost/\${CHOST}/raspberrypi-experimental/"'
#FEATURES="\${FEATURES} buildpkg getbinpkg"
#EMERGE_DEFAULT_OPTS="--binpkg-respect-use y"
#PORTAGE_TMPDIR="/tmp"
EOF

# profile update
rm "${TARGET}"/etc/portage/make.profile
ln -s ../../usr/portage/profiles/default/linux/arm/13.0 \
	"${TARGET}"/etc/portage/make.profile
eend

ebegin "install kernel"
ACCEPT_KEYWORDS="~arm" emerge -v --nodeps --root=/rpi/target "=sys-kernel/raspberrypi-image-3.2.27_p20121105"
cp -v "${TARGET}"/boot/kernel-3.2.27+.img "${TARGET}"/boot/kernel.img

ebegin "install boot loader"
ACCEPT_KEYWORDS="~arm" emerge -v --nodeps --root=/rpi/target "=sys-boot/raspberrypi-loader-0_p20130705"
eend

sed -e 's:root=[/a-z0-9]*:root=/dev/mmcblk0p3:' \
	-i "${TARGET}"/boot/cmdline.txt
eend

ebegin "set hostname=genberry and root password=root"
mv ${TARGET}/etc/shadow{,-}
PASSWD=$(echo root | openssl passwd -1 -stdin)
{	echo "root:${PASSWD}:0:0:::::" # pam urges user to change password
	sed -e "/^root/d" "${TARGET}"/etc/shadow-
} > "${TARGET}"/etc/shadow
# name it 
sed -e '/^hostname=/s:=.*:="genberry":' -i "${TARGET}"/etc/conf.d/hostname
eend

ebegin "configure services"
#adjust name of the serial port
sed -e '/^s0:/s:ttyS0:ttyAMA0:' -i "${TARGET}"/etc/inittab

# start sshd anyway and don't stop it.
echo "rc_sshd_need=\"!net\"" >> "${TARGET}"/etc/rc.conf
ln -s /etc/init.d/ssh "${TARGET}"/etc/runlevels/default

# networking
ln -s net.lo "${TARGET}"/etc/init.d/net.eth0
ln -s /etc/init.d/net.eth0 "${TARGET}"/etc/runlevels/default

#clocks
rm "${TARGET}"/etc/runlevels/boot/hwclock
ln -s /etc/init.d/swclock "${TARGET}"/etc/runlevels/boot
ln -s /etc/init.d/savecache "${TARGET}"/etc/runlevels/boot/savecache

# swclock pre-set to image creation time
mkdir -p "${TARGET}"/lib/rc/cache
touch "${TARGET}"/lib/rc/cache/shutdowntime

# timezone
rm "${TARGET}"/etc/localtime
ln -s ../usr/share/zoneinfo/UTC "${TARGET}"/etc/localtime
eend

echo Fin
