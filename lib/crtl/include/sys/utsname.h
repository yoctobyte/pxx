/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_SYS_UTSNAME_H
#define PXX_CRTL_SYS_UTSNAME_H 1

/* 65, not 64: the kernel's new_utsname fields are 65 bytes each and the struct
   is six of them back to back -- 390 bytes, no padding. Measured against glibc
   (offsets 0,65,130,195,260,325), because the kernel fills this and the layout
   is an ABI fact rather than a choice. */
#define _UTSNAME_LENGTH 65

struct utsname {
  char sysname[_UTSNAME_LENGTH];
  char nodename[_UTSNAME_LENGTH];
  char release[_UTSNAME_LENGTH];
  char version[_UTSNAME_LENGTH];
  char machine[_UTSNAME_LENGTH];
  char domainname[_UTSNAME_LENGTH];
};
/* glibc spells the last field __domainname unless _GNU_SOURCE is defined.
   Accept both spellings so code written against either compiles unchanged. */
#define __domainname domainname

int uname(struct utsname *buf);

#endif
