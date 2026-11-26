/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <ar.h>, the common `ar` archive format (System V / GNU, the one
 * binutils and toybox ar write): an 8-byte magic, then per member a 60-byte
 * header of space-padded ASCII fields and the member's bytes, padded to an
 * even length. GNU make's arscan.c reads archives through it (the
 * `lib(member)` targets).
 */
#ifndef _CRTL_AR_H
#define _CRTL_AR_H

#define ARMAG  "!<arch>\n"   /* the archive's first 8 bytes */
#define SARMAG 8
#define ARFMAG "`\n"         /* ends every member header */

struct ar_hdr {
  char ar_name[16];   /* member name, "/"-terminated in the GNU variant */
  char ar_date[12];   /* modification time, decimal seconds since the Epoch */
  char ar_uid[6];     /* decimal */
  char ar_gid[6];     /* decimal */
  char ar_mode[8];    /* octal */
  char ar_size[10];   /* member size in bytes, decimal */
  char ar_fmag[2];    /* ARFMAG */
};

#endif
