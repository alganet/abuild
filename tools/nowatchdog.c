/* SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com> */
/* SPDX-License-Identifier: GPL-3.0-or-later */

/* nowatchdog: Disables the UEFI watchdog timer.
 * UEFI firmware sets a 5-minute watchdog by default.  If not disabled,
 * the firmware resets the system after 5 minutes — too short for
 * extracting large tarballs or compiling mes.
 */

#include <stdio.h>
#include <stdlib.h>

int main(int argc, char** argv)
{
	__uefi_4(0, 0, 0, 0, _system->boot_services->set_watchdog_timer);
	fputs("watchdog disabled\n", stderr);
	return 0;
}
