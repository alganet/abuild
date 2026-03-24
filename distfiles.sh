#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

WGET="${WGET:-$(command -v wget)}"
MKDIR="${MKDIR:-$(command -v mkdir)}"

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