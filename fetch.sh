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

$MKDIR -p "files/vendor"

# NOTE: this file is used to check if dependencies changed in CI
# SEE: .github/workflows/build.yml

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
