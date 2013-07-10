#!/bin/zsh
# Michael Weber xmw at gentoo dot org 2013
#
# TODO 
#	portage tree in squashfs
# 	replace portage-latest with rsync

check() {
	[ "$(id -u)" -eq 0 ] || echo "run as root"
	for tool in mkdir wget openssl gpg pv mkfs.vfat mkswap mkfs.ext4 \
		tar kpartx losetup sfdisk dd
	do
		which ${tool} >/dev/null || echo "missing: ${tool}"
	done
}
ERR=$(check)
if [ -n "${ERR}" ] ; then
	echo ${ERR}
	exit 1
fi

setopt -e -x

WORKDIR=/rpi

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
wget -c -O ${STAGE3} ${URL}
wget -c -O ${STAGE3}.DIGESTS ${URL}.DIGESTS
wget -c -O ${STAGE3}.CONTENTS ${URL}.CONTENTS

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
URL=http://distfiles.gentoo.org/releases/snapshots/current/portage-latest.tar.xz
PORTAGE=${WORKDIR}/portage/$(basename ${URL})
wget -c -O ${PORTAGE} ${URL}
wget -c -O ${PORTAGE}.gpgsig ${URL}.gpgsig

gpg --recv-keys C9189250
gpg --verify ${PORTAGE}.gpgsig ${PORTAGE}

IMAGE=${WORKDIR}/image.raw
dd bs=1M count=2000 if=/dev/zero | pv -s 2000M > ${IMAGE}

LOOP=$(losetup -f)
losetup ${LOOP} ${IMAGE}
{ # 4194304000 / 255 / 63 / 512 -> 509
	echo ",16,0x0C,*"
	echo ",64,,-"
	echo ",,,-"
} | sfdisk -D -H 255 -S 63 -C 254 ${LOOP} #509

kpartx -a -v ${LOOP}

TARGET=${WORKDIR}/target

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

TMP=$(mktemp -d)
pv ${PORTAGE} | tar xJC ${TMP}
mksquashfs ${TMP} ${TARGET}/usr/portage.squashfs
rm -r ${TMP}

ACCEPT_KEYWORDS="~arm" emerge -v --nodeps --root=/rpi/target "=sys-kernel/raspberrypi-image-3.2.27_p20121105"
ACCEPT_KEYWORDS="~arm" emerge -v --nodeps --root=/rpi/target "=sys-boot/raspberrypi-loader-0_p20121105"

cp -v ${TARGET}/boot/kernel-3.2.27+.img ${TARGET}/boot/kernel.img

sed -e 's:root=[/a-z0-9]*:root=/dev/mmcblk0p3:' \
	-i ${TARGET}/boot/cmdline.txt

{
	sed -ne '/^#/p' ${TARGET}/etc/fstab
	echo -e "/dev/mmcblk0p1\t\t/boot\t\tvfat\t\tdefaults\t1 2"
	echo -e "/dev/mmcblk0p2\t\tnone\t\tswap\t\tsw\t\t0 0"
	echo -e "/dev/mmcblk0p3\t\t/\t\text4\t\tnoatime\t0 1"
} > ${TARGET}/etc/fstab.new
mv ${TARGET}/etc/fstab{.new,}

mv ${TARGET}/etc/shadow{,-}
local PASSWD=$(echo Gentoo | openssl passwd -1 -stdin)
{ 
	echo "root:${PASSWD}:0:0:::::"
	sed -e "/^root/d" ${TARGET}/etc/shadow-
} > ${TARGET}/etc/shadow

${SHELL}

umount ${BOOT} 
umount ${ROOT}


kpartx -d -v ${LOOP}

losetup -d ${LOOP}
