/* SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com> */
/* SPDX-License-Identifier: GPL-3.0-or-later */

/* fatget: Extracts a file from a FAT32 image.
 * Usage: fatget <image> <fat-path> <output-file>
 *
 * Read-only counterpart of fatput.
 */

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "M2libc/bootstrappable.h"

#define SECTOR_SIZE 512
#define DIR_ENTRY_SIZE 32

/* FAT32 BPB fields */
int bpb_bytes_per_sector;
int bpb_sectors_per_cluster;
int bpb_reserved_sectors;
int bpb_num_fats;
int bpb_sectors_per_fat;
int bpb_root_cluster;
int bpb_partition_start;
int bpb_cluster_size;
int bpb_fat_start;
int bpb_data_start;

int img_fd;

/* Read a little-endian 16-bit value from buffer */
int read_le16(char* buf, int offset) {
  int lo;
  int hi;
  lo = buf[offset] & 0xFF;
  hi = buf[offset + 1] & 0xFF;
  return lo | (hi << 8);
}

/* Read a little-endian 32-bit value from buffer */
int read_le32(char* buf, int offset) {
  int b0;
  int b1;
  int b2;
  int b3;
  b0 = buf[offset] & 0xFF;
  b1 = buf[offset + 1] & 0xFF;
  b2 = buf[offset + 2] & 0xFF;
  b3 = buf[offset + 3] & 0xFF;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
}

/* Get the byte offset for a given cluster number */
int cluster_offset(int cluster) {
  return (bpb_data_start + ((cluster - 2) * bpb_sectors_per_cluster)) * SECTOR_SIZE;
}

/* Get the byte offset for a FAT entry */
int fat_entry_offset(int cluster) {
  return (bpb_fat_start * SECTOR_SIZE) + (cluster * 4);
}

/* Read a FAT entry */
int fat_read(int cluster) {
  char* buf;
  int val;
  buf = calloc(4, sizeof(char));
  lseek(img_fd, fat_entry_offset(cluster), 0);
  read(img_fd, buf, 4);
  val = read_le32(buf, 0) & 0x0FFFFFFF;
  free(buf);
  return val;
}

/* Parse FAT32 BPB from the image */
void parse_bpb() {
  char* buf;
  char* mbr;

  buf = calloc(512, sizeof(char));
  mbr = calloc(512, sizeof(char));

  lseek(img_fd, 0, 0);
  read(img_fd, mbr, 512);
  bpb_partition_start = read_le32(mbr, 446 + 8);

  lseek(img_fd, bpb_partition_start * SECTOR_SIZE, 0);
  read(img_fd, buf, 512);

  bpb_bytes_per_sector = read_le16(buf, 11);
  bpb_sectors_per_cluster = buf[13] & 0xFF;
  bpb_reserved_sectors = read_le16(buf, 14);
  bpb_num_fats = buf[16] & 0xFF;
  bpb_sectors_per_fat = read_le32(buf, 36);
  bpb_root_cluster = read_le32(buf, 44);

  bpb_cluster_size = bpb_sectors_per_cluster * SECTOR_SIZE;
  bpb_fat_start = bpb_partition_start + bpb_reserved_sectors;
  bpb_data_start = bpb_fat_start + (bpb_num_fats * bpb_sectors_per_fat);

  free(buf);
  free(mbr);
}

/* Convert a character to uppercase */
int to_upper(int c) {
  if (c >= 'a' && c <= 'z') {
    return c - 32;
  }
  return c;
}

/* Find a named entry in a directory cluster chain.
 * Returns the start cluster of the found entry, or -1 if not found.
 * Sets *file_size to the file size from the directory entry. */
int find_entry(int parent_cluster, char* name, int* file_size) {
  char* buf;
  char* lfn_name;
  char* short_cmp;
  int lfn_pos;
  int lfn_offset;
  int seq_num;
  int offset;
  int i;
  int j;
  int k;
  int entries_per_cluster;
  int cluster;
  int found;
  int end_of_dir;
  int name_len;
  int result;

  buf = calloc(32, sizeof(char));
  lfn_name = calloc(256, sizeof(char));
  short_cmp = calloc(12, sizeof(char));

  entries_per_cluster = bpb_cluster_size / DIR_ENTRY_SIZE;

  found = 0;
  end_of_dir = 0;
  lfn_pos = 0;
  cluster = parent_cluster;
  while (found == 0 && end_of_dir == 0) {
    offset = cluster_offset(cluster);
    for (i = 0; i < entries_per_cluster && found == 0 && end_of_dir == 0; i = i + 1) {
      lseek(img_fd, offset + (i * DIR_ENTRY_SIZE), 0);
      read(img_fd, buf, DIR_ENTRY_SIZE);

      if (buf[0] == 0) {
        end_of_dir = 1;
      } else if ((buf[0] & 0xFF) == 0xE5) {
        lfn_pos = 0;
      } else if ((buf[11] & 0x0F) == 0x0F) {
        /* LFN entry */
        seq_num = buf[0] & 0x3F;
        lfn_offset = (seq_num - 1) * 13;
        for (j = 0; j < 5; j = j + 1) {
          if (lfn_offset + j < 255) {
            lfn_name[lfn_offset + j] = buf[1 + (j * 2)];
          }
        }
        for (j = 0; j < 6; j = j + 1) {
          if (lfn_offset + 5 + j < 255) {
            lfn_name[lfn_offset + 5 + j] = buf[14 + (j * 2)];
          }
        }
        for (j = 0; j < 2; j = j + 1) {
          if (lfn_offset + 11 + j < 255) {
            lfn_name[lfn_offset + 11 + j] = buf[28 + (j * 2)];
          }
        }
        lfn_pos = 1;
      } else {
        /* Regular entry (file or directory) */
        if (lfn_pos != 0 && 0 == strcmp(lfn_name, name)) {
          found = 1;
        } else if (lfn_pos == 0) {
          /* Compare by short name: build 8.3 padded uppercase from name */
          name_len = strlen(name);
          for (j = 0; j < 11; j = j + 1) {
            short_cmp[j] = ' ';
          }
          short_cmp[11] = 0;
          j = 0;
          for (k = 0; k < name_len && j < 11; k = k + 1) {
            if (name[k] == '.') {
              j = 8;
            } else {
              short_cmp[j] = to_upper(name[k]);
              j = j + 1;
            }
          }
          /* Restore i for outer loop (won't matter, found will be set) */
          if (0 == strncmp(buf, short_cmp, 11)) {
            found = 1;
          }
        }
        /* Reset LFN */
        for (j = 0; j < 256; j = j + 1) {
          lfn_name[j] = 0;
        }
        lfn_pos = 0;
      }
    }

    if (found == 0 && end_of_dir == 0) {
      cluster = fat_read(cluster);
      if (cluster >= 0x0FFFFFF8) {
        end_of_dir = 1;
      }
    }
  }

  if (found) {
    result = (read_le16(buf, 20) << 16) | read_le16(buf, 26);
    *file_size = read_le32(buf, 28);
    free(buf);
    free(lfn_name);
    free(short_cmp);
    return result;
  }

  free(buf);
  free(lfn_name);
  free(short_cmp);
  return -1;
}

/* Navigate a path, returning the cluster of the final component.
 * Sets *file_size for the final component. */
int navigate_and_find(char* path, int* file_size) {
  int cluster;
  char* component;
  int i;
  int k;
  int len;
  int dummy_size;

  component = calloc(256, sizeof(char));
  cluster = bpb_root_cluster;
  len = strlen(path);
  dummy_size = 0;

  /* Skip leading slash */
  i = 0;
  if (path[0] == '/') {
    i = 1;
  }

  /* Walk each component */
  while (i < len) {
    k = 0;
    while (i < len && path[i] != '/') {
      component[k] = path[i];
      k = k + 1;
      i = i + 1;
    }
    component[k] = 0;

    if (k > 0) {
      if (i >= len) {
        /* Last component - this is the file we want */
        cluster = find_entry(cluster, component, file_size);
      } else {
        /* Directory component */
        cluster = find_entry(cluster, component, &dummy_size);
      }
      if (cluster == -1) {
        fputs("fatget: path not found: ", stderr);
        fputs(component, stderr);
        fputs("\n", stderr);
        free(component);
        return -1;
      }
    }

    if (i < len && path[i] == '/') {
      i = i + 1;
    }
  }

  free(component);
  return cluster;
}

int main(int argc, char** argv) {
  int file_cluster;
  int file_size;
  int out_fd;
  int cluster;
  int to_write;
  char* buf;

  if (argc < 4) {
    fputs("Usage: fatget <image> <fat-path> <output-file>\n", stderr);
    exit(EXIT_FAILURE);
  }

  img_fd = open(argv[1], O_RDONLY, 0);
  if (img_fd == -1) {
    fputs("Error: Cannot open image file\n", stderr);
    exit(EXIT_FAILURE);
  }

  parse_bpb();

  file_size = 0;
  file_cluster = navigate_and_find(argv[2], &file_size);
  if (file_cluster == -1) {
    fputs("Error: File not found in image\n", stderr);
    exit(EXIT_FAILURE);
  }

  out_fd = open(argv[3], O_WRONLY | O_CREAT | O_TRUNC, 0644);
  if (out_fd == -1) {
    fputs("Error: Cannot open output file\n", stderr);
    exit(EXIT_FAILURE);
  }

  /* Read file data cluster by cluster */
  buf = calloc(bpb_cluster_size, sizeof(char));
  cluster = file_cluster;
  while (file_size > 0 && cluster < 0x0FFFFFF8) {
    lseek(img_fd, cluster_offset(cluster), 0);
    read(img_fd, buf, bpb_cluster_size);

    to_write = bpb_cluster_size;
    if (file_size < bpb_cluster_size) {
      to_write = file_size;
    }
    write(out_fd, buf, to_write);

    file_size = file_size - to_write;
    cluster = fat_read(cluster);
  }

  free(buf);
  close(out_fd);
  close(img_fd);
  return 0;
}
