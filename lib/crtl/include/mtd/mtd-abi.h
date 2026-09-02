/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <mtd/mtd-abi.h> -- the MTD (raw flash) ioctl interface.
 *
 * struct mtd_info_user IS NOT PACKED AND THAT IS THE WHOLE PROBLEM. `__u8
 * type' is followed by five __u32 and then a __u64, so the compiler inserts
 * three bytes after `type' and four before `padding' -- 32 bytes, not 25. A
 * transcription that reordered the fields, or that made `type' an int to
 * "tidy" it, still compiles and still fills every field; MEMGETINFO then
 * reports a flash size read out of the erasesize slot, and flashcp writes the
 * wrong number of bytes to a device that cannot be un-written. The layout is
 * asserted in the test rather than trusted.
 *
 * MEMGETBADBLOCK TAKES A __kernel_loff_t -- 64 bits on EVERY architecture,
 * i386 included. The type is inside the ioctl NUMBER via _IOW's size field, so
 * spelling it `off_t' produces a different request on a 32-bit build: the
 * kernel rejects it, and a caller that ignores the error scans a chip and
 * reports no bad blocks at all.
 *
 * Found attempting busybox on i386: miscutils/nandwrite.c, flashcp.c,
 * flash_eraseall.c, flash_lock_unlock.c, ubirename.c.
 * feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_MTD_ABI_H
#define _CRTL_MTD_ABI_H

#include <linux/types.h>
#include <sys/ioctl.h>

struct erase_info_user {
  __u32 start;
  __u32 length;
};

struct erase_info_user64 {
  __u64 start;
  __u64 length;
};

struct mtd_oob_buf {
  __u32 start;
  __u32 length;
  unsigned char *ptr;
};

struct mtd_oob_buf64 {
  __u64 start;
  __u32 pad;
  __u32 length;
  __u64 usr_ptr;
};

/* Operation modes for MEMWRITE/MEMREAD. */
#define MTD_OPS_PLACE_OOB  0
#define MTD_OPS_AUTO_OOB   1
#define MTD_OPS_RAW        2

struct mtd_write_req {
  __u64 start;
  __u64 len;
  __u64 ooblen;
  __u64 usr_data;
  __u64 usr_oob;
  __u8  mode;
  __u8  padding[7];
};

struct mtd_read_req_ecc_stats {
  __u32 uncorrectable_errors;
  __u32 corrected_bitflips;
  __u32 max_bitflips;
};

struct mtd_read_req {
  __u64 start;
  __u64 len;
  __u64 ooblen;
  __u64 usr_data;
  __u64 usr_oob;
  __u8  mode;
  __u8  padding[7];
  struct mtd_read_req_ecc_stats ecc_stats;
};

/* Device types. */
#define MTD_ABSENT      0
#define MTD_RAM         1
#define MTD_ROM         2
#define MTD_NORFLASH    3
#define MTD_NANDFLASH   4   /* SLC NAND */
#define MTD_DATAFLASH   6
#define MTD_UBIVOLUME   7
#define MTD_MLCNANDFLASH 8  /* MLC NAND (including TLC) */

#define MTD_WRITEABLE            0x400   /* Device is writeable */
#define MTD_BIT_WRITEABLE        0x800   /* Single bits can be flipped */
#define MTD_NO_ERASE             0x1000  /* No erase necessary */
#define MTD_POWERUP_LOCK         0x2000  /* Always locked after reset */
#define MTD_SLC_ON_MLC_EMULATION 0x4000  /* Emulate SLC behavior on MLC NANDs */

/* Some common devices / combinations of capabilities. */
#define MTD_CAP_ROM       0
#define MTD_CAP_RAM       (MTD_WRITEABLE | MTD_BIT_WRITEABLE | MTD_NO_ERASE)
#define MTD_CAP_NORFLASH  (MTD_WRITEABLE | MTD_BIT_WRITEABLE)
#define MTD_CAP_NANDFLASH (MTD_WRITEABLE)
#define MTD_CAP_NVRAM     (MTD_WRITEABLE | MTD_BIT_WRITEABLE | MTD_NO_ERASE)

/* Obsolete ECC byte placement modes (used with MTD_NANDECC_*). */
#define MTD_NANDECC_OFF        0
#define MTD_NANDECC_PLACE      1
#define MTD_NANDECC_AUTOPLACE  2
#define MTD_NANDECC_PLACEONLY  3
#define MTD_NANDECC_AUTOPL_USR 4

/* OTP mode selection. */
#define MTD_OTP_OFF      0
#define MTD_OTP_FACTORY  1
#define MTD_OTP_USER     2

struct mtd_info_user {
  __u8  type;
  __u32 flags;
  __u32 size;       /* Total size of the MTD */
  __u32 erasesize;
  __u32 writesize;
  __u32 oobsize;    /* Amount of OOB data per block (e.g. 16) */
  __u64 padding;    /* Old obsolete field; do not use */
};

struct region_info_user {
  __u32 offset;      /* At which this region starts */
  __u32 erasesize;   /* For this region */
  __u32 numblocks;   /* Number of blocks in this region */
  __u32 regionindex;
};

struct otp_info {
  __u32 start;
  __u32 length;
  __u32 locked;
};

#define MEMGETINFO         _IOR('M', 1, struct mtd_info_user)
#define MEMERASE           _IOW('M', 2, struct erase_info_user)
#define MEMWRITEOOB        _IOWR('M', 3, struct mtd_oob_buf)
#define MEMREADOOB         _IOWR('M', 4, struct mtd_oob_buf)
#define MEMLOCK            _IOW('M', 5, struct erase_info_user)
#define MEMUNLOCK          _IOW('M', 6, struct erase_info_user)
#define MEMGETREGIONCOUNT  _IOR('M', 7, int)
#define MEMGETREGIONINFO   _IOWR('M', 8, struct region_info_user)
#define MEMGETOOBSEL       _IOR('M', 10, struct nand_oobinfo)
#define MEMGETBADBLOCK     _IOW('M', 11, __kernel_loff_t)
#define MEMSETBADBLOCK     _IOW('M', 12, __kernel_loff_t)
#define OTPSELECT          _IOR('M', 13, int)
#define OTPGETREGIONCOUNT  _IOW('M', 14, int)
#define OTPGETREGIONINFO   _IOW('M', 15, struct otp_info)
#define OTPLOCK            _IOR('M', 16, struct otp_info)
#define ECCGETLAYOUT       _IOR('M', 17, struct nand_ecclayout_user)
#define ECCGETSTATS        _IOR('M', 18, struct mtd_ecc_stats)
#define MTDFILEMODE        _IO('M', 19)
#define MEMERASE64         _IOW('M', 20, struct erase_info_user64)
#define MEMWRITEOOB64      _IOWR('M', 21, struct mtd_oob_buf64)
#define MEMREADOOB64       _IOWR('M', 22, struct mtd_oob_buf64)
#define MEMISLOCKED        _IOR('M', 23, struct erase_info_user)
#define MEMWRITE           _IOWR('M', 24, struct mtd_write_req)
#define OTPERASE           _IOW('M', 25, struct otp_info)
#define MEMREAD            _IOWR('M', 26, struct mtd_read_req)

/* Obsolete, but MEMGETOOBSEL still names it. */
struct nand_oobinfo {
  __u32 useecc;
  __u32 eccbytes;
  __u32 oobfree[8][2];
  __u32 eccpos[32];
};

struct nand_oobfree {
  __u32 offset;
  __u32 length;
};

#define MTD_MAX_OOBFREE_ENTRIES  8
#define MTD_MAX_ECCPOS_ENTRIES   64

struct nand_ecclayout_user {
  __u32 eccbytes;
  __u32 eccpos[MTD_MAX_ECCPOS_ENTRIES];
  __u32 oobavail;
  struct nand_oobfree oobfree[MTD_MAX_OOBFREE_ENTRIES];
};

struct mtd_ecc_stats {
  __u32 corrected;
  __u32 failed;
  __u32 badblocks;
  __u32 bbtblocks;
};

/* Read/write file modes for MTDFILEMODE. */
#define MTD_FILE_MODE_NORMAL       MTD_OTP_OFF
#define MTD_FILE_MODE_OTP_FACTORY  MTD_OTP_FACTORY
#define MTD_FILE_MODE_OTP_USER     MTD_OTP_USER
#define MTD_FILE_MODE_RAW          3

#endif
