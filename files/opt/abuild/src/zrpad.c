/* SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com> */
/* SPDX-License-Identifier: GPL-3.0-or-later */

#include <stdio.h>
#include <stdlib.h>

#include "M2libc/bootstrappable.h"

int main(int argc, char **argv) {
  int bs;
  char *filename;

  if (argc < 3) {
    fputs("zrpad requires 3 arguments\n", stderr);
    exit(0);
  }

  filename = argv[1];
  bs = strtoint(argv[2]);

  FILE *fp = NULL;
  FILE *fw = NULL;
  long off;

  fp = fopen(filename, "r");
  if (fp == NULL) {
    fputs("failed to fopen\n", stderr);
    exit(EXIT_FAILURE);
  }

  if (fseek(fp, 0, SEEK_END) == -1) {
    fputs("failed to fseek\n", stderr);
    exit(EXIT_FAILURE);
  }

  off = ftell(fp);

  if (fclose(fp) != 0) {
    fputs("failed to fclose\n", stderr);
    exit(EXIT_FAILURE);
  }

  if (off == -1) {
    fputs("failed to ftell\n", stderr);
    exit(EXIT_FAILURE);
  }

  fw = fopen(argv[3], "w");
  while (0 != off % bs) {
    fputc('\0', fw);
    off += 1;
  }

  if (fclose(fw) != 0) {
    fputs("failed to fclose\n", stderr);
    exit(EXIT_FAILURE);
  }

  return 0;
}
