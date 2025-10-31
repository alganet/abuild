[#]:: (SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>)
[#]:: (SPDX-License-Identifier: GPL-3.0-or-later)

# abuild

A proof-of-concept self-hosting bootable x86 image that recreates itself from hex0 seeds.

## Quick Start

```sh
sh run.sh all
```

This downloads dependencies, builds the toolchain, creates a bootable image, boots it in QEMU, and verifies the image can reproduce itself identically.

## What It Does

abuild implements a three-phase bootstrap:

1. **Host Bootstrap** - Downloads stage0-posix and builder-hex0, builds x86 toolchain
2. **Image Creation** - Creates bootable `out/k0.img` with filesystem and bootstrap tools
3. **Self-Verification** - Boots image in QEMU, rebuilds itself, proves independence via sha256sum

Success means the host-built image matches the self-generated image byte-for-byte.

## Development

Fast rebuild (skip QEMU):
```sh
sh run.sh make_host make_k0_img
```

Extract image contents:
```sh
./out/host/bin/bh0x out/k0.img out/k0
```

Verify licenses:
```sh
sh LICENSES/verify.sh
```
