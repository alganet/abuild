/* SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com> */
/* SPDX-License-Identifier: GPL-3.0-or-later */

/* diskwrite: Writes a file to the raw block device on UEFI, then shuts down.
 * This is the UEFI equivalent of the bh0 /dev/hda auto-flush.
 * Must be the last command: it overwrites the boot filesystem then resets.
 * Usage: diskwrite <source-file>
 */

#include <stdio.h>
#include <stdlib.h>
#include <bootstrappable.h>

/* EFI_BLOCK_IO_PROTOCOL - we only access media and function pointers.
 * The media struct has BOOLEAN fields (1 byte) that M2-Planet can't
 * represent, so we avoid struct field access and use raw byte offsets. */
struct efi_block_io_protocol
{
	void* revision;
	void* media;
	void* reset;
	void* read_blocks;
	void* write_blocks;
	void* flush_blocks;
};

/* Read a 4-byte little-endian unsigned from a raw byte pointer at offset */
unsigned read_u32(char* base, unsigned offset)
{
	unsigned val;
	val = base[offset] & 0xFF;
	val = val + ((base[offset + 1] & 0xFF) * 256);
	val = val + ((base[offset + 2] & 0xFF) * 65536);
	val = val + ((base[offset + 3] & 0xFF) * 16777216);
	return val;
}

/* Read a 8-byte little-endian unsigned from a raw byte pointer at offset */
unsigned read_u64(char* base, unsigned offset)
{
	unsigned lo;
	unsigned hi;
	lo = read_u32(base, offset);
	hi = read_u32(base, offset + 4);
	return lo + (hi * 4294967296);
}

int main(int argc, char** argv)
{
	struct efi_guid block_io_guid;
	struct efi_block_io_protocol* block_io;
	void* handle_buffer;
	unsigned handle_count;
	unsigned i;
	unsigned j;
	unsigned rval;
	FILE* f;
	struct efi_file_protocol* raw_file;
	unsigned file_size;
	char* buffer;
	unsigned best_blocks;
	struct efi_block_io_protocol* best_bio;
	char* media;
	unsigned last_block;
	unsigned zero;
	unsigned chunk_size;
	unsigned lba;
	unsigned bytes_left;
	unsigned block_size;
	unsigned disk_size;
	unsigned to_write;
	unsigned to_read;
	unsigned read_size;

	if(argc < 2)
	{
		fputs("Usage: diskwrite <source-file>\n", stderr);
		exit(1);
	}

	/* EFI_BLOCK_IO_PROTOCOL GUID: 964e5b21-6459-11d2-8e39-00a0c969723b */
	block_io_guid.data1 = 0x964e5b21;
	block_io_guid.data2 = 0x6459;
	block_io_guid.data3 = 0x11d2;
	block_io_guid.data4[0] = 0x8e;
	block_io_guid.data4[1] = 0x39;
	block_io_guid.data4[2] = 0x00;
	block_io_guid.data4[3] = 0xa0;
	block_io_guid.data4[4] = 0xc9;
	block_io_guid.data4[5] = 0x69;
	block_io_guid.data4[6] = 0x72;
	block_io_guid.data4[7] = 0x3b;

	/* Locate block I/O handles */
	handle_count = 0;
	handle_buffer = 0;
	rval = __uefi_5(2, &block_io_guid, 0, &handle_count, &handle_buffer, _system->boot_services->locate_handle_buffer);
	if(rval != 0)
	{
		fputs("diskwrite: failed to locate block devices\n", stderr);
		exit(2);
	}

	fputs("diskwrite: found ", stderr);
	fputs(int2str(handle_count, 10, 0), stderr);
	fputs(" block device(s)\n", stderr);

	/* Find the block device with the most blocks (whole disk) */
	best_blocks = 0;
	best_bio = 0;
	for(i = 0; i < handle_count; i = i + 1)
	{
		void* handle;
		struct efi_block_io_protocol* bio;
		handle = ((void**)handle_buffer)[i];
		rval = __uefi_3(handle, &block_io_guid, &bio, _system->boot_services->handle_protocol);
		if(rval == 0)
		{
			/* EFI_BLOCK_IO_MEDIA layout (packed with BOOLEAN bytes):
			 *   offset 0:  UINT32 MediaId
			 *   offset 4:  BOOLEAN RemovableMedia (1 byte)
			 *   offset 5:  BOOLEAN MediaPresent (1 byte)
			 *   offset 6:  BOOLEAN LogicalPartition (1 byte)
			 *   offset 7:  BOOLEAN ReadOnly (1 byte)
			 *   offset 8:  BOOLEAN WriteCaching (1 byte)
			 *   offset 12: UINT32 BlockSize (aligned)
			 *   offset 16: UINT32 IoAlign
			 *   offset 20: padding (4 bytes for 8-byte alignment)
			 *   offset 24: UINT64 LastBlock
			 */
			media = bio->media;
			last_block = read_u64(media, 24);
			fputs("diskwrite: device ", stderr);
			fputs(int2str(i, 10, 0), stderr);
			fputs(" last_block=", stderr);
			fputs(int2str(last_block, 10, 0), stderr);
			fputs("\n", stderr);

			if(last_block > best_blocks)
			{
				best_blocks = last_block;
				best_bio = bio;
			}
		}
	}

	if(best_bio == 0)
	{
		fputs("diskwrite: no block device found\n", stderr);
		exit(3);
	}

	block_io = best_bio;
	fputs("diskwrite: using device with ", stderr);
	fputs(int2str(best_blocks, 10, 0), stderr);
	fputs(" blocks\n", stderr);

	/* Open source file using raw UEFI file protocol (bypass M2libc stdio
	 * which reads entire file into memory and can't handle large files) */
	fputs("diskwrite: opening file\n", stderr);
	f = fopen(argv[1], "r");
	if(f == 0)
	{
		fputs("diskwrite: cannot open source file\n", stderr);
		exit(4);
	}

	/* Get file size by seeking to end (more reliable than GetInfo on UEFI) */
	raw_file = f->fd;
	file_size = 0xFFFFFFFFFFFFFFFF;
	__uefi_2(raw_file, &file_size, raw_file->set_position);
	__uefi_2(raw_file, &file_size, raw_file->get_position);
	fputs("diskwrite: file size = ", stderr);
	fputs(int2str(file_size, 10, 0), stderr);
	fputs("\n", stderr);

	/* Seek back to start */
	zero = 0;
	__uefi_2(raw_file, &zero, raw_file->set_position);

	/* Write to block device in chunks using raw UEFI file Read */
	media = block_io->media;

	block_size = read_u32(media, 12);
	fputs("diskwrite: block_size=", stderr);
	fputs(int2str(block_size, 10, 0), stderr);
	fputs("\n", stderr);

	/* Allocate one chunk (64KB aligned to block_size) */
	chunk_size = 65536;
	buffer = calloc(chunk_size, 1);
	if(buffer == 0)
	{
		fputs("diskwrite: alloc failed\n", stderr);
		exit(5);
	}

	/* Total disk size from block device */
	disk_size = (best_blocks + 1) * block_size;
	fputs("diskwrite: disk size = ", stderr);
	fputs(int2str(disk_size, 10, 0), stderr);
	fputs(" file size = ", stderr);
	fputs(int2str(file_size, 10, 0), stderr);
	fputs("\n", stderr);

	/* Write entire disk: read from file until EOF, pad zeros after.
	 * Don't trust file_size - UEFI GetInfo may underreport. */
	lba = 0;
	bytes_left = disk_size;
	i = 1;
	while(bytes_left > 0)
	{
		to_write = chunk_size;
		if(bytes_left < chunk_size) to_write = bytes_left;

		/* Try reading from file (i tracks whether EOF reached) */
		read_size = 0;
		if(i != 0)
		{
			read_size = to_write;
			__uefi_3(raw_file, &read_size, buffer, raw_file->read);
			if(read_size == 0) i = 0;
		}

		/* Zero-fill from end of read data to end of chunk */
		for(j = read_size; j < to_write; j = j + 1)
		{
			buffer[j] = 0;
		}

		/* Write chunk to block device */
		rval = __uefi_5(block_io, read_u32(media, 0), lba, to_write, buffer, block_io->write_blocks);
		if(rval != 0)
		{
			fputs("diskwrite: write failed at lba ", stderr);
			fputs(int2str(lba, 10, 0), stderr);
			fputs("\n", stderr);
			exit(6);
		}

		lba = lba + (to_write / block_size);
		bytes_left = bytes_left - to_write;
	}

	/* Flush */
	__uefi_1(block_io, block_io->flush_blocks);

	fputs("diskwrite: done, wrote ", stderr);
	fputs(int2str(disk_size, 10, 0), stderr);
	fputs(" bytes\n", stderr);

	free(buffer);

	/* Shutdown: the disk we just wrote over is our boot filesystem,
	 * so shutdown.efi can't be loaded as a separate binary anymore.
	 * Stall to let serial buffer flush, then reset. */
	fputs("Shutting down\n", stdout);
	__uefi_1(15000000, _system->boot_services->stall);
	__uefi_4(0, 0, 0, 0, _system->runtime_services->reset_system);
	return 0;
}
