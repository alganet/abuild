/* SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com> */
/* SPDX-License-Identifier: GPL-3.0-or-later */

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "M2libc/bootstrappable.h"
#include "M2libc/fcntl.h"

#define BUFFER_SIZE 4096
#define HEADER_SIZE 2048
#define FILE_MODE 0755
#define BASE_TEN 10

void cleanup(char* buffer, char* header, int input_fd, int output_fd) {
  if (buffer)
    free(buffer);
  if (header)
    free(header);
  if (input_fd >= 0)
    close(input_fd);
  if (output_fd >= 0)
    close(output_fd);
}

void error_exit(const char* msg) {
  fputs(msg, stderr);
  exit(EXIT_FAILURE);
}

int main(int argc, char** argv) {
  if (argc < 3) {
    error_exit("Error: wcw requires 2 arguments: <output_file> <input_file>\n");
  }

  int output_fd = open(argv[1], O_WRONLY | O_CREAT | O_TRUNC, FILE_MODE);
  if (output_fd == -1) {
    error_exit("Error: Cannot open output file\n");
  }

  int total_bytes = 0;
  char* buffer = calloc(BUFFER_SIZE + 1, sizeof(char));
  char* header = malloc(HEADER_SIZE);
  int input_fd = open(argv[2], O_RDONLY, 0);
  if (input_fd == -1) {
    cleanup(buffer, header, -1, output_fd);
    error_exit("Error: Cannot open input file\n");
  }

  int bytes_read = 0;
  do {
    bytes_read = read(input_fd, buffer, BUFFER_SIZE);
    if (bytes_read < 0) {
      cleanup(buffer, header, input_fd, output_fd);
      error_exit("Error: Failed to read input file\n");
    }
    total_bytes += bytes_read;
  } while (bytes_read == BUFFER_SIZE);

  snprintf(header, HEADER_SIZE, "src %s %s\n",
           int2str(total_bytes, BASE_TEN, FALSE), argv[2]);
  write(output_fd, header, strlen(header));

  cleanup(buffer, header, input_fd, output_fd);
  return EXIT_SUCCESS;
}
