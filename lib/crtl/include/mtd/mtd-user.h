/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <mtd/mtd-user.h>.
 *
 * FIVE TYPEDEFS OVER <mtd/mtd-abi.h> AND NOTHING ELSE -- that is the whole
 * header upstream, and it is worth having as its own file rather than folding
 * in because it is the name every program includes. The ABI lives next door.
 *
 * Found attempting busybox on i386: miscutils/nandwrite.c, flashcp.c,
 * flash_eraseall.c, flash_lock_unlock.c, ubirename.c.
 * feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_MTD_USER_H
#define _CRTL_MTD_USER_H

#include <mtd/mtd-abi.h>

typedef struct mtd_info_user       mtd_info_t;
typedef struct erase_info_user     erase_info_t;
typedef struct region_info_user    region_info_t;
typedef struct nand_oobinfo        nand_oobinfo_t;
typedef struct nand_ecclayout_user nand_ecclayout_t;

#endif
