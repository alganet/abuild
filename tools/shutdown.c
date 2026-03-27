/* SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com> */
/* SPDX-License-Identifier: GPL-3.0-or-later */

/* shutdown: Shuts down a UEFI system via RT->ResetSystem(). */

#include <stdio.h>
#include <stdlib.h>
#include <bootstrappable.h>

int main(int argc, char** argv)
{
	fputs("Shutting down\n", stdout);
	/* Stall 5 seconds to let serial buffer flush */
	__uefi_1(5000000, _system->boot_services->stall);
	/* EfiResetCold = 0; with QEMU --no-reboot this causes QEMU to exit */
	__uefi_4(0, 0, 0, 0, _system->runtime_services->reset_system);
	return 0;
}
