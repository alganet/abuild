#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

WGET="${WGET:-$(command -v wget)}"
MKDIR="${MKDIR:-$(command -v mkdir)}"
GIT="${GIT:-$(command -v git)}"

set -eufx
PATH=

SH_FILE="$PWD/$0"
SH_ROOT="${SH_FILE%\/*}"
cd "$SH_ROOT"

$MKDIR -p "distfiles"

# NOTE: this file is used to check if dependencies changed in CI
# SEE: .github/workflows/build.yml

# V=1.5 (bump internal version because no official release yet)
if ! test -f distfiles/builder-hex0-arch-main.tar.gz
then $WGET -O distfiles/builder-hex0-arch-main.tar.gz https://github.com/alganet/builder-hex0-arch/archive/refs/heads/main.tar.gz
fi

if ! test -f distfiles/stage0-posix-1.9.1.tar.gz
then $WGET -O distfiles/stage0-posix-1.9.1.tar.gz https://github.com/oriansj/stage0-posix/releases/download/Release_1.9.1/stage0-posix-1.9.1.tar.gz
fi

if ! test -d distfiles/stage0-uefi-1.9.1
then PATH=/usr/bin:/bin $GIT clone --depth 1 --branch Release_1.9.1 --recurse-submodules --shallow-submodules \
	https://git.stikonas.eu/andrius/stage0-uefi.git distfiles/stage0-uefi-1.9.1
fi

if ! test -f distfiles/mes-0.27.1.tar.gz
then $WGET -O distfiles/mes-0.27.1.tar.gz https://ftp.gnu.org/gnu/mes/mes-0.27.1.tar.gz
fi
