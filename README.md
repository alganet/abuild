[#]:: (SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com>)
[#]:: (SPDX-License-Identifier: GPL-3.0-or-later)

sbuild
======

sbuild is a proof-of-concept prototype of a full source bootstrap system for x86.

It's the smallest (to date) self-hosting bootable image that can recreate itself
from within itself.

Intructions
-----------

Run `sh boot.sh`. You should see `build/k0.img: OK`, which proves the image
generated from inside the bootable image is identical to the image itself.

To prove that an image is really written, and the sha256sum is not just
checking the artifact from the host system, you can remove `build/k0.img` and 
run `FORCE_FAIL=yes sh boot.sh`, which will introduce a change to 
`build/descend/files/seal` during the inner image build, forcing a mismatch.

Problem
-------

The initial kick of a full source bootstrap system is *creating a bootable image*.

In projects such as live-bootstrap, this is achieved with the help of external tools,
most prominently, python.

sbuild aims to explore this space: the tools used to create a first bootable image,
from a bootstrapper's approach.

Solution
--------

We present a self-hosting system based on stage0-posix-x86 and builder-hex0, able to
re-construct it's own bootable image from within, using the same script that was used
to build the image outside.

Although the image preparation steps are still required to be performed outside the
bootstrapped system, once it's bootstrapped, the system is able to perform those
same steps (Phase 2, see below) from the booted image and produce an exact copy
of the image that was created outside, therefore proving they're the same.

This drastically reduces the dependencies for the image preparation steps.

Steps
-----

Phase 1: "dirty" stage0 bootstrap (still depends on pre-existing kernel and tools)

 - boot.sh: download stage0-posix and builder-hex0.
 - boot.sh: run stage0-posix x86 build from in the host system.
 - boot.sh: run k0.kaem inside mescc-tools-extra's `wrap` program (simple chroot clone).

Phase 2: "dirty" image creation (still depends on existing kernel, all tools bootstrapped)

 - k0.kaem: re-build the hex0 seed
 - k0.kaem: build builder-hex0-x86-stage1
 - k0.kaem: build `wcw` (partial `wc` clone) and zrpad (partial `dd` clone).
 - k0.kaem: setup `create_file`, `putdir.kaem` and `putfile.kaem` scripts
 - k0.kaem: creates the bootable image using `putdir` and `putfile`.
 - k0.kaem: writes the bootable image to `/dev/hda` (file within wrapped chroot)

Phase 3: "clean" image creation (kernel and tools built entirely from source)

 - boot.sh: copy `build/dev/hda` to `build/k0.img` (saves the bootable image)
 - boot.sh: boots `k0.img` within `qemu-system-i386`.
 - builder-hex0: build the hex0 seed.
 - builder-hex0: build `kaem-optional-seed`.
 - builder-hex0: bootstraps stage0-posix-x86 (again, now inside qemu).
 - k1.kaem (as after.kaem): Runs **Phase 2** (again, now inside qemu).

If everything goes right, **Phase 3** proves that the "dirty" and the "clean"
images are the same, and therefore, independent of pre-existing non-seed binaries.
