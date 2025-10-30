/* SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com> */
/* SPDX-License-Identifier: GPL-3.0-or-later */

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "M2libc/bootstrappable.h"

// CONSTANT BUFFER_SIZE 4096
#define BUFFER_SIZE 4096

int main(int argc, char **argv) {
  if (2 > argc) {
    fputs("wcw requires 2 arguments\n", stderr);
    exit(EXIT_FAILURE);
  }

  // int output = open(argv[1], O_WRONLY|O_CREAT|O_APPEND, 384);
  int output = open(argv[1], 577, 384);
  if (-1 == output) {
    fputs("The file: ", stderr);
    fputs(argv[1], stderr);
    fputs(" is not a valid output file name\n", stderr);
    exit(EXIT_FAILURE);
  }

  int bytes;
  int bsize;
  char *buffer = calloc(BUFFER_SIZE + 1, sizeof(char));
  char *tbytes = malloc(1024);
  int input;
  bsize = 0;
  input = open(argv[2], 0, 0);
  if (-1 == input) {
    fputs("The file: ", stderr);
    fputs(argv[2], stderr);
    fputs(" is not a valid input file name\n", stderr);
    exit(EXIT_FAILURE);
  }
keep:
  bytes = read(input, buffer, BUFFER_SIZE);
  bsize += bytes;
  if (BUFFER_SIZE == bytes)
    goto keep;

  tbytes = strcat(tbytes, "src ");
  tbytes = strcat(tbytes, int2str(bsize, 10, FALSE));
  tbytes = strcat(tbytes, " ");
  tbytes = strcat(tbytes, argv[2]);
  tbytes = strcat(tbytes, "\n\0");
  write(output, tbytes, strlen(tbytes));

  free(buffer);
  return EXIT_SUCCESS;
}
