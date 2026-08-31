/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <mntent.h> -- struct mntent and the option-name macros. No
 * setmntent/getmntent/endmntent/hasmntopt.
 *
 * Same rule as <pwd.h> and <grp.h>: the type travels with the headers (this
 * one arrives in every busybox translation unit via include/libbb.h) while
 * the calls appear only in mount/umount/df. Unlike those two, this family is
 * implementable here with nothing but stdio -- /etc/mtab is a text file --
 * so its absence is scheduling, not a limitation. It gets written when a
 * corpus target calls it, with the field-splitting rules (octal escapes in
 * mnt_dir, the missing trailing freq/passno columns) tested against glibc
 * rather than guessed.
 */
#ifndef _CRTL_MNTENT_H
#define _CRTL_MNTENT_H

#include <stdio.h>

#define MNTTYPE_IGNORE  "ignore"
#define MNTTYPE_NFS     "nfs"
#define MNTTYPE_SWAP    "swap"

#define MNTOPT_DEFAULTS "defaults"
#define MNTOPT_RO       "ro"
#define MNTOPT_RW       "rw"
#define MNTOPT_SUID     "suid"
#define MNTOPT_NOSUID   "nosuid"
#define MNTOPT_NOAUTO   "noauto"

struct mntent {
  char *mnt_fsname;  /* device or remote filesystem */
  char *mnt_dir;     /* mount point */
  char *mnt_type;    /* filesystem type */
  char *mnt_opts;    /* comma-separated options */
  int   mnt_freq;    /* dump frequency, in days */
  int   mnt_passno;  /* fsck pass number */
};

#endif
