#!/usr/bin/env sh
# Boot QEMU with GDB stub (port 1234), paused at start.
# Use: gdb-multiarch in another terminal:
#   (gdb) target remote :1234
#   (gdb) continue

TIMEOUT_SECS="${1:-600}"
ARCH=riscv64
BOARD=uefi
SERIAL_LOG="out/qemu-${ARCH}-${BOARD}-serial.log"
OVMF_RISCV64_CODE="${OVMF_RISCV64_CODE:-/usr/share/qemu-efi-riscv64/RISCV_VIRT_CODE.fd}"
OVMF_RISCV64_VARS="${OVMF_RISCV64_VARS:-/usr/share/qemu-efi-riscv64/RISCV_VIRT_VARS.fd}"
QEMU="${QEMU:-$(command -v qemu-system-riscv64)}"
CP="${CP:-$(command -v cp)}"

set -eux

$CP "${OVMF_RISCV64_VARS}" "out/k0-${ARCH}-${BOARD}-vars.fd"

# -s = gdbstub on port 1234
# -S = start paused, wait for GDB to continue
timeout "${TIMEOUT_SECS}" $QEMU \
    -machine virt \
    -m 4G \
    -nographic \
    -drive if=pflash,format=raw,unit=0,file=${OVMF_RISCV64_CODE},readonly=on \
    -drive if=pflash,format=raw,unit=1,file=out/k0-${ARCH}-${BOARD}-vars.fd \
    -device nvme,serial=deadbeef,drive=hd0 \
    -drive file="out/k0-${ARCH}-${BOARD}-fat.img",format=raw,if=none,id=hd0 \
    -serial file:${SERIAL_LOG} \
    -s -S \
    --no-reboot \
    2>&1 || true
