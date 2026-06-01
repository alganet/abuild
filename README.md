[#]:: (SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>)
[#]:: (SPDX-License-Identifier: GPL-3.0-or-later)

# abuild

Builds self-hosting bootable images that rebuild themselves from a hex0 seed,
for seven architecture/board targets. Wraps stage0-uefi, M2libc and GNU Mes
into a reproducible, sealed image per target.

## Quick Start

```sh
sh run.sh all                          # x86/bios (default)
ARCH=riscv64 BOARD=uefi sh run.sh all  # pick a target
```

Builds the host toolchain, assembles a bootable image, boots it in QEMU, and
checks the booted image reproduces itself byte-for-byte against its sealed hash.

## Targets

| ARCH    | BOARD                |
|---------|----------------------|
| x86     | bios                 |
| amd64   | uefi                 |
| aarch64 | virt, raspi3b        |
| riscv64 | virt, sifive_u, uefi |

## Stages

`run.sh all` runs these in order (each also runs standalone), then extracts
the sealed image with `make_k0`:

1. **make_host** — a hex0 seed bootstraps the stage0-posix chain into the host
   toolchain, plus the builder-hex0 stage1 kernels and helper tools.
2. **make_k0_img** — packs the toolchain, full source tree and seeds into a
   bootable image `out/k0-<arch>-<board>.img` (UEFI also gets a `-fat.img`).
3. **boot_k0_img** — boots it in QEMU; the guest reruns the whole bootstrap and
   builds GNU Mes, printing `Hello from inside the <arch> image` on success.
4. **sha256sum_k0_answers** — seals/verifies the post-boot image against
   `k0-<arch>-<board>.answers`.

The stage0-uefi compiler chain that runs inside the image is documented in the
stage0-uefi README.

## Development

```sh
sh run.sh make_host make_k0_img                              # skip QEMU
./out/host-x86/bin/bh0x out/k0-x86-bios.img out/k0-x86-bios  # extract image
sh LICENSES/verify.sh                                        # check licenses
```
