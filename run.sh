#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

ARCH="${ARCH:-x86}"

# Default board per architecture (x86 only has bios, others default to virt)
case "$ARCH" in
	x86) BOARD="${BOARD:-bios}" ;;
	*)   BOARD="${BOARD:-virt}" ;;
esac

# Detect host architecture (x86_64 falls back to x86 for 32-bit compatibility)
case "${HOST_ARCH:-$(uname -m)}" in
	x86_64|i686|i386|x86) HOST_ARCH="x86" ;;
	riscv64)              HOST_ARCH="riscv64" ;;
	aarch64)              HOST_ARCH="aarch64" ;;
	*)                    echo "error: unsupported host arch $(uname -m)" && exit 1 ;;
esac

# stage0-posix directory name for host arch (AArch64 uses mixed case)
case "$HOST_ARCH" in
	aarch64) STAGE0_HOST="AArch64" ;;
	*)       STAGE0_HOST="$HOST_ARCH" ;;
esac

case "$ARCH" in
	x86)     QEMU="${QEMU:-$(command -v qemu-system-i386)}" ;;
	riscv64) QEMU="${QEMU:-$(command -v qemu-system-riscv64)}" ;;
	aarch64) QEMU="${QEMU:-$(command -v qemu-system-aarch64)}" ;;
	*)       echo "error: unsupported ARCH=$ARCH" && exit 1 ;;
esac

WGET="${WGET:-$(command -v wget)}"
MKDIR="${MKDIR:-$(command -v mkdir)}"
RM="${RM:-$(command -v rm)}"
CP="${CP:-$(command -v cp)}"
GZIP="${GZIP:-$(command -v gzip)}"
TAR="${TAR:-$(command -v tar)}"
MAKE="${MAKE:-$(command -v make)}"

set -eufx
PATH=

SH_FILE="$PWD/$0"
SH_ROOT="${SH_FILE%\/*}"
cd "$SH_ROOT"

. "$SH_ROOT/distfiles.sh"

run_make_host () {
	$MKDIR -p out/host-${HOST_ARCH}/builder-hex0-arch

	if ! test -d out/host-${HOST_ARCH}/stage0-posix-extracted
	then
		$GZIP --decompress --keep distfiles/stage0-posix-1.9.1.tar.gz
		$TAR --extract --strip-components=1 --directory out/host-${HOST_ARCH} --file=distfiles/stage0-posix-1.9.1.tar
		$RM -f distfiles/stage0-posix-1.9.1.tar
		$MKDIR -p out/host-${HOST_ARCH}/stage0-posix-extracted
	fi

	# Always re-extract builder-hex0-arch (may be updated independently of stage0-posix)
	$GZIP --decompress --keep distfiles/builder-hex0-arch-main.tar.gz
	$TAR --extract --strip-components=1 --directory out/host-${HOST_ARCH}/builder-hex0-arch --file=distfiles/builder-hex0-arch-main.tar
	$RM -f distfiles/builder-hex0-arch-main.tar
	
	$CP -Rf distfiles "$SH_ROOT/out/host-${HOST_ARCH}"
	$CP -Rf tools "$SH_ROOT/out/host-${HOST_ARCH}"
	$CP -Rf scripts "$SH_ROOT/out/host-${HOST_ARCH}"
	printf 'intact' > "$SH_ROOT/out/host-${HOST_ARCH}/seal"

	cd "$SH_ROOT/out/host-${HOST_ARCH}"

	# Bootstrap host tools from hex0 seed
	# (stage0-posix uses ${STAGE0_HOST} for directory names, ${HOST_ARCH} for kaem/answers)
	./bootstrap-seeds/POSIX/${STAGE0_HOST}/hex0-seed ${STAGE0_HOST}/hex0_${STAGE0_HOST}.hex0 ${STAGE0_HOST}/artifact/hex0
	# Build stage1 kernel images for all arch+board combinations
	$MKDIR -p ./bootstrap-seeds/NATIVE/x86
	$MKDIR -p ./bootstrap-seeds/NATIVE/riscv64
	$MKDIR -p ./bootstrap-seeds/NATIVE/aarch64
	./${STAGE0_HOST}/artifact/hex0 ./builder-hex0-arch/builder-hex0-x86-stage1-bios.hex0 ./bootstrap-seeds/NATIVE/x86/builder-hex0-x86-stage1-bios.img
	./${STAGE0_HOST}/artifact/hex0 ./builder-hex0-arch/builder-hex0-riscv64-stage1-virt.hex0 ./bootstrap-seeds/NATIVE/riscv64/builder-hex0-riscv64-stage1-virt.img
	./${STAGE0_HOST}/artifact/hex0 ./builder-hex0-arch/builder-hex0-riscv64-stage1-sifive_u.hex0 ./bootstrap-seeds/NATIVE/riscv64/builder-hex0-riscv64-stage1-sifive_u.img
	./${STAGE0_HOST}/artifact/hex0 ./builder-hex0-arch/builder-hex0-aarch64-stage1-virt.hex0 ./bootstrap-seeds/NATIVE/aarch64/builder-hex0-aarch64-stage1-virt.img
	./${STAGE0_HOST}/artifact/hex0 ./builder-hex0-arch/builder-hex0-aarch64-stage1-raspi3b.hex0 ./bootstrap-seeds/NATIVE/aarch64/builder-hex0-aarch64-stage1-raspi3b.img
	./${STAGE0_HOST}/artifact/hex0 ${STAGE0_HOST}/kaem-minimal.hex0 bootstrap-seeds/POSIX/${STAGE0_HOST}/kaem-optional-seed

	if ! test -f ./${STAGE0_HOST}/bin/sha256sum || ! ./${STAGE0_HOST}/bin/sha256sum -c ${HOST_ARCH}.answers
	then
		./bootstrap-seeds/POSIX/${STAGE0_HOST}/kaem-optional-seed kaem.${HOST_ARCH}
		cd "$SH_ROOT"
		./out/host-${HOST_ARCH}/${STAGE0_HOST}/bin/sha256sum -o host-${HOST_ARCH}.answers \
			out/host-${HOST_ARCH}/${HOST_ARCH}.answers \
			out/host-${HOST_ARCH}/bootstrap-seeds/NATIVE/x86/builder-hex0-x86-stage1-bios.img \
			out/host-${HOST_ARCH}/bootstrap-seeds/NATIVE/riscv64/builder-hex0-riscv64-stage1-virt.img \
			out/host-${HOST_ARCH}/bootstrap-seeds/NATIVE/riscv64/builder-hex0-riscv64-stage1-sifive_u.img \
			out/host-${HOST_ARCH}/bootstrap-seeds/NATIVE/aarch64/builder-hex0-aarch64-stage1-virt.img \
			out/host-${HOST_ARCH}/bootstrap-seeds/NATIVE/aarch64/builder-hex0-aarch64-stage1-raspi3b.img
	fi
}

run_make_k0_img () {
	if ! cd "$SH_ROOT/out/host-${HOST_ARCH}"
	then echo "info: run make_host first." && return 1
	fi

	if ! test -f "../k0-${ARCH}.img"
	then
		# Generate env preamble for host-side kaem execution
		printf 'set -a\nARCH="%s"\nHOST_ARCH="%s"\nSTAGE0_HOST="%s"\nBOARD="%s"\n' "$ARCH" "$HOST_ARCH" "$STAGE0_HOST" "$BOARD" > ./scripts/env.kaem

		# Regenerate in-image env file with current BOARD (idempotent)
		printf '# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>\n# SPDX-License-Identifier: GPL-3.0-or-later\n\nset -a\nARCH="%s"\nHOST_ARCH="%s"\nSTAGE0_HOST="%s"\nBOARD="%s"\n' "$ARCH" "$ARCH" "$( case "$ARCH" in aarch64) echo AArch64 ;; *) echo "$ARCH" ;; esac )" "$BOARD" > "./scripts/env.${ARCH}.kaem"

		# Concatenate env preamble + seal-break into pre-build.kaem
		if ./${STAGE0_HOST}/bin/match "yes" "${FORCE_FAIL:-no}"
		then ./${STAGE0_HOST}/bin/catm ./scripts/pre-build.kaem ./scripts/env.${ARCH}.kaem ./scripts/seal-break.kaem
		else ./${STAGE0_HOST}/bin/catm ./scripts/pre-build.kaem ./scripts/env.${ARCH}.kaem ./scripts/noop.kaem
		fi

		# Concatenate env preamble + k0.kaem for host-side execution
		./${STAGE0_HOST}/bin/catm ./scripts/k0-run.kaem ./scripts/env.kaem ./scripts/k0.kaem
		./${STAGE0_HOST}/bin/wrap /${STAGE0_HOST}/bin/kaem --verbose --strict --file /scripts/k0-run.kaem
		./${STAGE0_HOST}/bin/cp ./dev/hda "$SH_ROOT/out/k0-${ARCH}.img"
	fi

	cd "$SH_ROOT"

	if ! test -f "k0-${ARCH}.answers"
	then
		./out/host-${HOST_ARCH}/${STAGE0_HOST}/bin/sha256sum -o "k0-${ARCH}.answers" "out/k0-${ARCH}.img"
	fi
}

run_boot_k0_img () {
	case "$ARCH" in
		x86)
			if ! $QEMU \
				--enable-kvm \
				-m 2G \
				-smp 2 \
				-nographic \
				-machine kernel-irqchip=split \
				-drive file="out/k0-${ARCH}.img",format=raw \
				--no-reboot
			then
				echo "info: run make_k0_img first." && return 1
			fi
			;;
		riscv64)
			case "$BOARD" in
				virt)
					if ! $QEMU \
						-machine virt \
						-m 2G \
						-nographic \
						-kernel "${SH_ROOT}/out/host-${HOST_ARCH}/bootstrap-seeds/NATIVE/${ARCH}/builder-hex0-${ARCH}-stage1-${BOARD}.img" \
						-drive file="out/k0-${ARCH}.img",format=raw,if=none,id=hd0 \
						-device virtio-blk-device,drive=hd0 \
						--no-reboot
					then
						echo "info: run make_k0_img first." && return 1
					fi
					;;
				sifive_u)
					if ! $QEMU \
						-machine sifive_u \
						-m 2G \
						-nographic \
						-kernel "${SH_ROOT}/out/host-${HOST_ARCH}/bootstrap-seeds/NATIVE/${ARCH}/builder-hex0-${ARCH}-stage1-${BOARD}.img" \
						-drive file="out/k0-${ARCH}.img",format=raw,if=sd \
						--no-reboot
					then
						echo "info: run make_k0_img first." && return 1
					fi
					;;
				*)
					echo "error: unsupported BOARD=$BOARD for ARCH=$ARCH" && exit 1
					;;
			esac
			;;
		aarch64)
			case "$BOARD" in
				virt)
					if ! $QEMU \
						-machine virt -cpu cortex-a53 \
						-m 2G \
						-nographic \
						-kernel "${SH_ROOT}/out/host-${HOST_ARCH}/bootstrap-seeds/NATIVE/${ARCH}/builder-hex0-${ARCH}-stage1-${BOARD}.img" \
						-drive file="out/k0-${ARCH}.img",format=raw,if=none,id=hd0 \
						-device virtio-blk-device,drive=hd0 \
						--no-reboot
					then
						echo "info: run make_k0_img first." && return 1
					fi
					;;
				raspi3b)
					if ! $QEMU \
						-machine raspi3b \
						-serial mon:stdio \
						-nographic \
						-kernel "${SH_ROOT}/out/host-${HOST_ARCH}/bootstrap-seeds/NATIVE/${ARCH}/builder-hex0-${ARCH}-stage1-${BOARD}.img" \
						-drive file="out/k0-${ARCH}.img",if=sd,format=raw \
						--no-reboot
					then
						echo "info: run make_k0_img first." && return 1
					fi
					;;
				*)
					echo "error: unsupported BOARD=$BOARD for ARCH=$ARCH" && exit 1
					;;
			esac
			;;
	esac
}

run_sha256sum_k0_answers () {
	./out/host-${HOST_ARCH}/${STAGE0_HOST}/bin/sha256sum -c "k0-${ARCH}.answers"
}

run_make_k0 () {
	if ! {
		./out/host-${HOST_ARCH}/${STAGE0_HOST}/bin/mkdir -p "$SH_ROOT/out/k0-${ARCH}" &&
		./out/host-${HOST_ARCH}/bin/bh0x "$SH_ROOT/out/k0-${ARCH}.img" "$SH_ROOT/out/k0-${ARCH}"
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
