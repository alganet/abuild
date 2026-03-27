/* SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com> */
/* SPDX-License-Identifier: GPL-3.0-or-later */

#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include "M2libc/bootstrappable.h"

#define FILE_MODE 0755

int match_prefix(char* str, char* prefix) {
  while (*prefix) {
    if (*str != *prefix)
      return 0;
    str += 1;
    prefix += 1;
  }
  return 1;
}

char* after_prefix(char* str, char* prefix) {
  while (*prefix) {
    str += 1;
    prefix += 1;
  }
  return str;
}

int main(int argc, char** argv) {
  int block_size = 0;
  int count = -1;
  char* input_filename = NULL;
  char* output_filename = NULL;
  int i;

  for (i = 1; i < argc; i += 1) {
    if (match_prefix(argv[i], "if=")) {
      input_filename = after_prefix(argv[i], "if=");
    } else if (match_prefix(argv[i], "bs=")) {
      block_size = strtoint(after_prefix(argv[i], "bs="));
    } else if (match_prefix(argv[i], "of=")) {
      output_filename = after_prefix(argv[i], "of=");
    } else if (match_prefix(argv[i], "count=")) {
      count = strtoint(after_prefix(argv[i], "count="));
    } else {
      fputs("Error: Unknown argument: ", stderr);
      fputs(argv[i], stderr);
      fputs("\n", stderr);
      exit(EXIT_FAILURE);
    }
  }

  if (input_filename == NULL) {
    fputs("Error: Missing if= argument\n", stderr);
    exit(EXIT_FAILURE);
  }

  if (block_size <= 0) {
    fputs("Error: Missing or invalid bs= argument\n", stderr);
    exit(EXIT_FAILURE);
  }

  if (output_filename == NULL) {
    fputs("Error: Missing of= argument\n", stderr);
    exit(EXIT_FAILURE);
  }

  int input_fd = open(input_filename, O_RDONLY, 0);
  if (input_fd == -1) {
    fputs("Error: Cannot open input file\n", stderr);
    exit(EXIT_FAILURE);
  }

  int output_fd =
      open(output_filename, O_WRONLY | O_CREAT | O_TRUNC, FILE_MODE);
  if (output_fd == -1) {
    fputs("Error: Cannot open output file\n", stderr);
    close(input_fd);
    exit(EXIT_FAILURE);
  }

  if (count >= 0) {
    char* buf = calloc(block_size + 1, sizeof(char));
    int total = count * block_size;
    while (total > 0) {
      int to_read = total;
      if (to_read > block_size) {
        to_read = block_size;
      }
      int bytes_read = read(input_fd, buf, to_read);
      if (bytes_read <= 0) {
        break;
      }
      write(output_fd, buf, bytes_read);
      total = total - bytes_read;
    }
    free(buf);
  } else {
    int32_t file_offset = lseek(input_fd, 0, 2);
    if (file_offset == -1) {
      fputs("Error: Failed to seek to end of input file\n", stderr);
      close(input_fd);
      close(output_fd);
      exit(EXIT_FAILURE);
    }

    {
      int pad_total = block_size - (file_offset % block_size);
      if(pad_total == block_size) pad_total = 0;
      char* zbuf = calloc(4096, 1);
      while(pad_total > 0) {
        int chunk = pad_total;
        if(chunk > 4096) chunk = 4096;
        if(write(output_fd, zbuf, chunk) != chunk) {
          fputs("Error: Failed to write padding to output file\n", stderr);
          close(input_fd);
          close(output_fd);
          exit(EXIT_FAILURE);
        }
        pad_total = pad_total - chunk;
      }
      free(zbuf);
    }
  }

  close(input_fd);

  if (close(output_fd) != 0) {
    fputs("Error: Failed to close output file\n", stderr);
    exit(EXIT_FAILURE);
  }

  return EXIT_SUCCESS;
}
