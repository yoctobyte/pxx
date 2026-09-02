/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <linux/loop.h>.
 *
 * TWO STATUS STRUCTS AND FOUR IOCTLS, AND THE PAIRS DO NOT INTERCHANGE.
 * LOOP_GET_STATUS takes `struct loop_info' (32-bit fields, a 16-bit
 * __kernel_old_dev_t, an `int lo_offset' that cannot address past 2GB);
 * LOOP_GET_STATUS64 takes `struct loop_info64', which is a different shape
 * entirely. Handing the kernel the 64-bit struct with the 32-bit request does
 * not fail -- the kernel copies its own struct's worth of bytes into a longer
 * buffer, and every field the caller reads after lo_offset is stale stack.
 * busybox's libbb/loop.c typedefs bb_loop_info to loop_info64 and picks the
 * matching request; that pairing is the whole content of the file.
 *
 * `struct loop_info' IS NOT DEAD CODE HERE even though nothing in crtl calls
 * it: it is what the 32-bit ioctl means, and its presence is what lets the
 * test above assert that the two are different sizes.
 *
 * Found attempting busybox on i386: libbb/loop.c.
 * feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_LINUX_LOOP_H
#define _CRTL_LINUX_LOOP_H

#include <linux/types.h>

#define LO_NAME_SIZE  64
#define LO_KEY_SIZE   32

/* Flags. */
#define LO_FLAGS_READ_ONLY  1
#define LO_FLAGS_AUTOCLEAR  4
#define LO_FLAGS_PARTSCAN   8
#define LO_FLAGS_DIRECT_IO  16

#define LOOP_SET_STATUS_SETTABLE_FLAGS  (LO_FLAGS_AUTOCLEAR | LO_FLAGS_PARTSCAN)
#define LOOP_SET_STATUS_CLEARABLE_FLAGS (LO_FLAGS_AUTOCLEAR)
#define LOOP_CONFIGURE_SETTABLE_FLAGS   (LO_FLAGS_READ_ONLY | LO_FLAGS_AUTOCLEAR \
                                         | LO_FLAGS_PARTSCAN | LO_FLAGS_DIRECT_IO)

struct loop_info {
  int                lo_number;         /* ioctl r/o */
  __kernel_old_dev_t lo_device;         /* ioctl r/o */
  unsigned long      lo_inode;          /* ioctl r/o */
  __kernel_old_dev_t lo_rdevice;        /* ioctl r/o */
  int                lo_offset;
  int                lo_encrypt_type;      /* obsolete, ignored */
  int                lo_encrypt_key_size;  /* ioctl w/o */
  int                lo_flags;
  char               lo_name[LO_NAME_SIZE];
  unsigned char      lo_encrypt_key[LO_KEY_SIZE];  /* ioctl w/o */
  unsigned long      lo_init[2];
  char               reserved[4];
};

struct loop_info64 {
  __u64 lo_device;              /* ioctl r/o */
  __u64 lo_inode;               /* ioctl r/o */
  __u64 lo_rdevice;             /* ioctl r/o */
  __u64 lo_offset;
  __u64 lo_sizelimit;           /* bytes, 0 == max available */
  __u32 lo_number;              /* ioctl r/o */
  __u32 lo_encrypt_type;        /* obsolete, ignored */
  __u32 lo_encrypt_key_size;    /* ioctl w/o */
  __u32 lo_flags;
  __u8  lo_file_name[LO_NAME_SIZE];
  __u8  lo_crypt_name[LO_NAME_SIZE];
  __u8  lo_encrypt_key[LO_KEY_SIZE];   /* ioctl w/o */
  __u64 lo_init[2];
};

struct loop_config {
  __u32 fd;
  __u32 block_size;
  struct loop_info64 info;
  __u64 __reserved[8];
};

/* Encryption types. All obsolete; the kernel ignores lo_encrypt_type. */
#define LO_CRYPT_NONE       0
#define LO_CRYPT_XOR        1
#define LO_CRYPT_DES        2
#define LO_CRYPT_FISH2      3   /* Twofish encryption */
#define LO_CRYPT_BLOW       4
#define LO_CRYPT_CAST128    5
#define LO_CRYPT_IDEA       6
#define LO_CRYPT_DUMMY      9
#define LO_CRYPT_SKIPJACK   10
#define LO_CRYPT_CRYPTOAPI  18
#define MAX_LO_CRYPT        20

/* /dev/loopN ioctls. */
#define LOOP_SET_FD          0x4C00
#define LOOP_CLR_FD          0x4C01
#define LOOP_SET_STATUS      0x4C02
#define LOOP_GET_STATUS      0x4C03
#define LOOP_SET_STATUS64    0x4C04
#define LOOP_GET_STATUS64    0x4C05
#define LOOP_CHANGE_FD       0x4C06
#define LOOP_SET_CAPACITY    0x4C07
#define LOOP_SET_DIRECT_IO   0x4C08
#define LOOP_SET_BLOCK_SIZE  0x4C09
#define LOOP_CONFIGURE       0x4C0A

/* /dev/loop-control ioctls. */
#define LOOP_CTL_ADD       0x4C80
#define LOOP_CTL_REMOVE    0x4C81
#define LOOP_CTL_GET_FREE  0x4C82

#endif
