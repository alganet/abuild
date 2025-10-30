#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

QEMU="${QEMU:-$(command -v qemu-system-i386)}"
WGET="${WGET:-$(command -v wget)}"
MKDIR="${MKDIR:-$(command -v mkdir)}"
RM="${RM:-$(command -v rm)}"
CP="${CP:-$(command -v cp)}"
GZIP="${GZIP:-$(command -v gzip)}"
TAR="${TAR:-$(command -v tar)}"

set -eufx
PATH=

SH_FILE="$PWD/$0"
SH_ROOT="${SH_FILE%\/*}"
cd "$SH_ROOT"

. "$SH_ROOT/distfiles.sh"

if ! test -d build/host
then
    $MKDIR -p build/host/builder-hex0
    $GZIP --decompress --keep distfiles/stage0-posix-1.9.1.tar.gz
    $TAR --extract --strip-components=1 --directory build/host --file=distfiles/stage0-posix-1.9.1.tar
    $RM -f distfiles/stage0-posix-1.9.1.tar
    $GZIP --decompress --keep distfiles/builder-hex0-main.tar.gz
    $TAR --extract --strip-components=1 --directory "build/host/builder-hex0" --file=distfiles/builder-hex0-main.tar
    $RM distfiles/builder-hex0-main.tar
fi

$CP -Rf distfiles "$SH_ROOT/build/host"
$CP -Rf tools "$SH_ROOT/build/host"
$CP -Rf scripts "$SH_ROOT/build/host"
printf 'intact' > "$SH_ROOT/build/host/seal"

cd "$SH_ROOT/build/host"

./bootstrap-seeds/POSIX/x86/hex0-seed x86/hex0_x86.hex0 x86/artifact/hex0
./x86/artifact/hex0 x86/kaem-minimal.hex0 bootstrap-seeds/POSIX/x86/kaem-optional-seed

if ! test -f ./x86/bin/sha256sum || ! ./x86/bin/sha256sum -c x86.answers
then
    ./bootstrap-seeds/POSIX/x86/kaem-optional-seed kaem.x86
fi

if ! test -f ../k0.img
then
    if ./x86/bin/match "yes" "${FORCE_FAIL:-no}"
    then ./x86/bin/catm ./scripts/pre-build.kaem ./scripts/seal-break.kaem
    else ./x86/bin/catm ./scripts/pre-build.kaem ./scripts/noop.kaem
    fi

    ./x86/bin/wrap /x86/bin/kaem --verbose --strict --file /scripts/k0.kaem
    ./x86/bin/cp ./dev/hda "$SH_ROOT/build/k0.img"
fi

cd "$SH_ROOT"

if ! test -f build/k0.answers
then
    ./build/host/x86/bin/sha256sum build/k0.img -o k0.answers
fi

$QEMU \
	--enable-kvm \
	-m 2G \
	-smp 2 \
	-nographic \
	-machine kernel-irqchip=split \
	-drive file="build/k0.img",format=raw \
	--no-reboot

./build/host/x86/bin/sha256sum -c k0.answers

./build/host/x86/bin/mkdir -p "$SH_ROOT/build/k0"
./build/host/bin/bh0x "$SH_ROOT/build/k0.img" "$SH_ROOT/build/k0"
