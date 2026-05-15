#!/usr/bin/env sh
# Boot riscv64 UEFI in QEMU with serial capture + exception logging.
# Captures every CPU exception to qemu-debug.log so we can spot ebreak traps
# from the cc_riscv64.M1 probe even when ConOut output is invisible.
#
# Usage: sh boot-uefi-debug.sh [timeout_seconds]

TIMEOUT_SECS="${1:-300}"
ARCH=riscv64
BOARD=uefi
SERIAL_LOG="out/qemu-${ARCH}-${BOARD}-serial.log"
DEBUG_LOG="out/qemu-${ARCH}-${BOARD}-debug.log"
OVMF_RISCV64_CODE="${OVMF_RISCV64_CODE:-/usr/share/qemu-efi-riscv64/RISCV_VIRT_CODE.fd}"
OVMF_RISCV64_VARS="${OVMF_RISCV64_VARS:-/usr/share/qemu-efi-riscv64/RISCV_VIRT_VARS.fd}"
QEMU="${QEMU:-$(command -v qemu-system-riscv64)}"
CP="${CP:-$(command -v cp)}"

set -eux

$CP "${OVMF_RISCV64_VARS}" "out/k0-${ARCH}-${BOARD}-vars.fd"

timeout "${TIMEOUT_SECS}" $QEMU \
    -machine virt \
    -m 4G \
    -nographic \
    -drive if=pflash,format=raw,unit=0,file=${OVMF_RISCV64_CODE},readonly=on \
    -drive if=pflash,format=raw,unit=1,file=out/k0-${ARCH}-${BOARD}-vars.fd \
    -device nvme,serial=deadbeef,drive=hd0 \
    -drive file="out/k0-${ARCH}-${BOARD}-fat.img",format=raw,if=none,id=hd0 \
    -serial file:${SERIAL_LOG} \
    -d int,guest_errors,cpu_reset,unimp \
    -D ${DEBUG_LOG} \
    --no-reboot \
    2>&1 || true

echo "=== serial tail ==="
tail -60 "${SERIAL_LOG}" 2>/dev/null || echo "(no serial log)"

echo "=== debug tail (exceptions / guest errors) ==="
tail -80 "${DEBUG_LOG}" 2>/dev/null || echo "(no debug log)"

# Extract updated bh0 from FAT if present
./out/host-x86/bin/fatget "out/k0-${ARCH}-${BOARD}-fat.img" /k0.img "out/k0-${ARCH}-${BOARD}.img" 2>/dev/null || true
