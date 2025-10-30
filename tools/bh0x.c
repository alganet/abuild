/* SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com> */
/* SPDX-License-Identifier: GPL-3.0-or-later */

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

int main(int argc, char **argv) {
  if (NULL == argv[1]) {
    fputs("bh0x requires an argument\n", stderr);
    exit(EXIT_FAILURE);
  }

  int input = open(argv[1], O_RDONLY, 0);
  if (-1 == input) {
    fputs("aThe file: ", stderr);
    fputs(argv[1], stderr);
    fputs(" is not a valid input file name\n", stderr);
    exit(EXIT_FAILURE);
  }

  char *buffer = calloc(512 + 1, sizeof(char));
  int bytes = read(input, buffer, 512);
keep:
  bytes = read(input, buffer, 512);
  if (512 == strlen(buffer))
    goto keep;

  char *instr = calloc(4, sizeof(char));
  char *fname = calloc(1024, sizeof(char));
  char *fsize = calloc(10, sizeof(char));
  char *c = calloc(1, sizeof(char));
  char *entpath = calloc(2048, sizeof(char));
  char *xfile = calloc(2048, sizeof(char));
  char *fcontents = calloc(512 + 1, sizeof(char));
  int fisize;
  int fibuff;
  int output3;

  strcat(entpath, argv[2]);
  mkdir(entpath, 0755);

newentry:
  bytes = read(input, instr, 4);

  if (0 == bytes) {
    exit(EXIT_SUCCESS);
  }

  if (0 != strcmp("src ", instr)) {
    strcpy(xfile, "");
    strcat(xfile, argv[2]);
    strcat(xfile, "/init");
    output3 = open(xfile, O_WRONLY | O_CREAT | O_APPEND, 384);
    if (-1 == output3) {
      fputs("dThe file: ", stderr);
      fputs(xfile, stderr);
      fputs(" is not a valid output3 file name\n", stderr);
      exit(EXIT_FAILURE);
    }
    write(output3, instr, strlen(instr));
    bytes = read(input, fcontents, 1024);
    write(output3, fcontents, strlen(fcontents));
    goto newentry;
  }

  strcpy(fsize, "");
  strcpy(fname, "");

sizescan:
  bytes = read(input, c, 1);
  if (0 != strcmp(c, " ")) {
    strcat(fsize, c);
    goto sizescan;
  }

  fisize = atoi(fsize);

fnamescan:
  bytes = read(input, c, 1);
  if (0 != strcmp(c, "\n")) {
    strcat(fname, c);
    goto fnamescan;
  }

  strcpy(entpath, "");
  strcat(entpath, argv[2]);
  strcat(entpath, fname);

  if (0 == fisize) {
    mkdir(entpath, 0755);
    goto newentry;
  }

  strcpy(xfile, "");
  strcat(xfile, argv[2]);
  strcat(xfile, fname);
  output3 = open(xfile, O_WRONLY | O_CREAT | O_TRUNC, 384);
  if (-1 == output3) {
    fputs("dThe file: ", stderr);
    fputs(xfile, stderr);
    fputs(" is not a valid output3 file name\n", stderr);
    exit(EXIT_FAILURE);
  }

fireads:
  fibuff = fisize;
  strcpy(fcontents, "");
  if (fisize > 512) {
    fibuff = 512;
  }

  bytes = read(input, fcontents, fibuff);
  write(output3, fcontents, strlen(fcontents));
  fisize = fisize - bytes;

  if (fisize > 0) {
    goto fireads;
  }

  goto newentry;
}
