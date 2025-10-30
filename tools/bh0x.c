/* SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com> */
/* SPDX-License-Identifier: GPL-3.0-or-later */

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#define BLOCK_SIZE 512
#define BUFFER_SIZE (BLOCK_SIZE + 1)
#define INSTR_SIZE 4
#define FSIZE_SIZE 10
#define PATH_SIZE 1024
#define FILE_MODE 0755

int main(int argc, char** argv) {
  int input;
  int bytes;
  int output_fd;
  int file_size;
  int read_size;
  char* buffer;
  char* instr;
  char* fname;
  char* fsize_str;
  char* single_char;
  char* entry_path;
  char* output_path;
  char* file_contents;

  /* Validate input arguments */
  if (NULL == argv[1]) {
    fputs("bh0x requires an input file argument\n", stderr);
    exit(EXIT_FAILURE);
  }

  if (NULL == argv[2]) {
    fputs("bh0x requires an output directory argument\n", stderr);
    exit(EXIT_FAILURE);
  }

  /* Open input image file */
  input = open(argv[1], O_RDONLY, 0);
  if (-1 == input) {
    fputs("The file: ", stderr);
    fputs(argv[1], stderr);
    fputs(" is not a valid input file name\n", stderr);
    exit(EXIT_FAILURE);
  }

  /* Allocate buffers */
  buffer = calloc(BUFFER_SIZE, sizeof(char));
  instr = calloc(INSTR_SIZE, sizeof(char));
  fname = calloc(PATH_SIZE, sizeof(char));
  fsize_str = calloc(FSIZE_SIZE, sizeof(char));
  single_char = calloc(1, sizeof(char));
  entry_path = calloc(PATH_SIZE, sizeof(char));
  output_path = calloc(PATH_SIZE, sizeof(char));
  file_contents = calloc(BUFFER_SIZE, sizeof(char));

  /* Skip header blocks until we find a non-full block */
  bytes = read(input, buffer, BLOCK_SIZE);
  while (1) {
    bytes = read(input, buffer, BLOCK_SIZE);
    if (BLOCK_SIZE != strlen(buffer)) {
      break;
    }
  }

  /* Create output root directory */
  snprintf(entry_path, PATH_SIZE, "%s", argv[2]);
  mkdir(entry_path, FILE_MODE);

  /* Process each entry in the image */
  while (1) {
    bytes = read(input, instr, INSTR_SIZE);

    if (0 == bytes) {
      close(input);
      exit(EXIT_SUCCESS);
    }

    /* Handle non-"src " entries (init script commands) */
    if (0 != strcmp("src ", instr)) {
      continue;
    }

    /* Parse "src <size> <path>" entry */
    snprintf(fsize_str, FSIZE_SIZE, "");
    snprintf(fname, PATH_SIZE, "");

    /* Read file size digits until space */
    while (1) {
      bytes = read(input, single_char, 1);
      if (0 == strcmp(single_char, " ")) {
        break;
      }
      snprintf(fsize_str + strlen(fsize_str), FSIZE_SIZE - strlen(fsize_str),
               "%s", single_char);
    }

    file_size = atoi(fsize_str);

    /* Read file path until newline */
    while (1) {
      bytes = read(input, single_char, 1);
      if (0 == strcmp(single_char, "\n")) {
        break;
      }
      snprintf(fname + strlen(fname), PATH_SIZE - strlen(fname), "%s",
               single_char);
    }

    /* Build full entry path */
    snprintf(entry_path, PATH_SIZE, "%s%s", argv[2], fname);

    /* Size 0 means directory entry */
    if (0 == file_size) {
      mkdir(entry_path, FILE_MODE);
      continue;
    }

    /* Create regular file */
    snprintf(output_path, PATH_SIZE, "%s%s", argv[2], fname);
    output_fd = open(output_path, O_WRONLY | O_CREAT | O_TRUNC, FILE_MODE);
    if (-1 == output_fd) {
      fputs("The file: ", stderr);
      fputs(output_path, stderr);
      fputs(" cannot be opened for writing\n", stderr);
      exit(EXIT_FAILURE);
    }

    /* Read file contents in blocks */
    while (file_size > 0) {
      read_size = file_size;
      snprintf(file_contents, BUFFER_SIZE, "");
      if (file_size > BLOCK_SIZE) {
        read_size = BLOCK_SIZE;
      }

      bytes = read(input, file_contents, read_size);
      write(output_fd, file_contents, strlen(file_contents));
      file_size = file_size - bytes;
    }

    close(output_fd);
  }
}
