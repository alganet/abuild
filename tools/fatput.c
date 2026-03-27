/* SPDX-FileCopyrightText: 2025 Alexandre Gomes Gaigalas <alganet@gmail.com> */
/* SPDX-License-Identifier: GPL-3.0-or-later */

/* fatput: Writes a file or creates a directory in a FAT32 image.
 * Usage: fatput <image> <path>          (create directory)
 *        fatput <image> <path> <source> (copy file)
 *
 * Handles FAT32 BPB parsing, cluster allocation, VFAT long filenames.
 */

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "M2libc/bootstrappable.h"

#define SECTOR_SIZE 512
#define MAX_PATH 1024
#define FILE_MODE 0644
#define DIR_ENTRY_SIZE 32
#define ENTRIES_PER_SECTOR 16

/* FAT32 BPB fields we care about */
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

/* navigate_path sets this global to point into the path string at the
 * basename component, avoiding the need for char** parameters. */
char* nav_basename;

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

/* Write a little-endian 16-bit value to a buffer */
void buf_write_le16(char* buf, int offset, int value) {
  buf[offset] = value & 0xFF;
  buf[offset + 1] = (value >> 8) & 0xFF;
}

/* Write a little-endian 32-bit value to a buffer */
void buf_write_le32(char* buf, int offset, int value) {
  buf[offset] = value & 0xFF;
  buf[offset + 1] = (value >> 8) & 0xFF;
  buf[offset + 2] = (value >> 16) & 0xFF;
  buf[offset + 3] = (value >> 24) & 0xFF;
}

/* Get the byte offset for a given cluster number */
int cluster_offset(int cluster) {
  return (bpb_data_start + ((cluster - 2) * bpb_sectors_per_cluster)) * SECTOR_SIZE;
}

/* Get the byte offset for a FAT entry (in FAT 1) */
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

/* Write a FAT entry to both FAT copies */
void fat_write(int cluster, int value) {
  char* buf;
  buf = calloc(4, sizeof(char));
  buf_write_le32(buf, 0, value);
  /* Write to FAT 1 */
  lseek(img_fd, fat_entry_offset(cluster), 0);
  write(img_fd, buf, 4);
  /* Write to FAT 2 */
  lseek(img_fd, fat_entry_offset(cluster) + (bpb_sectors_per_fat * SECTOR_SIZE), 0);
  write(img_fd, buf, 4);
  free(buf);
}

/* Allocate a free cluster, mark it as end-of-chain */
int alloc_cluster() {
  int c;
  c = 2;
  while (1) {
    if (fat_read(c) == 0) {
      fat_write(c, 0x0FFFFFFF);
      return c;
    }
    c = c + 1;
  }
}

/* Parse FAT32 BPB from the image */
void parse_bpb() {
  char* buf;
  char* mbr;

  buf = calloc(512, sizeof(char));
  mbr = calloc(512, sizeof(char));

  /* Read MBR to find partition start */
  lseek(img_fd, 0, 0);
  read(img_fd, mbr, 512);
  bpb_partition_start = read_le32(mbr, 446 + 8);

  /* Read BPB */
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

/* Check if a name fits in 8.3 format */
int is_short_name(char* name) {
  int len;
  int dot_pos;
  int i;

  len = strlen(name);
  if (len == 0 || len > 12) return 0;

  dot_pos = -1;
  for (i = 0; i < len; i = i + 1) {
    if (name[i] == '.') {
      if (dot_pos >= 0) return 0; /* Multiple dots */
      dot_pos = i;
    }
  }

  if (dot_pos < 0) {
    /* No dot: name must be <= 8 chars */
    return len <= 8;
  }

  /* Name part <= 8, extension <= 3 */
  if (dot_pos > 8) return 0;
  if ((len - dot_pos - 1) > 3) return 0;
  return 1;
}

/* Check if a short name exists in a directory cluster.
 * Returns 1 if found, 0 if not. */
int short_name_exists(int dir_cluster, char* short_name) {
  int entries_per_cluster;
  int offset;
  int i;
  int cluster;
  char* buf;

  entries_per_cluster = bpb_cluster_size / DIR_ENTRY_SIZE;
  buf = calloc(DIR_ENTRY_SIZE + 1, sizeof(char));

  cluster = dir_cluster;
  while (1) {
    offset = cluster_offset(cluster);
    for (i = 0; i < entries_per_cluster; i = i + 1) {
      lseek(img_fd, offset + (i * DIR_ENTRY_SIZE), 0);
      read(img_fd, buf, DIR_ENTRY_SIZE);

      if (buf[0] == 0) {
        free(buf);
        return 0;
      }
      if ((buf[0] & 0xFF) == 0xE5) {
        continue;
      }
      if ((buf[11] & 0x0F) == 0x0F) {
        continue;
      }
      if (0 == strncmp(buf, short_name, 11)) {
        free(buf);
        return 1;
      }
    }
    cluster = fat_read(cluster);
    if (cluster >= 0x0FFFFFF8) {
      break;
    }
  }
  free(buf);
  return 0;
}

/* Generate 8.3 short name from a long name.
 * If the name fits in 8.3, use it directly (uppercased).
 * Otherwise, truncate and add ~N suffix, checking dir_cluster for collisions. */
void make_short_name(char* name, char* out, int dir_cluster) {
  int i;
  int len;
  int dot_pos;
  int base_len;
  int ext_len;
  int tilde_num;

  len = strlen(name);

  /* Fill with spaces */
  for (i = 0; i < 11; i = i + 1) {
    out[i] = ' ';
  }
  out[11] = 0;

  /* Find last dot */
  dot_pos = -1;
  for (i = 0; i < len; i = i + 1) {
    if (name[i] == '.') {
      dot_pos = i;
    }
  }

  if (is_short_name(name)) {
    /* Direct conversion to 8.3 */
    if (dot_pos < 0) {
      for (i = 0; i < len && i < 8; i = i + 1) {
        out[i] = to_upper(name[i]);
      }
    } else {
      for (i = 0; i < dot_pos && i < 8; i = i + 1) {
        out[i] = to_upper(name[i]);
      }
      ext_len = len - dot_pos - 1;
      for (i = 0; i < ext_len && i < 3; i = i + 1) {
        out[8 + i] = to_upper(name[dot_pos + 1 + i]);
      }
    }
  } else {
    /* Truncated name with ~N, incrementing N until unique */
    base_len = 6;
    if (dot_pos >= 0 && dot_pos < 6) {
      base_len = dot_pos;
    }

    /* Set extension first (doesn't change with tilde number) */
    if (dot_pos >= 0) {
      ext_len = len - dot_pos - 1;
      for (i = 0; i < ext_len && i < 3; i = i + 1) {
        out[8 + i] = to_upper(name[dot_pos + 1 + i]);
      }
    }

    /* Try ~1, ~2, ~3, ... until we find a unique short name */
    tilde_num = 1;
    while (tilde_num < 100) {
      for (i = 0; i < base_len; i = i + 1) {
        out[i] = to_upper(name[i]);
      }
      out[base_len] = '~';
      if (tilde_num < 10) {
        out[base_len + 1] = '0' + tilde_num;
      } else {
        out[base_len] = '~';
        out[base_len + 1] = '0' + (tilde_num / 10);
        /* Need to shrink base to fit 2-digit number */
        if (base_len + 2 < 8) {
          out[base_len + 2] = '0' + (tilde_num % 10);
        } else {
          out[base_len - 1] = '~';
          out[base_len] = '0' + (tilde_num / 10);
          out[base_len + 1] = '0' + (tilde_num % 10);
        }
      }

      if (short_name_exists(dir_cluster, out) == 0) {
        return;
      }
      tilde_num = tilde_num + 1;
    }
  }
}

/* Compute the checksum of an 8.3 short name for LFN entries */
int lfn_checksum(char* short_name) {
  int sum;
  int i;
  sum = 0;
  for (i = 0; i < 11; i = i + 1) {
    sum = (((sum & 1) << 7) + (sum >> 1) + (short_name[i] & 0xFF)) & 0xFF;
  }
  return sum;
}

/* Write a VFAT long filename entry at the given directory offset.
 * seq is the sequence number (1-based, last entry has 0x40 OR'd). */
void write_lfn_entry(int dir_offset, int entry_index, int seq, char* name,
                     int name_offset, int checksum) {
  char* entry;
  int i;
  int ch;
  int pos;
  int name_len;

  entry = calloc(32, sizeof(char));
  name_len = strlen(name);

  entry[0] = seq & 0xFF;
  entry[11] = 0x0F; /* LFN attribute */
  entry[12] = 0;    /* Type */
  entry[13] = checksum & 0xFF;
  entry[26] = 0;    /* First cluster (always 0 for LFN) */
  entry[27] = 0;

  /* LFN characters are stored in UCS-2 at specific offsets:
   * Bytes 1-10:  chars 0-4  (5 chars, 2 bytes each)
   * Bytes 14-25: chars 5-10 (6 chars, 2 bytes each)
   * Bytes 28-31: chars 11-12 (2 chars, 2 bytes each) */

  /* Characters 0-4 (bytes 1-10) */
  for (i = 0; i < 5; i = i + 1) {
    pos = name_offset + i;
    if (pos < name_len) {
      ch = name[pos] & 0xFF;
    } else if (pos == name_len) {
      ch = 0; /* Null terminator */
    } else {
      ch = 0xFFFF; /* Padding */
    }
    entry[1 + (i * 2)] = ch & 0xFF;
    entry[1 + (i * 2) + 1] = (ch >> 8) & 0xFF;
  }

  /* Characters 5-10 (bytes 14-25) */
  for (i = 0; i < 6; i = i + 1) {
    pos = name_offset + 5 + i;
    if (pos < name_len) {
      ch = name[pos] & 0xFF;
    } else if (pos == name_len) {
      ch = 0;
    } else {
      ch = 0xFFFF;
    }
    entry[14 + (i * 2)] = ch & 0xFF;
    entry[14 + (i * 2) + 1] = (ch >> 8) & 0xFF;
  }

  /* Characters 11-12 (bytes 28-31) */
  for (i = 0; i < 2; i = i + 1) {
    pos = name_offset + 11 + i;
    if (pos < name_len) {
      ch = name[pos] & 0xFF;
    } else if (pos == name_len) {
      ch = 0;
    } else {
      ch = 0xFFFF;
    }
    entry[28 + (i * 2)] = ch & 0xFF;
    entry[28 + (i * 2) + 1] = (ch >> 8) & 0xFF;
  }

  lseek(img_fd, dir_offset + (entry_index * DIR_ENTRY_SIZE), 0);
  write(img_fd, entry, DIR_ENTRY_SIZE);
  free(entry);
}

/* Zero out a cluster */
void zero_cluster(int cluster) {
  char* zeros;
  int offset;
  int j;

  zeros = calloc(SECTOR_SIZE, sizeof(char));
  offset = cluster_offset(cluster);
  for (j = 0; j < bpb_sectors_per_cluster; j = j + 1) {
    lseek(img_fd, offset + (j * SECTOR_SIZE), 0);
    write(img_fd, zeros, SECTOR_SIZE);
  }
  free(zeros);
}

/* Find a free directory entry slot (or slots for LFN).
 * Returns the entry index within the cluster.
 * If the directory cluster is full, allocates a new one. */
int find_free_entries(int dir_cluster, int count) {
  char* buf;
  int offset;
  int i;
  int run;
  int run_start;
  int entries_per_cluster;
  int new_cluster;

  buf = calloc(32, sizeof(char));
  entries_per_cluster = bpb_cluster_size / DIR_ENTRY_SIZE;
  offset = cluster_offset(dir_cluster);

  run = 0;
  run_start = 0;

  for (i = 0; i < entries_per_cluster; i = i + 1) {
    lseek(img_fd, offset + (i * DIR_ENTRY_SIZE), 0);
    read(img_fd, buf, 1);
    if ((buf[0] == 0) || ((buf[0] & 0xFF) == 0xE5)) {
      if (run == 0) {
        run_start = i;
      }
      run = run + 1;
      if (run >= count) {
        free(buf);
        return run_start;
      }
    } else {
      run = 0;
    }
  }

  free(buf);

  /* Directory full - allocate new cluster */
  new_cluster = alloc_cluster();

  /* Chain the new cluster */
  fat_write(dir_cluster, new_cluster);

  /* Zero out the new cluster */
  zero_cluster(new_cluster);

  return find_free_entries(new_cluster, count);
}

/* Find or create a subdirectory within a directory cluster.
 * Returns the cluster number of the subdirectory. */
int find_or_create_dir(int parent_cluster, char* name) {
  char* buf;
  char* short_name;
  char* lfn_name;
  int lfn_pos;
  int lfn_offset;
  int seq_num;
  int offset;
  int i;
  int j;
  int entries_per_cluster;
  int cluster;
  int entry_index;
  int num_lfn;
  int name_len;
  int checksum;
  int new_cluster;
  int found;
  int end_of_dir;
  int seq;

  buf = calloc(32, sizeof(char));
  short_name = calloc(12, sizeof(char));
  lfn_name = calloc(256, sizeof(char));

  entries_per_cluster = bpb_cluster_size / DIR_ENTRY_SIZE;

  /* Search for existing directory by long filename */
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
        /* LFN entry - extract characters into lfn_name */
        seq_num = buf[0] & 0x3F;
        lfn_offset = (seq_num - 1) * 13;
        /* chars 0-4 at bytes 1,3,5,7,9 */
        for (j = 0; j < 5; j = j + 1) {
          if (lfn_offset + j < 255) {
            lfn_name[lfn_offset + j] = buf[1 + (j * 2)];
          }
        }
        /* chars 5-10 at bytes 14,16,18,20,22,24 */
        for (j = 0; j < 6; j = j + 1) {
          if (lfn_offset + 5 + j < 255) {
            lfn_name[lfn_offset + 5 + j] = buf[14 + (j * 2)];
          }
        }
        /* chars 11-12 at bytes 28,30 */
        for (j = 0; j < 2; j = j + 1) {
          if (lfn_offset + 11 + j < 255) {
            lfn_name[lfn_offset + 11 + j] = buf[28 + (j * 2)];
          }
        }
        lfn_pos = 1;
      } else if (buf[11] & 0x10) {
        /* Directory entry - compare by long name if available, else short name */
        if (lfn_pos != 0 && 0 == strcmp(lfn_name, name)) {
          found = 1;
        } else if (lfn_pos == 0) {
          /* No LFN - compare by short name (for 8.3 names) */
          make_short_name(name, short_name, parent_cluster);
          if (0 == strncmp(buf, short_name, 11)) {
            found = 1;
          }
        }
        /* Reset LFN buffer for next entry */
        for (j = 0; j < 256; j = j + 1) {
          lfn_name[j] = 0;
        }
        lfn_pos = 0;
      } else {
        lfn_pos = 0;
        for (j = 0; j < 256; j = j + 1) {
          lfn_name[j] = 0;
        }
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
    int result;
    result = (read_le16(buf, 20) << 16) | read_le16(buf, 26);
    free(buf);
    free(short_name);
    free(lfn_name);
    return result;
  }

  /* Create the directory */
  make_short_name(name, short_name, parent_cluster);
  name_len = strlen(name);
  if (is_short_name(name)) {
    num_lfn = 0;
  } else {
    num_lfn = (name_len + 12) / 13;
  }

  entry_index = find_free_entries(parent_cluster, num_lfn + 1);

  /* Write LFN entries */
  if (num_lfn > 0) {
    checksum = lfn_checksum(short_name);
    for (i = num_lfn; i >= 1; i = i - 1) {
      seq = i;
      if (i == num_lfn) {
        seq = seq | 0x40; /* Last LFN entry marker */
      }
      write_lfn_entry(cluster_offset(parent_cluster), entry_index + (num_lfn - i),
                       seq, name, (i - 1) * 13, checksum);
    }
  }

  /* Allocate cluster for new directory */
  new_cluster = alloc_cluster();

  /* Write short name entry */
  for (i = 0; i < 32; i = i + 1) {
    buf[i] = 0;
  }
  for (i = 0; i < 11; i = i + 1) {
    buf[i] = short_name[i];
  }
  buf[11] = 0x10; /* Directory attribute */
  buf_write_le16(buf, 20, (new_cluster >> 16) & 0xFFFF);
  buf_write_le16(buf, 26, new_cluster & 0xFFFF);
  buf_write_le32(buf, 28, 0); /* Size: 0 for directories */

  lseek(img_fd, cluster_offset(parent_cluster) + ((entry_index + num_lfn) * DIR_ENTRY_SIZE), 0);
  write(img_fd, buf, DIR_ENTRY_SIZE);

  /* Initialize the new directory cluster */
  zero_cluster(new_cluster);

  offset = cluster_offset(new_cluster);

  /* "." entry */
  for (i = 0; i < 32; i = i + 1) {
    buf[i] = 0;
  }
  buf[0] = '.';
  for (i = 1; i < 11; i = i + 1) {
    buf[i] = ' ';
  }
  buf[11] = 0x10;
  buf_write_le16(buf, 20, (new_cluster >> 16) & 0xFFFF);
  buf_write_le16(buf, 26, new_cluster & 0xFFFF);
  lseek(img_fd, offset, 0);
  write(img_fd, buf, DIR_ENTRY_SIZE);

  /* ".." entry */
  for (i = 0; i < 32; i = i + 1) {
    buf[i] = 0;
  }
  buf[0] = '.';
  buf[1] = '.';
  for (i = 2; i < 11; i = i + 1) {
    buf[i] = ' ';
  }
  buf[11] = 0x10;
  if (parent_cluster == bpb_root_cluster) {
    buf_write_le16(buf, 20, 0);
    buf_write_le16(buf, 26, 0);
  } else {
    buf_write_le16(buf, 20, (parent_cluster >> 16) & 0xFFFF);
    buf_write_le16(buf, 26, parent_cluster & 0xFFFF);
  }
  lseek(img_fd, offset + DIR_ENTRY_SIZE, 0);
  write(img_fd, buf, DIR_ENTRY_SIZE);

  free(buf);
  free(short_name);
  return new_cluster;
}

/* Navigate to (or create) the directory for a given path.
 * Returns the cluster of the final directory.
 * Sets nav_basename global to point to the filename component. */
int navigate_path(char* path) {
  int cluster;
  char* component;
  int i;
  int j;
  int k;
  int len;

  component = calloc(256, sizeof(char));
  cluster = bpb_root_cluster;
  len = strlen(path);

  /* Skip leading slash */
  i = 0;
  if (path[0] == '/') {
    i = 1;
  }

  /* Find last slash to separate directory from filename */
  j = len;
  while (j > i) {
    j = j - 1;
    if (path[j] == '/') {
      j = j + 1;
      break;
    }
    if (j == i) {
      /* No more slashes - the rest is the basename */
      break;
    }
  }

  nav_basename = path + j;

  /* Navigate directory components */
  while (i < j) {
    k = 0;
    while (i < j && path[i] != '/') {
      component[k] = path[i];
      k = k + 1;
      i = i + 1;
    }
    component[k] = 0;
    if (k > 0) {
      cluster = find_or_create_dir(cluster, component);
    }
    if (i < j && path[i] == '/') {
      i = i + 1;
    }
  }

  free(component);
  return cluster;
}

/* Write a file to the FAT32 image at the given path */
void write_file(char* dest_path, char* source_path) {
  int src_fd;
  char* basename;
  int dir_cluster;
  int first_cluster;
  int prev_cluster;
  int curr_cluster;
  int file_size;
  int bytes_written;
  int to_read;
  int bytes_read;
  char* read_buf;
  char* short_name;
  char* entry;
  int entry_index;
  int num_lfn;
  int name_len;
  int checksum;
  int i;
  int seq;

  src_fd = open(source_path, O_RDONLY, 0);
  if (src_fd == -1) {
    fputs("Error: Cannot open source file: ", stderr);
    fputs(source_path, stderr);
    fputs("\n", stderr);
    exit(EXIT_FAILURE);
  }

  /* Get file size */
  file_size = lseek(src_fd, 0, 2);
  lseek(src_fd, 0, 0);

  dir_cluster = navigate_path(dest_path);
  basename = nav_basename;

  short_name = calloc(12, sizeof(char));
  make_short_name(basename, short_name, dir_cluster);

  name_len = strlen(basename);
  if (is_short_name(basename)) {
    num_lfn = 0;
  } else {
    num_lfn = (name_len + 12) / 13;
  }

  entry_index = find_free_entries(dir_cluster, num_lfn + 1);

  /* Write LFN entries */
  if (num_lfn > 0) {
    checksum = lfn_checksum(short_name);
    for (i = num_lfn; i >= 1; i = i - 1) {
      seq = i;
      if (i == num_lfn) {
        seq = seq | 0x40;
      }
      write_lfn_entry(cluster_offset(dir_cluster), entry_index + (num_lfn - i),
                       seq, basename, (i - 1) * 13, checksum);
    }
  }

  /* Allocate clusters and write file data */
  first_cluster = 0;
  prev_cluster = 0;
  bytes_written = 0;
  read_buf = calloc(bpb_cluster_size + 1, sizeof(char));

  while (bytes_written < file_size) {
    curr_cluster = alloc_cluster();
    if (first_cluster == 0) {
      first_cluster = curr_cluster;
    }
    if (prev_cluster != 0) {
      fat_write(prev_cluster, curr_cluster);
    }

    to_read = file_size - bytes_written;
    if (to_read > bpb_cluster_size) {
      to_read = bpb_cluster_size;
    }

    /* Zero the buffer first */
    for (i = 0; i < bpb_cluster_size; i = i + 1) {
      read_buf[i] = 0;
    }

    bytes_read = read(src_fd, read_buf, to_read);
    lseek(img_fd, cluster_offset(curr_cluster), 0);
    write(img_fd, read_buf, bpb_cluster_size);

    bytes_written = bytes_written + bytes_read;
    prev_cluster = curr_cluster;
  }

  free(read_buf);
  close(src_fd);

  /* Handle empty files (no clusters allocated) */
  if (file_size == 0) {
    first_cluster = 0;
  }

  /* Write short name directory entry */
  entry = calloc(32, sizeof(char));
  for (i = 0; i < 11; i = i + 1) {
    entry[i] = short_name[i];
  }
  entry[11] = 0x20; /* Archive attribute */
  buf_write_le16(entry, 20, (first_cluster >> 16) & 0xFFFF);
  buf_write_le16(entry, 26, first_cluster & 0xFFFF);
  buf_write_le32(entry, 28, file_size);

  lseek(img_fd, cluster_offset(dir_cluster) + ((entry_index + num_lfn) * DIR_ENTRY_SIZE), 0);
  write(img_fd, entry, DIR_ENTRY_SIZE);

  free(entry);
  free(short_name);
}

/* Create a directory at the given path */
void make_dir(char* path) {
  char* basename;
  int dir_cluster;

  dir_cluster = navigate_path(path);
  basename = nav_basename;

  if (strlen(basename) > 0) {
    find_or_create_dir(dir_cluster, basename);
  }
}

int main(int argc, char** argv) {
  if (argc < 3) {
    fputs("Usage: fatput <image> <path> [source]\n", stderr);
    exit(EXIT_FAILURE);
  }

  img_fd = open(argv[1], O_RDWR, 0);
  if (img_fd == -1) {
    fputs("Error: Cannot open image file\n", stderr);
    exit(EXIT_FAILURE);
  }

  parse_bpb();

  if (argc >= 4) {
    write_file(argv[2], argv[3]);
  } else {
    make_dir(argv[2]);
  }

  close(img_fd);
  return EXIT_SUCCESS;
}
