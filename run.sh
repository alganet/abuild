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
SORT="${SORT:-$(command -v sort)}"
GZIP="${GZIP:-$(command -v gzip)}"
TAR="${TAR:-$(command -v tar)}"
MAKE="${MAKE:-$(command -v make)}"
UNZIP="${UNZIP:-$(command -v unzip)}"
GIT="${GIT:-$(command -v git)}"
TIMEOUT="${TIMEOUT:-$(command -v timeout)}"
TEE="${TEE:-$(command -v tee)}"
GREP="${GREP:-$(command -v grep)}"

# Every tool must resolve to an absolute, executable path BEFORE `PATH=`
# clears the search path below. command -v returns empty when a tool is
# missing; a caller env may also override e.g. SORT=sort (a bare name that
# stops resolving once PATH is empty). Either way an unusable $SORT/$FIND
# collapses a `find | LC_ALL=C $SORT | tar --files-from=-` pipeline (and the
# FAT find loops) into an EMPTY result with no non-zero exit set -e can see,
# shipping a silently-truncated mes tarball / boot image. Fail loudly here.
for _t in "WGET=$WGET" "MKDIR=$MKDIR" "RM=$RM" "CP=$CP" "FIND=$FIND" \
          "SORT=$SORT" "GZIP=$GZIP" "TAR=$TAR" "MAKE=$MAKE" "UNZIP=$UNZIP" \
          "GIT=$GIT" "TIMEOUT=$TIMEOUT" "TEE=$TEE" "GREP=$GREP"
do
	_tn="${_t%%=*}"; _tv="${_t#*=}"
	case "$_tv" in
		/*) test -x "$_tv" || { echo "fatal: tool '$_tn' resolved to '$_tv' which is not executable" >&2; exit 1 ;} ;;
		*)  echo "fatal: tool '$_tn' did not resolve to an absolute path (got '${_tv:-<empty>}'); PATH=$PATH" >&2; exit 1 ;;
	esac
done

set -eufx
PATH=

SH_FILE="$PWD/$0"
SH_ROOT="${SH_FILE%\/*}"
cd "$SH_ROOT"

. "$SH_ROOT/distfiles.sh"

# apply_overlay <name> <dest1> [<dest2> ...]
# Copies overlay-<name>/. into each existing destination, excluding .git and
# gitignored files via overlay_tracked (from distfiles.sh). Sibling at
# ../<name>/ wins over distfiles/overlay-<name>/. No-op if neither source
# exists (e.g., overlay branch is "" and no sibling).
apply_overlay () {
	_name="$1"; shift
	if   test -d "${SH_ROOT}/../${_name}"
	then _src="${SH_ROOT}/../${_name}"
	elif test -d "${SH_ROOT}/distfiles/overlay-${_name}"
	then _src="${SH_ROOT}/distfiles/overlay-${_name}"
	else return 0
	fi
	for _dst
	do test -d "${_dst}" && overlay_tracked "${_src}" "${_dst}"
	done
}

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
	
	# Copy stage0-uefi (distfiles.sh has already resolved alganet fork /
	# sibling / upstream stikonas into distfiles/stage0-uefi-1.9.1/).
	$MKDIR -p out/host-${HOST_ARCH}/stage0-uefi
	$CP -Rf distfiles/stage0-uefi-1.9.1/. out/host-${HOST_ARCH}/stage0-uefi/

	# Apply fork overlays onto stage0-posix's vendored copies. Sibling
	# checkouts at ../<name>/ override fetched forks; empty BRANCH no-ops.
	apply_overlay M2libc \
		"out/host-${HOST_ARCH}/M2libc" \
		"out/host-${HOST_ARCH}/M2-Planet/M2libc" \
		"out/host-${HOST_ARCH}/M2-Mesoplanet/M2libc" \
		"out/host-${HOST_ARCH}/mescc-tools/M2libc" \
		"out/host-${HOST_ARCH}/mescc-tools-extra/M2libc" \
		"out/host-${HOST_ARCH}/stage0-uefi/M2libc"
	apply_overlay bootstrap-seeds \
		"out/host-${HOST_ARCH}/bootstrap-seeds" \
		"out/host-${HOST_ARCH}/stage0-uefi/bootstrap-seeds"
	apply_overlay builder-hex0-arch \
		"out/host-${HOST_ARCH}/builder-hex0-arch"

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

	# Snapshot the clean (non-UEFI-overlaid) state of the shared source dirs
	# so run_make_k0_img can restore from it before every build. Without this,
	# a UEFI variant's overlay (which replaces M2libc, M2-Planet, ..., and
	# kaem.${ARCH}/${ARCH}.answers) leaks into any subsequent non-UEFI variant
	# of the same ARCH that gets built in the same out/ tree. Idempotent:
	# re-snapshots every run_make_host so the snapshot reflects the freshest
	# distfiles + apply_overlay state.
	cd "$SH_ROOT/out/host-${HOST_ARCH}"
	$RM -rf ./.snapshot
	$MKDIR -p ./.snapshot
	for _src in M2libc M2-Planet M2-Mesoplanet mescc-tools mescc-tools-extra \
	            x86 amd64 aarch64 riscv64 riscv32 armv7l AMD64 AArch64
	do
		test -d "./${_src}" && $CP -Rf "./${_src}" "./.snapshot/${_src}"
	done
	# kaem.${ARCH} and ${ARCH}.answers (e.g. kaem.x86, riscv64.answers): glob
	# would be simplest but `set -f` is active so we enumerate via find.
	$FIND . -maxdepth 1 -type f \( -name 'kaem.*' -o -name '*.answers' \) \
		-exec $CP -f {} ./.snapshot/ \;
	cd "$SH_ROOT"
}

run_make_k0_img () {
	if ! cd "$SH_ROOT/out/host-${HOST_ARCH}"
	then echo "info: run make_host first." && return 1
	fi

	# Skip rebuild when the per-(arch,board) image already exists. UEFI also
	# requires the FAT32 wrapper. The image file name encodes BOARD so two
	# variants of the same ARCH can coexist in out/ without overwriting.
	# CI's reseal-test job depends on the cached image surviving across
	# steps, so we don't invalidate on mtime. Local development that
	# changes tools/ or scripts/ should set FORCE_REBUILD=yes (or rm
	# out/k0-*.img) to bypass.
	_need_build=1
	if test -f "$SH_ROOT/out/k0-${ARCH}-${BOARD}.img" && \
	   test "${FORCE_REBUILD:-no}" != "yes"
	then
		case "$BOARD" in
			uefi) test -f "$SH_ROOT/out/k0-${ARCH}-${BOARD}-fat.img" && _need_build=0 ;;
			*)    _need_build=0 ;;
		esac
	fi
	if test "$_need_build" -eq 1
	then
		# Restore make_host's clean state of the shared dirs (M2libc, M2-Planet,
		# M2-Mesoplanet, mescc-tools, mescc-tools-extra, every ${ARCH}/, every
		# kaem.${ARCH}). The UEFI overlay below replaces those with stage0-uefi's
		# versions; without this restore, a subsequent non-UEFI variant of the
		# same ARCH (or any ARCH whose shared dirs were UEFI-overwritten) would
		# putfile the wrong sources into the bh0 image. Snapshot is a no-op
		# from a cold checkout (see end of run_make_host).
		if test -d ./.snapshot
		then
			$RM -rf ./M2libc ./M2-Planet ./M2-Mesoplanet ./mescc-tools ./mescc-tools-extra
			$RM -rf ./EFI ./bootstrap-seeds/UEFI ./posix-runner
			$CP -Rf ./.snapshot/M2libc ./M2libc
			$CP -Rf ./.snapshot/M2-Planet ./M2-Planet
			$CP -Rf ./.snapshot/M2-Mesoplanet ./M2-Mesoplanet
			$CP -Rf ./.snapshot/mescc-tools ./mescc-tools
			$CP -Rf ./.snapshot/mescc-tools-extra ./mescc-tools-extra
			for _arch in x86 amd64 aarch64 riscv64 riscv32 armv7l AMD64 AArch64
			do
				if test -d "./.snapshot/${_arch}"
				then
					$RM -rf "./${_arch}"
					$CP -Rf "./.snapshot/${_arch}" "./${_arch}"
				fi
			done
			# `set -f` is active so we can't glob — use find to enumerate.
			$FIND ./.snapshot -maxdepth 1 -type f \( -name 'kaem.*' -o -name '*.answers' \) \
				-exec $CP -f {} ./ \;
		fi

		# Compute board-dependent variables
		# Resolve all per-(arch,board) tunables in a single pass so the
		# arch-specific column is easy to audit.
		case "$ARCH" in
			x86)     _stage0_host=x86;      _mes_cpu=x86;     _mes_cc_cpu=i386;   _mes_blood_elf=--little-endian; _mes_base=0x08048000 ;;
			amd64)   _stage0_host=AMD64;    _mes_cpu=x86_64;  _mes_cc_cpu=x86_64; _mes_blood_elf=--64;            _mes_base=0x0600000  ;;
			aarch64) _stage0_host=AArch64;  _mes_cpu=aarch64; _mes_cc_cpu=aarch64;_mes_blood_elf=--64;            _mes_base=0x0600000  ;;
			riscv64) _stage0_host=riscv64;  _mes_cpu=riscv64; _mes_cc_cpu=riscv64;_mes_blood_elf=--64;            _mes_base=0x0600000  ;;
			*)       echo "error: unsupported ARCH=$ARCH" >&2; return 1 ;;
		esac
		case "$BOARD" in
			uefi) _exe_suffix=.efi; _operating_system=UEFI  ;;
			*)    _exe_suffix=;     _operating_system=Linux ;;
		esac

		# Generate env preamble for host-side kaem execution
		# Host always runs Linux with bare binary names, regardless of target board
		printf 'set -a\nARCH="%s"\nHOST_ARCH="%s"\nSTAGE0_HOST="%s"\nBOARD="%s"\nEXE_SUFFIX=""\nOPERATING_SYSTEM="Linux"\n' "$ARCH" "$HOST_ARCH" "$STAGE0_HOST" "$BOARD" > ./scripts/env.kaem
		printf '# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>\n# SPDX-License-Identifier: GPL-3.0-or-later\n\nset -a\nARCH="%s"\nHOST_ARCH="%s"\nSTAGE0_HOST="%s"\nBOARD="%s"\nSTAGE0_ARCH="%s"\nMES_CPU="%s"\nMES_CC_CPU="%s"\nMES_BLOOD_ELF_FLAG="%s"\nMES_BASE_ADDRESS="%s"\nEXE_SUFFIX="%s"\nOPERATING_SYSTEM="%s"\n' "$ARCH" "$ARCH" "$_stage0_host" "$BOARD" "$ARCH" "$_mes_cpu" "$_mes_cc_cpu" "$_mes_blood_elf" "$_mes_base" "$_exe_suffix" "$_operating_system" > "./scripts/env.${ARCH}.kaem"

		# Concatenate env preamble + seal-break into pre-build.kaem
		# UEFI boards use dd-based seal-break (catm doesn't close file handles)
		if test "${FORCE_FAIL:-no}" = "yes"
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
		if test "${BOARD}" = "uefi"
		then
			_uefi_src="./stage0-uefi"
			# Replace shared sources with stage0-uefi's pinned versions
			$RM -rf ./M2libc ./M2-Planet ./M2-Mesoplanet ./mescc-tools ./mescc-tools-extra
			$CP -Rf "${_uefi_src}/M2libc" ./M2libc
			$CP -Rf "${_uefi_src}/M2-Planet" ./M2-Planet
			$CP -Rf "${_uefi_src}/M2-Mesoplanet" ./M2-Mesoplanet
			$CP -Rf "${_uefi_src}/mescc-tools" ./mescc-tools
			$CP -Rf "${_uefi_src}/mescc-tools-extra" ./mescc-tools-extra
			# stage0-uefi arch sources (merge into existing posix dir using cp -a + trailing /)
			$CP -Rf "${_uefi_src}/${ARCH}/." "./${ARCH}/"
			$CP "${_uefi_src}/kaem.${ARCH}" "./kaem.${ARCH}"
			$CP "${_uefi_src}/${ARCH}.answers" "./${ARCH}.answers"
			# UEFI boot entry (architecture-specific name per UEFI spec)
			case "$ARCH" in
				amd64)   _uefi_boot_name=BOOTX64.EFI    ;;
				aarch64) _uefi_boot_name=BOOTAA64.EFI   ;;
				riscv64) _uefi_boot_name=BOOTRISCV64.EFI ;;
				*)       _uefi_boot_name=BOOT.EFI       ;;
			esac
			$MKDIR -p ./EFI/BOOT
			$CP "${_uefi_src}/bootstrap-seeds/UEFI/${ARCH}/kaem-optional-seed.efi" "./EFI/BOOT/${_uefi_boot_name}"
			$MKDIR -p "./bootstrap-seeds/UEFI/${ARCH}"
			$CP -Rf "${_uefi_src}/bootstrap-seeds/UEFI/${ARCH}/." "./bootstrap-seeds/UEFI/${ARCH}/"
			# posix-runner (whole dir, so trap-entry-${ARCH}.M1 etc. are picked up)
			$MKDIR -p ./posix-runner
			$CP -Rf "${_uefi_src}/posix-runner/." "./posix-runner/"
		fi

		# Concatenate env preamble + k0.kaem for host-side execution
		./${STAGE0_HOST}/bin/catm ./scripts/k0-run.kaem ./scripts/env.kaem ./scripts/k0.kaem
		./${STAGE0_HOST}/bin/wrap /${STAGE0_HOST}/bin/kaem --verbose --strict --file /scripts/k0-run.kaem
		./${STAGE0_HOST}/bin/cp ./dev/hda "$SH_ROOT/out/k0-${ARCH}-${BOARD}.img"

		# For UEFI: create FAT32 disk from the bh0 image contents + /k0.img
		# Extract bh0 → out/k0-${ARCH}-${BOARD}/, create FAT32 from that tree
		if test "${BOARD}" = "uefi"
		then
			_fat="$SH_ROOT/out/k0-${ARCH}-${BOARD}-fat.img"
			_tree="$SH_ROOT/out/k0-${ARCH}-${BOARD}"
			./bin/bh0x "$SH_ROOT/out/k0-${ARCH}-${BOARD}.img" "$_tree" \
				|| { echo "bh0x failed for $_tree" >&2; exit 1; }
			./bin/mkfat "$_fat" 350 \
				|| { echo "mkfat failed for $_fat" >&2; exit 1; }
			# Sort under LC_ALL=C so FAT directory entry order is
			# host-independent. Without the sort, readdir() order
			# (filesystem-hashed on ext4) leaks into the image bytes.
			#
			# Spool the listings to temp files and iterate with `< file`
			# rather than `find | sort | while`: a while loop on the right
			# of a pipe runs in a subshell, so a failing fatput there cannot
			# be detected (there is no `set -e` here) and a half-populated
			# image would be sealed silently. Each fatput rc is checked so a
			# failure aborts the build instead.
			_dirlist="$SH_ROOT/out/.fat-dirs"
			_filelist="$SH_ROOT/out/.fat-files"
			$FIND "$_tree" -type d | LC_ALL=C $SORT > "$_dirlist"
			$FIND "$_tree" -type f | LC_ALL=C $SORT > "$_filelist"
			while IFS= read -r _dir; do
				_rel="${_dir#${_tree}}"
				if test -n "$_rel"; then
					./bin/fatput "$_fat" "$_rel" \
						|| { echo "fatput failed: dir $_rel" >&2; exit 1; }
				fi
			done < "$_dirlist"
			while IFS= read -r _file; do
				_rel="${_file#${_tree}}"
				./bin/fatput "$_fat" "$_rel" "$_file" \
					|| { echo "fatput failed: file $_rel" >&2; exit 1; }
			done < "$_filelist"
			$RM -f "$_dirlist" "$_filelist"
			./bin/fatput "$_fat" /k0.img "$SH_ROOT/out/k0-${ARCH}-${BOARD}.img" \
				|| { echo "fatput failed: /k0.img" >&2; exit 1; }
			# startup.nsh (riscv64 EDK2 doesn't auto-load default boot path)
			_startup="$SH_ROOT/out/startup.nsh"
			printf 'FS0:\ncd \\\nEFI\\BOOT\\%s\n' "${_uefi_boot_name}" > "${_startup}"
			./bin/fatput "$_fat" /startup.nsh "${_startup}" \
				|| { echo "fatput failed: /startup.nsh" >&2; exit 1; }
		fi
	fi

	cd "$SH_ROOT"
}

run_boot_k0_img () {
	_img="out/k0-${ARCH}-${BOARD}.img"
	_fat="out/k0-${ARCH}-${BOARD}-fat.img"
	_qlog="out/k0-${ARCH}-${BOARD}.qemu.log"

	# QEMU's exit code is unreliable here: with --no-reboot, qemu exits 0 when
	# the guest "reboots" (i.e. an in-image kaem script aborts and stage2
	# returns), so the only trustworthy success signal is the
	# "Hello from inside the ${ARCH} image" sentinel printed by k1.kaem /
	# after-uefi.kaem. We tee QEMU stdout/stderr to ${_qlog} and grep for it
	# after the guest exits.
	case "$ARCH" in
		x86)
			$QEMU \
				--enable-kvm \
				-m 2G \
				-smp 2 \
				-nographic \
				-machine kernel-irqchip=split \
				-drive file="$_img",format=raw \
				--no-reboot 2>&1 | $TEE "$_qlog"
			;;
		riscv64)
			case "$BOARD" in
				virt)
					$QEMU \
						-machine virt \
						-m 2G \
						-nographic \
						-kernel "${SH_ROOT}/out/host-${HOST_ARCH}/bootstrap-seeds/NATIVE/${ARCH}/builder-hex0-${ARCH}-stage1-${BOARD}.img" \
						-drive file="$_img",format=raw,if=none,id=hd0 \
						-device virtio-blk-device,drive=hd0 \
						--no-reboot 2>&1 | $TEE "$_qlog"
					;;
				sifive_u)
					$QEMU \
						-machine sifive_u \
						-m 2G \
						-nographic \
						-kernel "${SH_ROOT}/out/host-${HOST_ARCH}/bootstrap-seeds/NATIVE/${ARCH}/builder-hex0-${ARCH}-stage1-${BOARD}.img" \
						-drive file="$_img",format=raw,if=sd \
						--no-reboot 2>&1 | $TEE "$_qlog"
					;;
				uefi)
					OVMF_RISCV64_CODE="${OVMF_RISCV64_CODE:-/usr/share/qemu-efi-riscv64/RISCV_VIRT_CODE.fd}"
					OVMF_RISCV64_VARS="${OVMF_RISCV64_VARS:-/usr/share/qemu-efi-riscv64/RISCV_VIRT_VARS.fd}"
					_rvars="out/k0-${ARCH}-${BOARD}-vars.fd"
					$CP "${OVMF_RISCV64_VARS}" "${_rvars}"
					$QEMU \
						-machine virt \
						-m 4G \
						-nographic \
						-drive if=pflash,format=raw,unit=0,file=${OVMF_RISCV64_CODE},readonly=on \
						-drive if=pflash,format=raw,unit=1,file=${_rvars} \
						-device nvme,serial=deadbeef,drive=hd0 \
						-drive file="$_fat",format=raw,if=none,id=hd0 \
						--no-reboot 2>&1 | $TEE "$_qlog"
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
					$QEMU \
						-cpu qemu64 -net none \
						-m 4G \
						--enable-kvm \
						-nographic \
						-drive if=pflash,format=raw,unit=0,file=${OVMF},readonly=on \
						-drive if=ide,format=raw,file="$_fat" \
						--no-reboot 2>&1 | $TEE "$_qlog"
					;;
				*)
					echo "error: unsupported BOARD=$BOARD for ARCH=$ARCH" && exit 1
					;;
			esac
			;;
		aarch64)
			case "$BOARD" in
				virt)
					$QEMU \
						-machine virt -cpu cortex-a53 \
						-m 2G \
						-nographic \
						-kernel "${SH_ROOT}/out/host-${HOST_ARCH}/bootstrap-seeds/NATIVE/${ARCH}/builder-hex0-${ARCH}-stage1-${BOARD}.img" \
						-drive file="$_img",format=raw,if=none,id=hd0 \
						-device virtio-blk-device,drive=hd0 \
						--no-reboot 2>&1 | $TEE "$_qlog"
					;;
				raspi3b)
					$QEMU \
						-machine raspi3b \
						-serial mon:stdio \
						-nographic \
						-kernel "${SH_ROOT}/out/host-${HOST_ARCH}/bootstrap-seeds/NATIVE/${ARCH}/builder-hex0-${ARCH}-stage1-${BOARD}.img" \
						-drive file="$_img",if=sd,format=raw \
						--no-reboot 2>&1 | $TEE "$_qlog"
					;;
				*)
					echo "error: unsupported BOARD=$BOARD for ARCH=$ARCH" && exit 1
					;;
			esac
			;;
	esac

	# Trust the in-image sentinel. If the guest didn't reach the Hello echo,
	# the build failed even if QEMU exited 0. No `^...$` anchors because QEMU
	# serial emits CRLF; the message is unique enough.
	if ! $GREP -q "Hello from inside the ${ARCH} image" "$_qlog"
	then
		echo "error: in-image build did not reach 'Hello from inside the ${ARCH} image' marker" >&2
		echo "info: see ${_qlog} for QEMU output" >&2
		return 1
	fi

	# UEFI: extract post-boot k0.img from the FAT32 wrapper now that we know
	# the guest succeeded (re-extracting after a failed boot would seal a
	# broken image).
	if test "${BOARD}" = "uefi"
	then
		./out/host-${HOST_ARCH}/bin/fatget "$_fat" /k0.img "$_img"
	fi
}

run_sha256sum_k0_answers () {
	# Seal post-boot: some boards (e.g. aarch64-raspi3b) write to the disk
	# during boot, so capturing the seal here covers full end-to-end
	# reproducibility. For boards whose boot is byte-identical to build,
	# this collapses to the same hash anyway.
	#
	# When the answers file is missing we GENERATE rather than verify --
	# this is how CI seeds new variants and how a developer rebases the
	# expected hash after intentional changes. Print a loud notice so
	# "I accidentally deleted the file" is never silently rubber-stamped.
	if ! test -f "k0-${ARCH}-${BOARD}.answers"
	then
		echo "notice: k0-${ARCH}-${BOARD}.answers missing -- generating fresh seal (re-run will verify)." >&2
		./out/host-${HOST_ARCH}/${STAGE0_HOST}/bin/sha256sum -o "k0-${ARCH}-${BOARD}.answers" "out/k0-${ARCH}-${BOARD}.img"
	fi
	./out/host-${HOST_ARCH}/${STAGE0_HOST}/bin/sha256sum -c "k0-${ARCH}-${BOARD}.answers"
}

run_make_k0 () {
	if ! {
		./out/host-${HOST_ARCH}/${STAGE0_HOST}/bin/mkdir -p "$SH_ROOT/out/k0-${ARCH}-${BOARD}" &&
		./out/host-${HOST_ARCH}/bin/bh0x "$SH_ROOT/out/k0-${ARCH}-${BOARD}.img" "$SH_ROOT/out/k0-${ARCH}-${BOARD}"
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

# Run each requested target as a plain command so `set -e` stays in force
# INSIDE the run_* function. Calling it on the left of `&&` (the old
# `"run_${1}" && shift || exit`) put the function in a condition context,
# which POSIX suppresses set -e for throughout the whole call tree -- a hard
# failure mid-build (e.g. kaem "ABORTING HARD") was swallowed, the function
# returned its last command's status (often 0), and the breakage surfaced far
# downstream as a confusing "cp: out/k0-*.img: No such file". A bare call lets
# set -e abort at the real point of failure.
for _t in "$@"
do "run_${_t}"
done
