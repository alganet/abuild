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

if ! test -f files/vendor/mes-0.27.1.tar.gz
then $WGET -O files/vendor/mes-0.27.1.tar.gz https://ftp.gnu.org/gnu/mes/mes-0.27.1.tar.gz
fi

if ! test -f files/vendor/nyacc-1.00.2-lb1.tar.gz
then $WGET -O files/vendor/nyacc-1.00.2-lb1.tar.gz https://github.com/Googulator/nyacc/releases/download/V1.00.2-lb1/nyacc-1.00.2-lb1.tar.gz
fi

if ! test -f files/vendor/tcc-0.9.26-1147-gee75a10c.tar.gz
then $WGET -O files/vendor/tcc-0.9.26-1147-gee75a10c.tar.gz https://lilypond.org/janneke/tcc/tcc-0.9.26-1147-gee75a10c.tar.gz
fi

if ! test -f files/vendor/tcc-0.9.27.tar.bz2
then $WGET -O files/vendor/tcc-0.9.27.tar.bz2 https://download.savannah.gnu.org/releases/tinycc/tcc-0.9.27.tar.bz2
fi

if ! test -f files/vendor/fiwix-1.5.0-lb1.tar.gz
then $WGET -O files/vendor/fiwix-1.5.0-lb1.tar.gz https://github.com/mikaku/Fiwix/releases/download/v1.5.0-lb1/fiwix-1.5.0-lb1.tar.gz
fi

if ! test -f files/vendor/lwext4-1.0.0-lb1.tar.gz
then $WGET -O files/vendor/lwext4-1.0.0-lb1.tar.gz https://github.com/rick-masters/lwext4/releases/download/v1.0.0-lb1/lwext4-1.0.0-lb1.tar.gz
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

./build/descend/x86/bin/mkdir -p "$SH_ROOT/build/k0"
./build/descend/bin/bh0x "$SH_ROOT/build/k0.img" "$SH_ROOT/build/k0"

./build/descend/x86/bin/sha256sum -c k0.answers
