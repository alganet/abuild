/* SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com> */
/* SPDX-License-Identifier: GPL-3.0-or-later */

#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include "M2libc/bootstrappable.h"

#define FILE_MODE 0755

int main(int argc, char** argv) {
  int block_size;
  char* input_filename;
  char* output_filename;

  if (argc < 4) {
    fputs("Usage: zrpad <input_file> <block_size> <output_file>\n", stderr);
    exit(EXIT_FAILURE);
  }

  input_filename = argv[1];
  block_size = strtoint(argv[2]);
  output_filename = argv[3];

  int input_fd = open(input_filename, O_RDONLY, 0);
  if (input_fd == -1) {
    fputs("Error: Cannot open input file\n", stderr);
    exit(EXIT_FAILURE);
  }

  int32_t file_offset = lseek(input_fd, 0, 2);
  if (file_offset == -1) {
    fputs("Error: Failed to seek to end of input file\n", stderr);
    close(input_fd);
    exit(EXIT_FAILURE);
  }

  if (close(input_fd) != 0) {
    fputs("Error: Failed to close input file\n", stderr);
    exit(EXIT_FAILURE);
  }

  int output_fd =
      open(output_filename, O_WRONLY | O_CREAT | O_TRUNC, FILE_MODE);
  if (output_fd == -1) {
    fputs("Error: Cannot open output file\n", stderr);
    exit(EXIT_FAILURE);
  }

  while ((file_offset % block_size) != 0) {
    char zero = '\0';
    if (write(output_fd, &zero, 1) != 1) {
      fputs("Error: Failed to write padding byte to output file\n", stderr);
      close(output_fd);
      exit(EXIT_FAILURE);
    }
    file_offset += 1;
  }

  if (close(output_fd) != 0) {
    fputs("Error: Failed to close output file\n", stderr);
    exit(EXIT_FAILURE);
  }

  return EXIT_SUCCESS;
}
