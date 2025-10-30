#!/usr/bin/env sh

# SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

# Checks that all files have proper SPDX license identifiers and that all
# licenses used are present in the LICENSES folder.

set -euf

# Creates variables for each license title found in LICENSES folder
create_license_vars () {
    echo "SPDX_license_ids="
    find ./LICENSES -type f | while read -r license_file
    do
        license_id="${license_file##*"./LICENSES/"}"
        license_id="${license_id%%".txt"*}"
        alnum_id=$(echo "SPDX_$license_id" | sed 's/[^A-Za-z0-9]/_/g')
        echo "${alnum_id}_id='${license_id}'"
        echo "SPDX_license_ids=\"\${SPDX_license_ids} ${alnum_id}\""
    done
}

find_spdx_ids () {
    { grep --exclude-dir=".git" -ar "SPDX-License-Identifier*" . || true; } |
    { grep -v "LICENSES/verify.sh" || true; } |
        sed 's/^\(^[^:]*\):.*SPDX-License-Identifier: \([A-Za-z0-9.-]*\).*$/\1    \2/g' |
        sort -u

    find distfiles -name '*.tar.*' |
    while read -r tar_file
    do
        case "$tar_file" in
            *.tar.gz|*.tgz) grep_cmd="zgrep" ;;
            *.tar.bz2) grep_cmd="bzgrep" ;;
            *.tar.xz) grep_cmd="xzgrep" ;;
        esac
        { $grep_cmd -a "SPDX-License-Identifier" "${tar_file}" || true; } |
        sed 's/^.*SPDX-License-Identifier: \([A-Za-z0-9.-]*\).*$/\1/g' |
            sort -u |
			while read -r spdx_id
            do
                printf %s\\t%s\\n "./${tar_file}" "${spdx_id}"
            done
    done
}

check_spdx_ids () {
    while read origin_file spdx_id
    do
        if ! test -e "LICENSES/${spdx_id}.txt"
        then
            echo "[ERROR] missing license"
            echo "  origin: ${origin_file}"
            echo " missing: ./LICENSES/${spdx_id}.txt"
            exit 1
        fi
        echo "ok - ${spdx_id} - $origin_file"
    done
}

SPDX_license_ids=
_EOL="
"

eval "$(create_license_vars)"

find_spdx_ids | check_spdx_ids

echo "All license checks passed."
exit 0

