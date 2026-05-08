#!/usr/bin/env sh
# Boot riscv64 UEFI in QEMU with timeout and log capture
# Usage: sh boot-uefi.sh [timeout_seconds]

TIMEOUT_SECS="${1:-120}"
ARCH=riscv64
LOG="out/qemu-${ARCH}.log"
OVMF_RISCV64_CODE="${OVMF_RISCV64_CODE:-/usr/share/qemu-efi-riscv64/RISCV_VIRT_CODE.fd}"
OVMF_RISCV64_VARS="${OVMF_RISCV64_VARS:-/usr/share/qemu-efi-riscv64/RISCV_VIRT_VARS.fd}"
QEMU="${QEMU:-$(command -v qemu-system-riscv64)}"
CP="${CP:-$(command -v cp)}"

set -eux

$CP "${OVMF_RISCV64_VARS}" "out/k0-${ARCH}-vars.fd"

# Run QEMU with timeout, capture serial to log
timeout "${TIMEOUT_SECS}" $QEMU \
    -machine virt \
    -m 4G \
    -nographic \
    -drive if=pflash,format=raw,unit=0,file=${OVMF_RISCV64_CODE},readonly=on \
    -drive if=pflash,format=raw,unit=1,file=out/k0-${ARCH}-vars.fd \
    -device nvme,serial=deadbeef,drive=hd0 \
    -drive file="out/k0-${ARCH}-fat.img",format=raw,if=none,id=hd0 \
    -serial file:${LOG} \
    --no-reboot \
    2>&1 || true

echo "=== QEMU exited, log tail ==="
tail -50 "${LOG}" 2>/dev/null || echo "(no log)"

# Extract updated bh0 from FAT
./out/host-x86/bin/fatget "out/k0-${ARCH}-fat.img" /k0.img "out/k0-${ARCH}.img" 2>/dev/null || true
