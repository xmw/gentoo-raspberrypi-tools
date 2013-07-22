#!/bin/bash
# vim: tabstop=4
# Michael Weber xmw at gentoo dot org 2013
#
# TODO 
#	provide update mechanism for portage.squashfs -> lore.xmw.de/gentoo

unset WORKDIR IMAGE TARGET BOOT SWAP ROOT TIMEZONE

[ -r /etc/genberry/create-sdcard.conf ] && source /etc/genberry/create-sdcard.conf

WORKDIR=${WORKDIR:-/rpi}
IMAGE=${IMAGE:-${WORKDIR}/image.raw}
TARGET=${TARGET:-${WORKDIR}/target}

VERIFY_GPG=${VERIFY_GPG:-1}
STAGE3_GPG_KEYID=${STAGE3_GPG_KEYID:-2D182910}
PORTAGE_GPG_KEYID=${PORTAGE_GPG_KEYID:-C9189250}
PORTAGE_ON_SQUASHFS=${PORTAGE_ON_SQUASHFS:-1}
UPDATE_FROM_BINHOST=${UPDATE_FROM_BINHOST:-1}
TIMEZONE="${TIMEZONE:-UTC}"
PASSWD=$(echo root | openssl passwd -1 -stdin)

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
		if ! gpg --list-keys ${STAGE3_GPG_KEYID} >/dev/null ; then
			echo "install key ${STAGE3_GPG_KEYID}, try"
			echo "gpg --keyserver pgp.mit.edu --recv-keys ${STAGE3_GPG_KEYID}"
		fi
		if ! gpg --list-keys ${PORTAGE_GPG_KEYID} >/dev/null ; then
			echo "install key ${PORTAGE_GPG_KEYID}, try"
			echo "gpg --keyserver pgp.mit.edu --recv-keys ${PORTAGE_GPG_KEYID}"
		fi
		GPG=gpg
	fi
	for tool in mkdir wget openssl pv mkfs.vfat mkswap mkfs.ext4 tar losetup \
		sfdisk dd mountpoint emerge ${GPG} tr bc ; do
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
[ -f "${STAGE3}".DIGESTS.asc ] || wget -O "${STAGE3}".DIGESTS.asc  "${URL}".DIGESTS.asc
[ -f "${STAGE3}".CONTENTS ] || wget -O "${STAGE3}".CONTENTS "${URL}".CONTENTS
eend

if [ "${VERIFY_GPG:-0}" -eq 1 ] ; then
	ebegin "verify stage3 gpg signature"
	gpg --decrypt "${STAGE3}".DIGESTS.asc > "${STAGE3}".DIGESTS
	eend
fi
ebegin "verify stage3 checksums"
{	cd "$(dirname "${STAGE3}")"
	for f in "$(basename "${STAGE3}")"{,.CONTENTS} ; do
		for h in MD5 SHA1 SHA512 WHIRLPOOL ; do
			echo "# ${h} HASH"
			openssl dgst -r -$(echo $h | tr '[A-Z]' '[a-z]') "${f}"
		done
	done
} | sed 's:*stage: stage:' | diff ${STAGE3}.DIGESTS -
eend

mkdir -p "${WORKDIR}"/portage
if [ "${PORTAGE_ON_SQUASHFS}" -eq 0 ] ; then
	ebegin "fetch portage snapshot"
	URL=http://lore.xmw.de/gentoo/snapshots/portage-latest.tar.xz
	PORTAGE=${WORKDIR}/portage/$(basename ${URL})
	wget -N -P "$(dirname "${PORTAGE}")" "${URL}"
	wget -N -P "$(dirname "${PORTAGE}")" "${URL}.gpgsig"
	eend

	if [ "${VERIFY_GPG:-0}" -eq 1 ] ; then
		ebegin "verify portage gpg signature"
		gpg --verify ${PORTAGE}.gpgsig ${PORTAGE}
		eend
	fi
else
	ebegin "fetch portage squashfs"
	URL=http://lore.xmw.de/gentoo/genberry/snapshots/LATEST.xz.txt
	LATEST=$(wget -O - -o /dev/null "${URL}")
	URL=$(dirname "${URL}")/${LATEST}
	PORTAGE_SQ=${WORKDIR}/portage/${LATEST}
	[ -f ${WORKDIR}/portage/${LATEST} ] || wget -O "${PORTAGE_SQ}" "${URL}"
	eend
fi

ebegin "create blank disk image"
CBYTES=$(echo 255*63*512 | bc) # bytes per cylinder of 255 heads and 63 sectors
SIZE=$(echo 2048*1024*1024 | bc) # estimated size
CYLS=$(echo ${SIZE}/${CBYTES} | bc)  # number of cylinders
SIZE=$(echo ${CYLS}*${CBYTES} | bc)  # exact image size
dd if=/dev/zero bs="${CBYTES}" count="${CYLS}" | pv -s "${SIZE}" > "${IMAGE}"
eend

ebegin "set up partitions"
LOOP=$(losetup -f)
losetup ${LOOP} ${IMAGE}
cat << EOF | fdisk -H 255 -S 63 -C 254 "${IMAGE}"
o
n
p
1
2048
+128M
n
p
2

+512M
n
p
3


t
1
c
t
2
82
t
3
83
w
EOF
partx -d "${LOOP}"
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
pv "${STAGE3}" | tar xjC "${TARGET}"
eend

mkdir "${TARGET}"/usr/portage
if [ "${PORTAGE_ON_SQUASHFS}" -eq 0 ] ; then
	ebegin "extract portage snapshot"
	pv "${PORTAGE}" > tar xJC "${TARGET}"/usr/portage
	eend
else
	ebegin "copy and mount portage squashfs"
	PORTAGE_SQ_TGT=${TARGET}/var/cache/portage/$(basename "${PORTAGE_SQ}")
	mkdir -p "${TARGET}/var/cache/portage"
	pv "${PORTAGE_SQ}" > "${PORTAGE_SQ_TGT}"
	ln -s "$(basename "${PORTAGE_SQ}")" \
		"${TARGET}"/var/cache/portage/latest.squashfs
	PORTAGE_MNT="/var/cache/portage/latest.squashfs	/usr/portage	squashfs	ro,loop	0 0"
	mount -o ro,loop "${TARGET}"/var/cache/portage/latest.squashfs "${TARGET}"/usr/portage
	DISABLE_SYNC="SYNC=\"use update-portage\""
	eend
fi

ebegin "configure filesystem"
sed -ne '/^#/p' -i "${TARGET}"/etc/fstab
cat >> "${TARGET}"/etc/fstab <<EOF
/dev/mmcblk0p1		/boot		vfat		defaults	1 2
/dev/mmcblk0p2		none		swap		sw			0 0
/dev/mmcblk0p3		/		ext4		noatime	0 1
none			/tmp	tmpfs		size=256M,noauto	0 0
${PORTAGE_MNT}
EOF
eend


ebegin "setup make.conf"
cat >> "${TARGET}"/etc/portage/make.conf <<EOF
USE="\${USE} bash-completion zsh-completion"
DISTDIR=/var/cache/distfiles
PKGDIR=/var/cache/packages
PORT_LOGDIR=/var/log/portage
${DISABLE_SYNC}
PORTAGE_BINHOST="http://lore.xmw.de/gentoo/genberry/experimental"
FEATURES="\${FEATURES} buildpkg getbinpkg"
EMERGE_DEFAULT_OPTS="--binpkg-respect-use y"
PORTAGE_TMPDIR="/tmp"
#source /var/lib/layman/make.conf
PORTDIR_OVERLAY="/usr/local/portage \${PORTDIR_OVERLAY}"
EOF
mkdir -p "${TARGET}"/usr/local/portage
eend

ebegin "update profile" 
rm "${TARGET}"/etc/portage/make.profile
ln -s ../../usr/portage/profiles/default/linux/arm/13.0/armv6j \
	"${TARGET}"/etc/portage/make.profile
eend

ebegin "keyword some packages and set use flags"
cat >> "${TARGET}"/etc/portage/package.keywords << EOF
=app-portage/eix-0.28.5::gentoo
=net-misc/openssh-6.2_p2*::gentoo **
=sys-boot/raspberrypi-firmware-0_p20130711::gentoo
=sys-kernel/raspberrypi-image-3.6.11_p20130711::gentoo
=net-libs/ldns-1.6.16::gentoo
EOF
cat >> "${TARGET}"/etc/portage/package.use << EOF
dev-lang/python:2.7 berkdb sqlite
net-misc/openssh ldns
net-libs/ldns -ecdsa
EOF

export ROOT=${TARGET}
export FEATURES="-buildpkg"

ebegin "install binary bootloader and kernel image"
ACCEPT_KEYWORDS="~arm" emerge --verbose --quiet-build --nodeps \
	"=sys-kernel/raspberrypi-image-3.6.11_p20130711" \
	"=sys-boot/raspberrypi-firmware-0_p20130711"
cp -v "${TARGET}"/boot/kernel-3.6.11+.img "${TARGET}"/boot/kernel.img
eend

ebegin "update kernel command line"
sed -e 's:root=[/a-z0-9]*:root=/dev/mmcblk0p3:' \
	-i "${TARGET}"/boot/cmdline.txt
eend

export PORTAGE_CONFIGROOT=${TARGET}

if [ "${UPDATE_FROM_BINHOST}" -eq 1 ] ; then
	ebegin "install essential packages from binhost"
	emerge --quiet-build --verbose --usepkgonly \
		sys-apps/portage #update to FEATURES=preserved-libs
	emerge --quiet-build --verbose --usepkgonly \
		app-admin/logrotate \
		app-admin/syslog-ng \
		app-misc/screen \
		app-portage/eix \
		app-portage/layman \
		app-shells/zsh \
		net-misc/ntp \
		net-misc/openssh \
		sys-process/dcron \
		sys-process/htop \
		sys-apps/mlocate
	eend
	ebegin "update @world from binhost"
	emerge --quiet-build --verbose --update --changed-use --deep --usepkgonly \
		@world
	eend
	ebegin "simulate dispatch-conf"
	for f in $(find "${TARGET}" -name "._cfg????_*" | sort) ; do
		fn=$(basename "${f}")
		mv -vf "${f}" "$(dirname "${f}")/${fn#._cfg????_}"
	done
	eend
fi

ebegin "set hostname=genberry and root password=root"
mv ${TARGET}/etc/shadow{,-}
{	echo "root:${PASSWD}:15900:0:::::"
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
ln -s /etc/init.d/sshd "${TARGET}"/etc/runlevels/default

# networking
ln -s net.lo "${TARGET}"/etc/init.d/net.eth0
ln -s /etc/init.d/net.eth0 "${TARGET}"/etc/runlevels/default

#clocks
rm "${TARGET}"/etc/runlevels/boot/hwclock
ln -s /etc/init.d/swclock "${TARGET}"/etc/runlevels/boot
#ln -s /etc/init.d/savecache "${TARGET}"/etc/runlevels/boot/savecache
ln -s /etc/init.d/ntp-client "${TARGET}"/etc/runlevels/default

# swclock pre-set to image creation time
mkdir -p "${TARGET}"/lib/rc/cache
touch "${TARGET}"/lib/rc/cache/shutdowntime

# timezone
rm "${TARGET}"/etc/localtime
ln -s ../usr/share/zoneinfo/"${TIMEZONE}" "${TARGET}"/etc/localtime

cat >> "${TARGET}"/etc/sysctl.d/genberry.conf << EOF
vm.swappiness=1
vm.min_free_kbytes = 16184
EOF

cat >> "${TARGET}"/etc/conf.d/net << EOF
#config_eth0="192.168.23.5/24"
#routes_eth0="default via 192.168.23.254"
#dns_servers_eth0="8.8.8.8"
#dns_domain_eth0=""
#dns_search=""
EOF

eend

echo Fin
