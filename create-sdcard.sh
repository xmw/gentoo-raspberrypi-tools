#!/bin/zsh
# Michael Weber xmw at gentoo dot org 2013
#
# TODO 
#	provide update mechanism for portage.squashfs -> lore.xmw.de/gentoo
#	fix respawning s0
# ADD
#	syslog-ng, dcron, eix, vim, ntp, slocate

WORKDIR=/rpi
IMAGE=${WORKDIR}/image.raw
TARGET=${WORKDIR}/target

VERIFY_GPG=1
GPG_KEYID=C9189250

check() {
	[ "$(id -u)" -eq 0 ] || echo "run as root"
	[ -d "${WORKDIR}" ] || echo "WORKDIR=${WORKDIR} does not exist"
	if [ "${VERIFY_GPG:-0}" -eq 1 ] ; then
		if ! gpg --list-keys ${GPG_KEYID} >/dev/null ; then
			echo "install key ${GPG_KEYID}, try"
			echo "  gpg --keyserver pgp.mit.edu --recv-keys ${GPG_KEYID}"
		fi
	fi
	for tool in mkdir wget openssl gpg pv mkfs.vfat mkswap mkfs.ext4 \
		tar kpartx losetup sfdisk dd mksquashfs mountpoint ; do
		which ${tool} >/dev/null || echo "missing: ${tool}"
	done
	if losetup -a | grep ${IMAGE} >/dev/null ; then
		echo "The target file ${IMAGE} is set up as loopback device."
		echo "Proceeding would cause file corruption, exiting."
	fi
	if mountpoint ${TARGET} >/dev/null ; then
		echo "The target mountpoint ${TARGET} is already mounted."
		echo "Proceeding would overshadown the filesystem,"
		echo "and is most likely due to an unfinished previous invocation."
	fi
}
ERR=$(check)
if [ -n "${ERR}" ] ; then
	echo ${ERR}
	exit 1
fi

setopt -e -x

LATEST="20130207/20130207/armv6j-hardfloat-linux-gnueabi/stage3-armv6j_hardfp-20130207.tar.bz2"

latest=$(wget -O - http://distfiles.gentoo.org/releases/arm/autobuilds/latest-stage3-armv6j_hardfp.txt 2>/dev/null | tail -n 1)

if [ "${LATEST}" != "${latest}" ] ; then
	echo "update stage3 tarball reference to"
	echo "${latest}"
	exit 1
fi

mkdir -p ${WORKDIR}/stage3
URL=http://distfiles.gentoo.org/releases/arm/autobuilds/${LATEST}
STAGE3=${WORKDIR}/stage3/$(basename ${URL})
[ -f ${STAGE3}          ] || wget -O ${STAGE3}          ${URL}
[ -f ${STAGE3}.DIGESTS  ] || wget -O ${STAGE3}.DIGESTS  ${URL}.DIGESTS
[ -f ${STAGE3}.CONTENTS ] || wget -O ${STAGE3}.CONTENTS ${URL}.CONTENTS

{ #stupid way to do that
	cd $(dirname ${STAGE3})
	echo "# MD5 HASH"
	openssl dgst -r -md5 $(basename ${STAGE3}) 
	echo "# SHA1 HASH"
	openssl dgst -r -sha1 $(basename ${STAGE3})
	echo "# SHA512 HASH"
	openssl dgst -r -sha512 $(basename ${STAGE3})
	echo "# WHIRLPOOL HASH"
	openssl dgst -r -whirlpool $(basename ${STAGE3})
	echo "# MD5 HASH"
	openssl dgst -r -md5 $(basename ${STAGE3}.CONTENTS)
	echo "# SHA1 HASH"
	openssl dgst -r -sha1 $(basename ${STAGE3}.CONTENTS)
	echo "# SHA512 HASH"
	openssl dgst -r -sha512 $(basename ${STAGE3}.CONTENTS)
	echo "# WHIRLPOOL HASH"
	openssl dgst -r -whirlpool $(basename ${STAGE3}.CONTENTS)
} | sed 's:*stage: stage:' | diff ${STAGE3}.DIGESTS -

mkdir -p ${WORKDIR}/portage
URL=http://lore.xmw.de/gentoo/snapshots/portage-20130709.tar.xz
PORTAGE=${WORKDIR}/portage/$(basename ${URL})
[ -f ${PORTAGE}        ] || wget -O ${PORTAGE}        ${URL}
[ -f ${PORTAGE}.gpgsig ] || wget -O ${PORTAGE}.gpgsig ${URL}.gpgsig

if [ "${VERIFY_GPG:-0}" -eq 1 ] ; then
	gpg --verify ${PORTAGE}.gpgsig ${PORTAGE}
fi

dd bs=1M count=2000 if=/dev/zero | pv -s 2000M > ${IMAGE}

LOOP=$(losetup -f)
losetup ${LOOP} ${IMAGE}
{ # 4194304000 / 255 / 63 / 512 -> 509
	echo ",16,0x0C,*"
	echo ",64,,-"
	echo ",,,-"
} | sfdisk -D -H 255 -S 63 -C 254 ${LOOP} #509

kpartx -a -v ${LOOP}

ROOT=/dev/mapper/$(basename ${LOOP})p3
mkfs.ext4 -i 4096 ${ROOT}
mkdir -p ${TARGET}
mount ${ROOT} ${TARGET}

BOOT=/dev/mapper/$(basename ${LOOP})p1
mkfs.vfat ${BOOT}
mkdir -p ${TARGET}/boot
mount ${BOOT} ${TARGET}/boot

SWAP=/dev/mapper/$(basename ${LOOP})p2
mkswap ${SWAP}
 
pv ${STAGE3} | tar xjC ${TARGET}

PORTAGE_SQ=${PORTAGE%.tar.xz}.squashfs
if ! [ -f ${PORTAGE_SQ} ] ; then 
	mkdir -p ${WORKDIR}/tmp
	TMP=$(mktemp -d ${WORKDIR}/tmp/squash.XXXXX)
	pv ${PORTAGE} | tar xJC ${TMP}
	mksquashfs ${TMP}/portage ${PORTAGE_SQ}
	rm -r ${TMP}
fi

PORTAGE_SQ_TGT=${TARGET}/var/cache/$(basename ${PORTAGE_SQ})
pv ${PORTAGE_SQ} > ${PORTAGE_SQ_TGT}
ln -s ${PORTAGE_SQ} ${TARGET}/var/cache/portage.squashfs
mkdir ${TARGET}/usr/portage

ACCEPT_KEYWORDS="~arm" emerge -v --nodeps --root=/rpi/target "=sys-kernel/raspberrypi-image-3.2.27_p20121105"
ACCEPT_KEYWORDS="~arm" emerge -v --nodeps --root=/rpi/target "=sys-boot/raspberrypi-loader-0_p20130705"

cp -v ${TARGET}/boot/kernel-3.2.27+.img ${TARGET}/boot/kernel.img

sed -e 's:root=[/a-z0-9]*:root=/dev/mmcblk0p3:' \
	-i ${TARGET}/boot/cmdline.txt

{
	sed -ne '/^#/p' ${TARGET}/etc/fstab
	echo -e "/dev/mmcblk0p1\t\t/boot\t\tvfat\t\tdefaults\t1 2"
	echo -e "/dev/mmcblk0p2\t\tnone\t\tswap\t\tsw\t\t0 0"
	echo -e "/dev/mmcblk0p3\t\t/\t\text4\t\tnoatime\t0 1"
	echo -e "/var/cache/portage.quashfs\t/usr/portage\tsquashfs\t\tro\t0 0"
} > ${TARGET}/etc/fstab.new
mv ${TARGET}/etc/fstab{.new,}

mv ${TARGET}/etc/shadow{,-}
local PASSWD=$(echo root | openssl passwd -1 -stdin)
{
	echo "root:${PASSWD}:0:0:::::" # pam urges user to change password
	sed -e "/^root/d" ${TARGET}/etc/shadow-
} > ${TARGET}/etc/shadow

# services
ln -s net.lo ${TARGET}/etc/init.d/net.eth0
#start sshd anyway and don't stop it.
echo "rc_sshd_need=\"!net\"" >> ${TARGET}/etc/rc.conf
ln -s /etc/init.d/net.eth0 ${TARGET}/etc/runlevels/default/sshd
ln -s /etc/init.d/swclock ${TARGET}/etc/runlevels/boot/swclock
ln -s /etc/init.d/savecache ${TARGET}/etc/runlevels/boot/savecache

# swclock pre-set to image creation time
mkdir -p ${TARGET}/lib/rc/cache
touch ${TARGET}/lib/rc/cache/shutdowntime

# make.conf
{ 
	echo
	echo 'USE="${USE} zsh-completion"'
	echo 'DISTDIR=/var/cache/distfiles'
	echo 'PKGDIR=/var/cache/packages'
	echo 'PORT_LOGDIR=/var/log/portage'
	echo 'SYNC=squashfs'
	echo 'FEATURES="${FEATURES} candy"'
	echo '#BINHOST="http://lore.xmw.de/gentoo/binhost/${CHOST}/raspberrypi-experimental/"'
	echo '#FEATURES="${FEATURES} buildpkg getbinpkg"'
	echo '#EMERGE_DEFAULT_OPTS="--binpkg-respect-use y"'
} >> ${TARGET}/etc/portage/make.conf

# profile update
rm ${TARGET}/etc/portage/make.profile
ln -s ../../usr/portage/profiles/default/linux/arm/13.0 \
	${TARGET}/etc/portage/make.profile

# timezone
rm ${TARGET}/etc/localtime
ln -s ../usr/share/zoneinfo/UTC ${TARGET}/etc/localtime

echo "Starting a shell for modifications of ${TARGET}"
echo "Exit shell to finish image creation."
${SHELL}

umount ${BOOT} 
umount ${ROOT}

kpartx -d -v ${LOOP}

losetup -d ${LOOP}
