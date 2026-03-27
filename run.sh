#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

ARCH="${ARCH:-x86}"

# Default board per architecture (x86 only has bios, others default to virt)
case "$ARCH" in
	x86)    BOARD="${BOARD:-bios}" ;;
	amd64)  BOARD="${BOARD:-uefi}" ;;
	*)      BOARD="${BOARD:-virt}" ;;
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
	amd64)   STAGE0_HOST="AMD64" ;;
	*)       STAGE0_HOST="$HOST_ARCH" ;;
esac

case "$ARCH" in
	x86)     QEMU="${QEMU:-$(command -v qemu-system-i386)}" ;;
	amd64)   QEMU="${QEMU:-$(command -v qemu-system-x86_64)}" ;;
	riscv64) QEMU="${QEMU:-$(command -v qemu-system-riscv64)}" ;;
	aarch64) QEMU="${QEMU:-$(command -v qemu-system-aarch64)}" ;;
	*)       echo "error: unsupported ARCH=$ARCH" && exit 1 ;;
esac

WGET="${WGET:-$(command -v wget)}"
MKDIR="${MKDIR:-$(command -v mkdir)}"
RM="${RM:-$(command -v rm)}"
CP="${CP:-$(command -v cp)}"
FIND="${FIND:-$(command -v find)}"
GZIP="${GZIP:-$(command -v gzip)}"
TAR="${TAR:-$(command -v tar)}"
MAKE="${MAKE:-$(command -v make)}"
UNZIP="${UNZIP:-$(command -v unzip)}"
GIT="${GIT:-$(command -v git)}"
TIMEOUT="${TIMEOUT:-$(command -v timeout)}"

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
	
	# Copy stage0-uefi (cloned with its own submodules at pinned versions)
	if ! test -d out/host-${HOST_ARCH}/stage0-uefi
	then
		$CP -Rf distfiles/stage0-uefi-1.9.1 out/host-${HOST_ARCH}/stage0-uefi
	fi

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

	# Compile host tools (needed by make_k0_img and boot_k0_img)
	if ! test -f ./out/host-${HOST_ARCH}/bin/fatget
	then
		cd "$SH_ROOT/out/host-${HOST_ARCH}"
		$MKDIR -p bin
		PATH="./${STAGE0_HOST}/bin" ./${STAGE0_HOST}/bin/M2-Mesoplanet --architecture ${HOST_ARCH} -f tools/wc.c -o bin/wc
		PATH="./${STAGE0_HOST}/bin" ./${STAGE0_HOST}/bin/M2-Mesoplanet --architecture ${HOST_ARCH} -f tools/dd.c -o bin/dd
		PATH="./${STAGE0_HOST}/bin" ./${STAGE0_HOST}/bin/M2-Mesoplanet --architecture ${HOST_ARCH} -f tools/bh0x.c -o bin/bh0x
		PATH="./${STAGE0_HOST}/bin" ./${STAGE0_HOST}/bin/M2-Mesoplanet --architecture ${HOST_ARCH} -f tools/mkfat.c -o bin/mkfat
		PATH="./${STAGE0_HOST}/bin" ./${STAGE0_HOST}/bin/M2-Mesoplanet --architecture ${HOST_ARCH} -f tools/fatput.c -o bin/fatput
		PATH="./${STAGE0_HOST}/bin" ./${STAGE0_HOST}/bin/M2-Mesoplanet --architecture ${HOST_ARCH} -f tools/fatget.c -o bin/fatget
		PATH="./${STAGE0_HOST}/bin" ./${STAGE0_HOST}/bin/M2-Mesoplanet --architecture ${HOST_ARCH} -f tools/bh0header.c -o bin/bh0header
		cd "$SH_ROOT"
	fi
}

run_make_k0_img () {
	if ! cd "$SH_ROOT/out/host-${HOST_ARCH}"
	then echo "info: run make_host first." && return 1
	fi

	if ! test -f "../k0-${ARCH}.img"
	then
		# Compute board-dependent variables
		_stage0_host="$( case "$ARCH" in aarch64) echo AArch64 ;; amd64) echo AMD64 ;; *) echo "$ARCH" ;; esac )"
		_mes_cpu="$( case "$ARCH" in amd64) echo x86_64 ;; *) echo "$ARCH" ;; esac )"
		_mes_cc_cpu="$( case "$ARCH" in x86) echo i386 ;; amd64) echo x86_64 ;; *) echo "$ARCH" ;; esac )"
		_mes_blood_elf="$( case "$ARCH" in x86) echo "--little-endian" ;; *) echo "--64" ;; esac )"
		_mes_base="$( case "$ARCH" in x86) echo "0x1000000" ;; *) echo "0x0600000" ;; esac )"
		_exe_suffix="$( case "$BOARD" in uefi) echo ".efi" ;; *) echo "" ;; esac )"
		_operating_system="$( case "$BOARD" in uefi) echo "UEFI" ;; *) echo "Linux" ;; esac )"

		# Generate env preamble for host-side kaem execution
		# Host always runs Linux with bare binary names, regardless of target board
		printf 'set -a\nARCH="%s"\nHOST_ARCH="%s"\nSTAGE0_HOST="%s"\nBOARD="%s"\nEXE_SUFFIX=""\nOPERATING_SYSTEM="Linux"\n' "$ARCH" "$HOST_ARCH" "$STAGE0_HOST" "$BOARD" > ./scripts/env.kaem
		printf '# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>\n# SPDX-License-Identifier: GPL-3.0-or-later\n\nset -a\nARCH="%s"\nHOST_ARCH="%s"\nSTAGE0_HOST="%s"\nBOARD="%s"\nSTAGE0_ARCH="%s"\nMES_CPU="%s"\nMES_CC_CPU="%s"\nMES_BLOOD_ELF_FLAG="%s"\nMES_BASE_ADDRESS="%s"\nEXE_SUFFIX="%s"\nOPERATING_SYSTEM="%s"\n' "$ARCH" "$ARCH" "$_stage0_host" "$BOARD" "$ARCH" "$_mes_cpu" "$_mes_cc_cpu" "$_mes_blood_elf" "$_mes_base" "$_exe_suffix" "$_operating_system" > "./scripts/env.${ARCH}.kaem"

		# Concatenate env preamble + seal-break into pre-build.kaem
		# UEFI boards use dd-based seal-break (catm doesn't close file handles)
		if ./${STAGE0_HOST}/bin/match "yes" "${FORCE_FAIL:-no}"
		then
			case "$BOARD" in
				uefi) ./${STAGE0_HOST}/bin/catm ./scripts/pre-build.kaem ./scripts/env.${ARCH}.kaem ./scripts/seal-break-uefi.kaem ;;
				*)    ./${STAGE0_HOST}/bin/catm ./scripts/pre-build.kaem ./scripts/env.${ARCH}.kaem ./scripts/seal-break.kaem ;;
			esac
		else ./${STAGE0_HOST}/bin/catm ./scripts/pre-build.kaem ./scripts/env.${ARCH}.kaem ./scripts/noop.kaem
		fi

		# Assemble swappable scripts
		./${STAGE0_HOST}/bin/catm ./scripts/putfile.kaem ./scripts/putfile-bh0.kaem
		./${STAGE0_HOST}/bin/catm ./scripts/putdir.kaem  ./scripts/putdir-bh0.kaem
		case "$BOARD" in
			uefi)
				./${STAGE0_HOST}/bin/catm ./scripts/k0-boot.kaem ./scripts/after-uefi.kaem
				;;
			*)
				./${STAGE0_HOST}/bin/catm ./scripts/k0-boot.kaem ./scripts/k1.kaem
				;;
		esac

		# For UEFI: copy stage0-uefi files into wrap sandbox so k0.kaem can putfile them
		if ./${STAGE0_HOST}/bin/match "uefi" "${BOARD}"
		then
			_uefi_src="./stage0-uefi"
			# Replace shared sources with stage0-uefi's pinned versions
			$RM -rf ./M2libc ./M2-Planet ./M2-Mesoplanet ./mescc-tools ./mescc-tools-extra
			$CP -Rf "${_uefi_src}/M2libc" ./M2libc
			$CP -Rf "${_uefi_src}/M2-Planet" ./M2-Planet
			$CP -Rf "${_uefi_src}/M2-Mesoplanet" ./M2-Mesoplanet
			$CP -Rf "${_uefi_src}/mescc-tools" ./mescc-tools
			$CP -Rf "${_uefi_src}/mescc-tools-extra" ./mescc-tools-extra
			# stage0-uefi arch sources
			$CP -Rf "${_uefi_src}/${ARCH}" "./${ARCH}"
			$CP "${_uefi_src}/kaem.${ARCH}" "./kaem.${ARCH}"
			$CP "${_uefi_src}/${ARCH}.answers" "./${ARCH}.answers"
			# UEFI boot entry
			$MKDIR -p ./EFI/BOOT
			$CP "./bootstrap-seeds/UEFI/${ARCH}/kaem-optional-seed.efi" "./EFI/BOOT/BOOTX64.EFI"
			# posix-runner
			$MKDIR -p ./posix-runner
			$CP "${_uefi_src}/posix-runner/posix-runner.c" "./posix-runner/posix-runner.c"
		fi

		# Concatenate env preamble + k0.kaem for host-side execution
		./${STAGE0_HOST}/bin/catm ./scripts/k0-run.kaem ./scripts/env.kaem ./scripts/k0.kaem
		./${STAGE0_HOST}/bin/wrap /${STAGE0_HOST}/bin/kaem --verbose --strict --file /scripts/k0-run.kaem
		./${STAGE0_HOST}/bin/cp ./dev/hda "$SH_ROOT/out/k0-${ARCH}.img"

		# For UEFI: create FAT32 disk from the bh0 image contents + /k0.img
		# Extract bh0 → out/k0-amd64/, create FAT32 from that tree
		if ./${STAGE0_HOST}/bin/match "uefi" "${BOARD}"
		then
			_fat="$SH_ROOT/out/k0-${ARCH}-fat.img"
			_tree="$SH_ROOT/out/k0-${ARCH}"
			./bin/bh0x "$SH_ROOT/out/k0-${ARCH}.img" "$_tree"
			./bin/mkfat "$_fat" 350
			$FIND "$_tree" -type d | while read _dir; do
				_rel="${_dir#${_tree}}"
				test -n "$_rel" && ./bin/fatput "$_fat" "$_rel"
			done
			$FIND "$_tree" -type f | while read _file; do
				_rel="${_file#${_tree}}"
				./bin/fatput "$_fat" "$_rel" "$_file"
			done
			./bin/fatput "$_fat" /k0.img "$SH_ROOT/out/k0-${ARCH}.img"
		fi
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
		amd64)
			case "$BOARD" in
				uefi)
					OVMF="${OVMF:-/usr/share/OVMF/OVMF_CODE_4M.fd}"
					if ! $QEMU \
						-cpu qemu64 -net none \
						-m 4G \
						--enable-kvm \
						-nographic \
						-drive if=pflash,format=raw,unit=0,file=${OVMF},readonly=on \
						-drive if=ide,format=raw,file="out/k0-${ARCH}-fat.img" \
						--no-reboot
					then
						echo "info: run make_k0_img first." && return 1
					fi
					# Extract updated bh0 image from FAT32 container
					./out/host-${HOST_ARCH}/bin/fatget "out/k0-${ARCH}-fat.img" /k0.img "out/k0-${ARCH}.img"
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
