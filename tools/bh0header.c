/* SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com> */
/* SPDX-License-Identifier: GPL-3.0-or-later */

/* bh0header: appends a bh0 entry to an accumulator file.
 * Usage: bh0header <accumulator> <path>          (directory entry)
 *        bh0header <accumulator> <path> <source> (file entry)
 *
 * Seeks to the end of the accumulator and appends "src <size> <path>\n"
 * header (and file contents if source given).  In-place append avoids
 * the O(n^2) copy-via-temp that stalled on UEFI FAT32 after ~145 files.
 */

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "M2libc/bootstrappable.h"

#define BUF_SIZE 4096

int main(int argc, char** argv)
{
	int acc_out;
	int src_fd;
	int src_size;
	int bytes;
	char* buf;
	char* header;
	int header_len;
	int i;

	if(argc < 3)
	{
		fputs("Usage: bh0header <accumulator> <path> [source]\n", stderr);
		exit(EXIT_FAILURE);
	}

	/* Measure source file if given */
	src_size = 0;
	if(argc >= 4)
	{
		src_fd = open(argv[3], 0, 0);
		if(src_fd == -1)
		{
			fputs("bh0header: cannot open ", stderr);
			fputs(argv[3], stderr);
			fputs("\n", stderr);
			exit(EXIT_FAILURE);
		}
		src_size = lseek(src_fd, 0, 2);
		lseek(src_fd, 0, 0);
		close(src_fd);
	}

	/* Build header string: "src <size> <path>\n" */
	header = calloc(1024, 1);
	i = 0;
	header[i] = 's'; i = i + 1;
	header[i] = 'r'; i = i + 1;
	header[i] = 'c'; i = i + 1;
	header[i] = ' '; i = i + 1;
	/* Copy size digits */
	{
		char* size_str;
		int j;
		size_str = int2str(src_size, 10, 0);
		for(j = 0; size_str[j] != 0; j = j + 1)
		{
			header[i] = size_str[j];
			i = i + 1;
		}
	}
	header[i] = ' '; i = i + 1;
	/* Copy path */
	{
		int j;
		for(j = 0; argv[2][j] != 0; j = j + 1)
		{
			header[i] = argv[2][j];
			i = i + 1;
		}
	}
	header[i] = '\n'; i = i + 1;
	header_len = i;

	/* Append header and source directly to accumulator (seek to end) */
	buf = calloc(BUF_SIZE, 1);

	acc_out = open(argv[1], O_WRONLY, 0600);
	if(acc_out == -1)
	{
		fputs("bh0header: cannot open accumulator\n", stderr);
		exit(EXIT_FAILURE);
	}
	lseek(acc_out, 0, 2);

	/* Append header */
	write(acc_out, header, header_len);

	/* Append source file content if given */
	if(argc >= 4)
	{
		src_fd = open(argv[3], 0, 0);
		bytes = read(src_fd, buf, BUF_SIZE);
		while(bytes > 0)
		{
			write(acc_out, buf, bytes);
			bytes = read(src_fd, buf, BUF_SIZE);
		}
		close(src_fd);
	}

	close(acc_out);

	free(buf);
	free(header);
	return 0;
}
