/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <mntent.h> -- struct mntent, the option-name macros, and the
 * /etc/mtab readers.
 *
 * The calls were deferred until "a corpus target calls it, with the
 * field-splitting rules tested against glibc rather than guessed". busybox's
 * coreutils/df.c and libbb/find_mount_point.c are that target, and src/mntent.c
 * records which rules were measured -- the octal escapes and the optional
 * freq/passno columns in particular. addmntent is still absent: nothing in the
 * corpus WRITES mtab, and a half-written entry is worse than a missing call.
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

/* The returned struct and its strings live in the stream's own buffer and are
   invalidated by the next getmntent on that stream. */
FILE          *setmntent(const char *filename, const char *mode);
int            endmntent(FILE *fp);
struct mntent *getmntent(FILE *fp);
/* Whole-element match: `ro' does not match `errors=remount-ro'. */
char          *hasmntopt(const struct mntent *mnt, const char *opt);

#endif
