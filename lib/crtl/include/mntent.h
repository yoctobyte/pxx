/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <mntent.h> -- struct mntent, the option-name macros, and the
 * /etc/mtab readers.
 *
 * The calls were deferred until "a corpus target calls it, with the
 * field-splitting rules tested against glibc rather than guessed". busybox's
 * coreutils/df.c and libbb/find_mount_point.c are that target, and src/mntent.c
 * records which rules were measured -- the octal escapes and the optional
 * freq/passno columns in particular. addmntent and getmntent_r joined them on
 * 2026-09-02, when util-linux/mount.c and umount.c reached rung 2's applet
 * list -- one writes mtab, the other reads it reentrantly.
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
/* Reentrant read into the caller's storage: needs no stream slot, so it works
   on any FILE*, including one fopen'd directly rather than via setmntent. */
struct mntent *getmntent_r(FILE *fp, struct mntent *mntbuf,
                           char *buf, int buflen);
/* Append one entry, escaping the four characters getmntent decodes.
   RETURNS 0 ON SUCCESS AND 1 ON FAILURE -- glibc's convention, the opposite of
   the usual one. */
int            addmntent(FILE *fp, const struct mntent *mnt);

#endif
