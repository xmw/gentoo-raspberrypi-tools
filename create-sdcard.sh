#!/bin/zsh

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

setopt -e 

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
dd bs=1M count=4000 if=/dev/zero | pv -s 4000M > ${IMAGE}

LOOP=$(losetup -f)
losetup ${LOOP} ${IMAGE}
{ # 4194304000 / 255 / 63 / 512 -> 509
	echo ",16,0x0C,*"
	echo ",64,,-"
	echo ",,,-"
} | sfdisk -D -H 255 -S 63 -C 509 ${LOOP}
kpartx -a -v ${LOOP}
BOOT=/dev/mapper/$(basename ${LOOP})p1
SWAP=/dev/mapper/$(basename ${LOOP})p2
ROOT=/dev/mapper/$(basename ${LOOP})p3
mkfs.vfat ${BOOT}
mkswap ${SWAP}
mkfs.ext4 -i 4096 ${ROOT}

TARGET=${WORKDIR}/target
mkdir -p ${TARGET}
mount ${ROOT} ${TARGET}
mkdir -p ${TARGET}/boot
mount ${BOOT} ${TARGET}/boot
 
pv ${STAGE3} | tar xjC ${TARGET}
pv ${PORTAGE} | tar xJC ${TARGET}/usr

