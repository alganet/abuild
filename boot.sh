#!/bin/sh

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

$MKDIR -p "files/vendor"

if ! test -f files/vendor/stage0-posix-1.9.1.tar.gz
then $WGET -O files/vendor/stage0-posix-1.9.1.tar.gz https://github.com/oriansj/stage0-posix/releases/download/Release_1.9.1/stage0-posix-1.9.1.tar.gz
fi

if ! test -f files/vendor/builder-hex0-main.tar.gz
then $WGET -O files/vendor/builder-hex0-main.tar.gz https://github.com/ironmeld/builder-hex0/archive/refs/heads/main.tar.gz
fi

if ! test -d build/descend
then
    $MKDIR -p build/descend/builder-hex0
    $GZIP --decompress --keep files/vendor/stage0-posix-1.9.1.tar.gz
    $TAR --extract --strip-components=1 --directory build/descend --file=files/vendor/stage0-posix-1.9.1.tar
    $RM -f files/vendor/stage0-posix-1.9.1.tar
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
then
    ./bootstrap-seeds/POSIX/x86/kaem-optional-seed kaem.x86
fi

if ! test -f ../k0.img
then
    if ./x86/bin/match "yes" "${FORCE_FAIL:-no}"
    then ./x86/bin/catm ./pre-build.kaem ./seal-break.kaem
    else ./x86/bin/catm ./pre-build.kaem ./noop.kaem
    fi

    ./x86/bin/wrap /x86/bin/kaem --verbose --strict --file k0.kaem
    ./x86/bin/cp ./dev/hda ../k0.img
fi

cd "$SH_ROOT"

if ! test -f build/k0.answers
then
    ./build/descend/x86/bin/sha256sum build/k0.img -o k0.answers
fi

$QEMU --enable-kvm -m 2G -nographic -machine kernel-irqchip=split -drive file="build/k0.img",format=raw --no-reboot

./build/descend/x86/bin/sha256sum -c k0.answers
