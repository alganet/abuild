#!/bin/sh

QEMU="${QEMU:-$(command -v qemu-system-i386)}"
WGET="${WGET:-$(command -v wget)}"
MKDIR="${MKDIR:-$(command -v mkdir)}"
RM="${RM:-$(command -v rm)}"
CP="${CP:-$(command -v cp)}"
GZIP="${GZIP:-$(command -v gzip)}"
TAR="${TAR:-$(command -v tar)}"

set -euf
PATH=

SH_FILE="$PWD/$0"
SH_ROOT="${SH_FILE%\/*}"
cd "$SH_ROOT"

$MKDIR -p "files/vendor"

if ! test -f files/vendor/stage0-posix-1.7.0.tar.gz
then $WGET -O files/vendor/stage0-posix-1.7.0.tar.gz https://github.com/oriansj/stage0-posix/releases/download/Release_1.7.0/stage0-posix-1.7.0.tar.gz
fi

if ! test -f files/vendor/builder-hex0-main.tar.gz
then $WGET -O files/vendor/builder-hex0-main.tar.gz https://github.com/ironmeld/builder-hex0/archive/refs/heads/main.tar.gz
fi

if ! test -d build/descend
then
    $MKDIR -p build/descend/builder-hex0
    $GZIP --decompress --keep files/vendor/stage0-posix-1.7.0.tar.gz
    $TAR --extract --strip-components=1 --directory build/descend --file=files/vendor/stage0-posix-1.7.0.tar
    $RM -f files/vendor/stage0-posix-1.7.0.tar
    $GZIP --decompress --keep files/vendor/builder-hex0-main.tar.gz
    $TAR --extract --strip-components=1 --directory "build/descend/builder-hex0" --file=files/vendor/builder-hex0-main.tar
    $RM files/vendor/builder-hex0-main.tar
fi

cd files
$CP -Rf . "$SH_ROOT/build/descend"

cd "$SH_ROOT/build/descend"

./bootstrap-seeds/POSIX/x86/hex0-seed x86/hex0_x86.hex0 x86/artifact/hex0
./x86/artifact/hex0 x86/kaem-minimal.hex0 bootstrap-seeds/POSIX/x86/kaem-optional-seed

if ! ./x86/bin/sha256sum -c x86.answers
then ./bootstrap-seeds/POSIX/x86/kaem-optional-seed kaem.x86
fi

if ! test -f ../k0.img
then
    ./x86/bin/wrap /x86/bin/kaem --verbose --strict --file k0.kaem
    ./x86/bin/cp ./dev/hda ../k0.img
fi

cd "$SH_ROOT"

$QEMU --enable-kvm -m 2G -nographic -machine kernel-irqchip=split -drive file="build/k0.img",format=raw --no-reboot
