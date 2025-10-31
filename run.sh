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

run_make_host () {
	if ! test -d out/host
	then
		$MKDIR -p out/host/builder-hex0
		$GZIP --decompress --keep distfiles/stage0-posix-1.9.1.tar.gz
		$TAR --extract --strip-components=1 --directory out/host --file=distfiles/stage0-posix-1.9.1.tar
		$RM -f distfiles/stage0-posix-1.9.1.tar
		$GZIP --decompress --keep distfiles/builder-hex0-main.tar.gz
		$TAR --extract --strip-components=1 --directory "out/host/builder-hex0" --file=distfiles/builder-hex0-main.tar
		$RM distfiles/builder-hex0-main.tar
	fi

	$CP -Rf distfiles "$SH_ROOT/out/host"
	$CP -Rf tools "$SH_ROOT/out/host"
	$CP -Rf scripts "$SH_ROOT/out/host"
	printf 'intact' > "$SH_ROOT/out/host/seal"

	cd "$SH_ROOT/out/host"

	./bootstrap-seeds/POSIX/x86/hex0-seed x86/hex0_x86.hex0 x86/artifact/hex0
	./x86/artifact/hex0 x86/kaem-minimal.hex0 bootstrap-seeds/POSIX/x86/kaem-optional-seed

	if ! test -f ./x86/bin/sha256sum || ! ./x86/bin/sha256sum -c x86.answers
	then
		./bootstrap-seeds/POSIX/x86/kaem-optional-seed kaem.x86
		cd "$SH_ROOT"
		./out/host/x86/bin/sha256sum -o host.answers out/host/x86.answers
	fi
}

run_make_k0_img () {
	if ! cd "$SH_ROOT/out/host"
	then echo "info: run make_host first." && return 1
	fi

	if ! test -f ../k0.img
	then
		if ./x86/bin/match "yes" "${FORCE_FAIL:-no}"
		then ./x86/bin/catm ./scripts/pre-build.kaem ./scripts/seal-break.kaem
		else ./x86/bin/catm ./scripts/pre-build.kaem ./scripts/noop.kaem
		fi

		./x86/bin/wrap /x86/bin/kaem --verbose --strict --file /scripts/k0.kaem
		./x86/bin/cp ./dev/hda "$SH_ROOT/out/k0.img"
	fi

	cd "$SH_ROOT"

	if ! test -f k0.answers
	then
		./out/host/x86/bin/sha256sum -o k0.answers out/k0.img
	fi
}

run_boot_k0_img () {
	if ! $QEMU \
		--enable-kvm \
		-m 2G \
		-smp 2 \
		-nographic \
		-machine kernel-irqchip=split \
		-drive file="out/k0.img",format=raw \
		--no-reboot
	then
		echo "info: run make_k0_img first." && return 1
	fi
}

run_sha256sum_k0_answers () {
	./out/host/x86/bin/sha256sum -c k0.answers
}

run_make_k0 () {
	if ! {
		./out/host/x86/bin/mkdir -p "$SH_ROOT/out/k0" &&
		./out/host/bin/bh0x "$SH_ROOT/out/k0.img" "$SH_ROOT/out/k0"
	}
	then echo "info: run make_k0_img first." && return 1
	fi
}

run_all () {
	run_make_host
	run_make_k0_img
	run_boot_k0_img
	run_sha256sum_k0_answers
	run_make_k0
}

while test $# -gt 0
do "run_${1}" && shift || exit
done