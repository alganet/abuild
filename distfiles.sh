#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

WGET="${WGET:-$(command -v wget)}"
MKDIR="${MKDIR:-$(command -v mkdir)}"
GIT="${GIT:-$(command -v git)}"
TAR="${TAR:-$(command -v tar)}"
GZIP="${GZIP:-$(command -v gzip)}"
RM="${RM:-$(command -v rm)}"
CP="${CP:-$(command -v cp)}"

set -eufx
PATH=

SH_FILE="$PWD/$0"
SH_ROOT="${SH_FILE%\/*}"
cd "$SH_ROOT"

# NOTE: this file is used to check if dependencies changed in CI
# SEE: .github/workflows/build.yml

# Fork manifest. Replacement forks (mes, stage0-uefi) replace the upstream
# source entirely; overlay forks (M2libc, bootstrap-seeds) are consumed by
# apply_overlay in run.sh. Set <NAME>_BRANCH="" to disable a fork: replacement
# falls back to the original upstream, overlay no-ops. A sibling checkout at
# ../<name>/ overrides the fetched fork unconditionally.
MES_REPO="${MES_REPO-https://github.com/alganet/mes.git}"
MES_BRANCH="${MES_BRANCH-aarch64}"
STAGE0_UEFI_REPO="${STAGE0_UEFI_REPO-https://github.com/alganet/stage0-uefi.git}"
STAGE0_UEFI_BRANCH="${STAGE0_UEFI_BRANCH-riscv64}"
M2LIBC_REPO="${M2LIBC_REPO-https://github.com/alganet/M2libc.git}"
M2LIBC_BRANCH="${M2LIBC_BRANCH-riscv64-uefi}"
BOOTSTRAP_SEEDS_REPO="${BOOTSTRAP_SEEDS_REPO-https://github.com/alganet/bootstrap-seeds.git}"
BOOTSTRAP_SEEDS_BRANCH="${BOOTSTRAP_SEEDS_BRANCH-stage0-uefi}"
BUILDER_HEX0_ARCH_REPO="${BUILDER_HEX0_ARCH_REPO-https://github.com/alganet/builder-hex0-arch.git}"
BUILDER_HEX0_ARCH_BRANCH="${BUILDER_HEX0_ARCH_BRANCH-brk_cap}"

$MKDIR -p distfiles

# Copy <src>/. to <dst>/, contributing the same bytes a github source tarball
# would. Plain `cp -Rf` leaks every locally-built artifact in <src> (e.g.
# *.bin, *.o, __pycache__) into the destination — those are invisible to
# `git status` but still change the bytes downstream tools see. When <src> is
# a git working tree, we enumerate tracked paths via `git ls-files
# --recurse-submodules` (faithful to git's semantics: tracked files override
# .gitignore, submodule contents included). Plain directories (e.g. an
# already-extracted github tarball) just exclude .git via tar. <dst> is
# created if missing.
overlay_tracked () {
	_src="$1"; _dst="$2"
	_tmp="${SH_ROOT}/distfiles/.overlay-tmp.tar"
	$MKDIR -p "${_dst}"
	if test -e "${_src}/.git"
	then
		(cd "${_src}" && PATH=/usr/bin:/bin $GIT ls-files -z --recurse-submodules \
			| $TAR --create --null --no-recursion --files-from=- \
				--file="${_tmp}")
	else
		# Plain directory (e.g. an extracted github tarball). Exclude only
		# the .git directory; .gitignore / .gitattributes / .gitmodules are
		# tracked files in many repos and `--exclude-vcs` would wrongly drop
		# them, diverging from the git working-tree branch above. `tar
		# --sort=name` gives a filesystem-independent order without a
		# find|sort|tar pipeline: in a pipeline an unresolved $FIND/$SORT
		# fails mid-pipe, set -e cannot see it, and `tar --files-from=-`
		# silently produces an EMPTY archive (the cause of the in-image
		# "mes tarball has 1 member" failure). A direct tar fails loudly
		# under set -e instead.
		(cd "${_src}" && $TAR --create --sort=name \
			--exclude='.git' --exclude='./.git/*' \
			--file="${_tmp}" .)
	fi
	(cd "${_dst}" && $TAR --extract --file="${_tmp}")
	$RM -f "${_tmp}"
}

# Deterministic re-tar of <src>/. into <dest> with top-level dir <topname>.
# Same content -> byte-identical tarball.
repackage_to_tarball () {
	_src="$1"; _dest="$2"; _topname="$3"
	_stage="${SH_ROOT}/distfiles/.repackage-stage"
	$RM -rf "${_stage}"
	$MKDIR -p "${_stage}/${_topname}"
	overlay_tracked "${_src}" "${_stage}/${_topname}"
	(cd "${_stage}" && $TAR --create \
		--sort=name --owner=0 --group=0 \
		--mtime='2024-01-01 00:00:00 UTC' --format=ustar \
		--mode='go=rX,u=rwX' \
		--no-acls --no-selinux --no-xattrs \
		--exclude='.git' --exclude='.git/*' \
		--file="${_topname}.tar" "${_topname}")
	$GZIP --force --no-name "${_stage}/${_topname}.tar"
	$CP -f "${_stage}/${_topname}.tar.gz" "${_dest}"
	$RM -rf "${_stage}"
}

# Fetch a GitHub branch tarball into <dest>, stripping the <repo>-<branch>
# top-level component. Stages into a temp dir and only swaps to <dest> on
# success — a failed fetch never leaves an empty <dest> that the caller's
# `test -d` cache check would mistake for a successful prior fetch.
# Decompresses with $GZIP first because tar's child-gzip lookup can't see
# PATH= when set to empty.
fetch_github_archive () {
	_user_repo="$1"; _branch="$2"; _dest="$3"
	_tar_gz="${SH_ROOT}/distfiles/.fetch.tar.gz"
	_tar="${SH_ROOT}/distfiles/.fetch.tar"
	_stage="${SH_ROOT}/distfiles/.fetch-stage"
	$WGET -O "${_tar_gz}" "https://github.com/${_user_repo}/archive/refs/heads/${_branch}.tar.gz"
	$GZIP --force --decompress "${_tar_gz}"
	$RM -rf "${_stage}"
	$MKDIR -p "${_stage}"
	$TAR --extract --strip-components=1 --directory "${_stage}" --file "${_tar}"
	$RM -f "${_tar}"
	$RM -rf "${_dest}"
	$MKDIR -p "${_dest}"
	$CP -Rf "${_stage}/." "${_dest}/"
	$RM -rf "${_stage}"
}

# --- base distfiles (always upstream) ---

# Always re-fetch branch-tracked tarballs: GitHub serves the branch HEAD, which
# changes between sessions. Caching by mere file presence shipped stale state
# into in-image builds and silently diverged hashes from CI sibling-free runs.
# stage0-posix is pinned to a release tag, so its bytes are stable and we
# keep the cache.
if test -d "${SH_ROOT}/../builder-hex0-arch"
then
	$RM -f distfiles/builder-hex0-arch-main.tar.gz
	repackage_to_tarball "${SH_ROOT}/../builder-hex0-arch" distfiles/builder-hex0-arch-main.tar.gz builder-hex0-arch-main
else
	$RM -f distfiles/builder-hex0-arch-main.tar.gz
	$WGET -O distfiles/builder-hex0-arch-main.tar.gz \
		"https://github.com/alganet/builder-hex0-arch/archive/refs/heads/${BUILDER_HEX0_ARCH_BRANCH}.tar.gz"
fi

if ! test -f distfiles/stage0-posix-1.9.1.tar.gz
then $WGET -O distfiles/stage0-posix-1.9.1.tar.gz https://github.com/oriansj/stage0-posix/releases/download/Release_1.9.1/stage0-posix-1.9.1.tar.gz
fi

# --- replacement forks ---

# stage0-uefi: alganet fork by default; sibling overrides; empty branch falls
# back to stikonas Release_1.9.1.
# Always invalidate the branch-tracked clone (HEAD shifts between sessions);
# keep the release-tag clone (immutable bytes).
if test -d "${SH_ROOT}/../stage0-uefi"
then
	$RM -rf distfiles/stage0-uefi-1.9.1
	overlay_tracked "${SH_ROOT}/../stage0-uefi" distfiles/stage0-uefi-1.9.1
elif test -n "${STAGE0_UEFI_BRANCH}"
then
	$RM -rf distfiles/stage0-uefi-1.9.1
	PATH=/usr/bin:/bin $GIT clone --depth 1 --branch "${STAGE0_UEFI_BRANCH}" --recurse-submodules --shallow-submodules \
		"${STAGE0_UEFI_REPO}" distfiles/stage0-uefi-1.9.1
elif ! test -d distfiles/stage0-uefi-1.9.1
then PATH=/usr/bin:/bin $GIT clone --depth 1 --branch Release_1.9.1 --recurse-submodules --shallow-submodules \
	https://git.stikonas.eu/andrius/stage0-uefi.git distfiles/stage0-uefi-1.9.1
fi

# mes: alganet fork by default; sibling overrides; empty branch falls back to
# GNU FTP. Always re-tarred when sourced from sibling so the in-image build
# (which extracts mes-0.27.1.tar.gz) sees fresh content on every run.
if test -d "${SH_ROOT}/../mes"
then
	repackage_to_tarball "${SH_ROOT}/../mes" distfiles/mes-0.27.1.tar.gz mes-0.27.1
elif test -n "${MES_BRANCH}"
then
	$RM -rf distfiles/.mes-fetched
	$RM -f distfiles/mes-0.27.1.tar.gz
	fetch_github_archive alganet/mes "${MES_BRANCH}" distfiles/.mes-fetched
	repackage_to_tarball distfiles/.mes-fetched distfiles/mes-0.27.1.tar.gz mes-0.27.1
	$RM -rf distfiles/.mes-fetched
elif ! test -f distfiles/mes-0.27.1.tar.gz
then $WGET -O distfiles/mes-0.27.1.tar.gz https://ftp.gnu.org/gnu/mes/mes-0.27.1.tar.gz
fi

# --- overlay forks (consumed by apply_overlay in run.sh) ---

# M2libc: overlays onto every M2libc copy in the host tree.
# Always invalidate the cache: GitHub branch HEAD shifts between sessions, and
# a stale overlay would clobber the sibling stage0-uefi/M2libc submodule's
# current pin with older bytes (this exact bug produced silently-wrong
# in-image .efi seals overnight). When the stage0-uefi sibling is present its
# submodule's working tree is authoritative; otherwise refetch from GitHub.
$RM -rf distfiles/overlay-M2libc
if test -d "${SH_ROOT}/../M2libc"
then : # top-level sibling overrides at apply time
elif test -d "${SH_ROOT}/../stage0-uefi/M2libc"
then overlay_tracked "${SH_ROOT}/../stage0-uefi/M2libc" distfiles/overlay-M2libc
elif test -n "${M2LIBC_BRANCH}"
then fetch_github_archive alganet/M2libc "${M2LIBC_BRANCH}" distfiles/overlay-M2libc
fi

# bootstrap-seeds: overlays onto top-level + stage0-uefi/bootstrap-seeds.
$RM -rf distfiles/overlay-bootstrap-seeds
if test -d "${SH_ROOT}/../bootstrap-seeds"
then : # top-level sibling overrides at apply time
elif test -d "${SH_ROOT}/../stage0-uefi/bootstrap-seeds"
then overlay_tracked "${SH_ROOT}/../stage0-uefi/bootstrap-seeds" distfiles/overlay-bootstrap-seeds
elif test -n "${BOOTSTRAP_SEEDS_BRANCH}"
then fetch_github_archive alganet/bootstrap-seeds "${BOOTSTRAP_SEEDS_BRANCH}" distfiles/overlay-bootstrap-seeds
fi
