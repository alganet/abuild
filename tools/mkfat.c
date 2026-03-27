/* SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com> */
/* SPDX-License-Identifier: GPL-3.0-or-later */

/* mkfat: Creates an empty FAT32 filesystem image with MBR partition table.
 * Usage: mkfat <output-file> <size-in-mb>
 *
 * Creates a disk image with:
 * - MBR with one EFI System Partition (type 0xEF)
 * - FAT32 filesystem starting at sector 2048
 * - Cluster size: 4096 bytes (8 sectors)
 * - Two FAT copies, empty root directory
 */

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include "M2libc/bootstrappable.h"

#define SECTOR_SIZE 512
#define CLUSTER_SIZE 4096
#define SECTORS_PER_CLUSTER 8
#define RESERVED_SECTORS 32
#define NUM_FATS 2
#define PARTITION_START 2048
#define FILE_MODE 0644

void write_byte(int fd, int value) {
  char buf;
  buf = value & 0xFF;
  write(fd, &buf, 1);
}

void write_le16(int fd, int value) {
  write_byte(fd, value & 0xFF);
  write_byte(fd, (value >> 8) & 0xFF);
}

void write_le32(int fd, int value) {
  write_byte(fd, value & 0xFF);
  write_byte(fd, (value >> 8) & 0xFF);
  write_byte(fd, (value >> 16) & 0xFF);
  write_byte(fd, (value >> 24) & 0xFF);
}

void write_zeros(int fd, int count) {
  int i;
  for (i = 0; i < count; i = i + 1) {
    write_byte(fd, 0);
  }
}

void write_string(int fd, char* str, int len) {
  int i;
  for (i = 0; i < len; i = i + 1) {
    if (str[i] != 0) {
      write_byte(fd, str[i]);
    } else {
      write_byte(fd, ' ');
    }
  }
}

/* Seek to a specific byte offset in the file */
void seek_to(int fd, int offset) {
  lseek(fd, offset, 0);
}

int main(int argc, char** argv) {
  int fd;
  int size_mb;
  int total_sectors;
  int partition_sectors;
  int total_clusters;
  int data_sectors;
  int fat_sectors;
  int data_start_sector;
  int root_cluster;
  int i;
  int remain;
  int to_write;
  char* zbuf;

  if (argc < 3) {
    fputs("Usage: mkfat <output-file> <size-in-mb>\n", stderr);
    exit(EXIT_FAILURE);
  }

  size_mb = strtoint(argv[2]);
  total_sectors = size_mb * 2048; /* 2048 sectors per MB */
  partition_sectors = total_sectors - PARTITION_START;

  /* Calculate FAT size iteratively: fat_sectors depends on total_clusters,
   * which depends on fat_sectors.  Start with an overestimate and converge. */
  total_clusters = partition_sectors / SECTORS_PER_CLUSTER;
  fat_sectors = ((total_clusters * 4) + SECTOR_SIZE - 1) / SECTOR_SIZE;

  /* Recompute with data area only (exclude reserved + FAT sectors) */
  data_start_sector = RESERVED_SECTORS + (NUM_FATS * fat_sectors);
  data_sectors = partition_sectors - data_start_sector;
  total_clusters = data_sectors / SECTORS_PER_CLUSTER;

  /* Recompute FAT size for the corrected cluster count */
  fat_sectors = ((total_clusters * 4) + SECTOR_SIZE - 1) / SECTOR_SIZE;
  data_start_sector = RESERVED_SECTORS + (NUM_FATS * fat_sectors);
  root_cluster = 2; /* First data cluster is always cluster 2 */

  fd = open(argv[1], O_WRONLY | O_CREAT | O_TRUNC, FILE_MODE);
  if (fd == -1) {
    fputs("Error: Cannot open output file\n", stderr);
    exit(EXIT_FAILURE);
  }

  /* ============================================================ */
  /* MBR (Sector 0)                                               */
  /* ============================================================ */

  /* Boot code area (zeroed) */
  write_zeros(fd, 446);

  /* Partition entry 1: EFI System Partition */
  write_byte(fd, 0x00);     /* Status: not bootable */
  write_zeros(fd, 3);       /* CHS of first sector (ignored for LBA) */
  write_byte(fd, 0xEF);     /* Type: EFI System Partition */
  write_zeros(fd, 3);       /* CHS of last sector (ignored for LBA) */
  write_le32(fd, PARTITION_START);        /* LBA of first sector */
  write_le32(fd, partition_sectors);      /* Number of sectors */

  /* Partition entries 2-4: empty */
  write_zeros(fd, 48);

  /* MBR signature */
  write_byte(fd, 0x55);
  write_byte(fd, 0xAA);

  /* ============================================================ */
  /* FAT32 Boot Sector (at PARTITION_START)                       */
  /* ============================================================ */
  seek_to(fd, PARTITION_START * SECTOR_SIZE);

  /* Jump instruction */
  write_byte(fd, 0xEB);
  write_byte(fd, 0x58);     /* Jump to offset 0x5A */
  write_byte(fd, 0x90);     /* NOP */

  /* OEM Name */
  write_string(fd, "MKFAT   ", 8);

  /* BIOS Parameter Block (BPB) */
  write_le16(fd, SECTOR_SIZE);           /* Bytes per sector */
  write_byte(fd, SECTORS_PER_CLUSTER);   /* Sectors per cluster */
  write_le16(fd, RESERVED_SECTORS);      /* Reserved sectors */
  write_byte(fd, NUM_FATS);             /* Number of FATs */
  write_le16(fd, 0);                    /* Root entry count (0 for FAT32) */
  write_le16(fd, 0);                    /* Total sectors 16-bit (0 for FAT32) */
  write_byte(fd, 0xF8);                 /* Media descriptor: fixed disk */
  write_le16(fd, 0);                    /* Sectors per FAT (16-bit, 0 for FAT32) */
  write_le16(fd, 63);                   /* Sectors per track */
  write_le16(fd, 255);                  /* Number of heads */
  write_le32(fd, PARTITION_START);       /* Hidden sectors (partition offset) */
  write_le32(fd, partition_sectors);     /* Total sectors 32-bit */

  /* FAT32 Extended BPB */
  write_le32(fd, fat_sectors);           /* Sectors per FAT (32-bit) */
  write_le16(fd, 0);                    /* Extended flags */
  write_le16(fd, 0);                    /* FS version */
  write_le32(fd, root_cluster);          /* Root cluster */
  write_le16(fd, 1);                    /* FSInfo sector */
  write_le16(fd, 6);                    /* Backup boot sector */
  write_zeros(fd, 12);                  /* Reserved */
  write_byte(fd, 0x80);                 /* Drive number */
  write_byte(fd, 0x00);                 /* Reserved */
  write_byte(fd, 0x29);                 /* Extended boot signature */
  write_le32(fd, 0x12345678);           /* Volume serial number */
  write_string(fd, "NO NAME    ", 11);  /* Volume label */
  write_string(fd, "FAT32   ", 8);      /* FS type */

  /* Boot code (zeroed) */
  write_zeros(fd, 420);

  /* Boot sector signature */
  write_byte(fd, 0x55);
  write_byte(fd, 0xAA);

  /* ============================================================ */
  /* FSInfo Sector (at PARTITION_START + 1)                       */
  /* ============================================================ */
  seek_to(fd, (PARTITION_START + 1) * SECTOR_SIZE);

  write_le32(fd, 0x41615252);           /* FSInfo signature 1 */
  write_zeros(fd, 480);                 /* Reserved */
  write_le32(fd, 0x61417272);           /* FSInfo signature 2 */
  write_le32(fd, total_clusters - 1);   /* Free cluster count */
  write_le32(fd, 3);                    /* Next free cluster hint */
  write_zeros(fd, 12);                  /* Reserved */
  write_le32(fd, 0xAA550000);           /* FSInfo trailing signature */

  /* ============================================================ */
  /* Backup Boot Sector (at PARTITION_START + 6)                  */
  /* ============================================================ */
  /* Copy the boot sector to sector 6 */
  /* For simplicity, we re-write the critical fields */
  seek_to(fd, (PARTITION_START + 6) * SECTOR_SIZE);

  /* Jump instruction */
  write_byte(fd, 0xEB);
  write_byte(fd, 0x58);
  write_byte(fd, 0x90);

  write_string(fd, "MKFAT   ", 8);

  write_le16(fd, SECTOR_SIZE);
  write_byte(fd, SECTORS_PER_CLUSTER);
  write_le16(fd, RESERVED_SECTORS);
  write_byte(fd, NUM_FATS);
  write_le16(fd, 0);
  write_le16(fd, 0);
  write_byte(fd, 0xF8);
  write_le16(fd, 0);
  write_le16(fd, 63);
  write_le16(fd, 255);
  write_le32(fd, PARTITION_START);
  write_le32(fd, partition_sectors);
  write_le32(fd, fat_sectors);
  write_le16(fd, 0);
  write_le16(fd, 0);
  write_le32(fd, root_cluster);
  write_le16(fd, 1);
  write_le16(fd, 6);
  write_zeros(fd, 12);
  write_byte(fd, 0x80);
  write_byte(fd, 0x00);
  write_byte(fd, 0x29);
  write_le32(fd, 0x12345678);
  write_string(fd, "NO NAME    ", 11);
  write_string(fd, "FAT32   ", 8);
  write_zeros(fd, 420);
  write_byte(fd, 0x55);
  write_byte(fd, 0xAA);

  /* ============================================================ */
  /* FAT 1 (at PARTITION_START + RESERVED_SECTORS)                */
  /* ============================================================ */
  seek_to(fd, (PARTITION_START + RESERVED_SECTORS) * SECTOR_SIZE);

  /* Cluster 0: Media descriptor */
  write_le32(fd, 0x0FFFFFF8);
  /* Cluster 1: End-of-chain marker */
  write_le32(fd, 0x0FFFFFFF);
  /* Cluster 2: Root directory (end-of-chain) */
  write_le32(fd, 0x0FFFFFFF);

  /* Rest of FAT 1 is zeros (free clusters) */

  /* ============================================================ */
  /* FAT 2 (at PARTITION_START + RESERVED_SECTORS + fat_sectors)  */
  /* ============================================================ */
  seek_to(fd, (PARTITION_START + RESERVED_SECTORS + fat_sectors) * SECTOR_SIZE);

  /* Same initial entries as FAT 1 */
  write_le32(fd, 0x0FFFFFF8);
  write_le32(fd, 0x0FFFFFFF);
  write_le32(fd, 0x0FFFFFFF);

  /* ============================================================ */
  /* Root Directory Cluster (first data cluster = cluster 2)      */
  /* ============================================================ */
  seek_to(fd, (PARTITION_START + data_start_sector) * SECTOR_SIZE);

  /* Empty root directory (all zeros) - one cluster of zeros */
  write_zeros(fd, CLUSTER_SIZE);

  /* ============================================================ */
  /* Zero-fill remainder of disk image                            */
  /* (chunked write instead of seek - UEFI doesn't extend sparse)*/
  /* ============================================================ */
  remain = (total_sectors * SECTOR_SIZE)
    - ((PARTITION_START + data_start_sector) * SECTOR_SIZE)
    - CLUSTER_SIZE;
  zbuf = calloc(SECTOR_SIZE, 1);
  while (remain > 0) {
    to_write = SECTOR_SIZE;
    if (remain < SECTOR_SIZE) to_write = remain;
    write(fd, zbuf, to_write);
    remain = remain - to_write;
  }
  free(zbuf);

  close(fd);
  return EXIT_SUCCESS;
}
