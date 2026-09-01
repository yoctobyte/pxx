/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: /etc/mtab and /proc/mounts reading.
 *
 * The header deferred this until "a corpus target calls it, with the
 * field-splitting rules tested against glibc rather than guessed". Both halves
 * are now done: busybox's coreutils/df.c and libbb/find_mount_point.c want
 * setmntent/getmntent/endmntent/hasmntopt, and the rules below were checked
 * against glibc on this box rather than reasoned about.
 *
 * WHAT GLIBC ACTUALLY DOES, measured, because two of these are easy to get
 * plausibly wrong:
 *
 *  - FIELDS ARE WHITESPACE-SEPARATED, not column-aligned, and a run of spaces
 *    or tabs is one separator.
 *  - THE OCTAL ESCAPES ARE DECODED. A mount point with a space in it is
 *    written `/mnt/my\040disk', and glibc hands back the DECODED string. A
 *    reader that skips this returns a path that does not exist, which is the
 *    plausible-wrong-value shape rather than a failure. \040 \011 \012 \134
 *    are the four the kernel emits; the decoder takes any three octal digits.
 *  - freq AND passno ARE OPTIONAL. /proc/mounts always writes them, /etc/mtab
 *    entries written by hand often do not, and glibc leaves them 0.
 *  - A COMMENT OR BLANK LINE IS SKIPPED, not end of file.
 *
 * setmntent's `mode' argument is passed straight to fopen, so a caller asking
 * for "a" gets an appendable stream -- but addmntent is NOT implemented, since
 * nothing in the corpus writes mtab and a half-written entry is worse than a
 * missing function.
 */
#include <mntent.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#define MNT_LINE_MAX 4096

struct pxx_mntstream { FILE *fp; char line[MNT_LINE_MAX]; struct mntent ent; };

/* One stream is not enough: df walks the mount table while find_mount_point
   holds one open. Two is what the corpus needs; a third caller gets NULL from
   setmntent rather than a silently shared cursor. */
static struct pxx_mntstream mnt_streams[2];
static int mnt_used[2];

/* Decode `\NNN' octal escapes in place. Returns the string, shortened. */
static char *mnt_unescape(char *s) {
  char *r = s, *w = s;
  while (*r) {
    if (r[0] == '\\' && r[1] >= '0' && r[1] <= '7' &&
                        r[2] >= '0' && r[2] <= '7' &&
                        r[3] >= '0' && r[3] <= '7') {
      *w++ = (char)(((r[1] - '0') << 6) | ((r[2] - '0') << 3) | (r[3] - '0'));
      r += 4;
    } else {
      *w++ = *r++;
    }
  }
  *w = '\0';
  return s;
}

/* Next whitespace-separated field, NUL-terminated in place; *next is the rest
   or NULL. Leading whitespace is skipped, so a run of blanks is one gap. */
static char *mnt_field(char *s, char **next) {
  char *p;
  if (!s) { *next = 0; return 0; }
  while (*s == ' ' || *s == '\t') s++;
  if (*s == '\0' || *s == '\n') { *next = 0; return 0; }
  p = s;
  while (*p && *p != ' ' && *p != '\t' && *p != '\n') p++;
  if (*p == '\0' || *p == '\n') { *p = '\0'; *next = 0; }
  else { *p = '\0'; *next = p + 1; }
  return s;
}

FILE *setmntent(const char *filename, const char *mode) {
  int i;
  for (i = 0; i < (int)(sizeof mnt_used / sizeof mnt_used[0]); i++) {
    if (mnt_used[i]) continue;
    mnt_streams[i].fp = fopen(filename, mode);
    if (!mnt_streams[i].fp) return 0;
    mnt_used[i] = 1;
    /* The handle a caller holds is the FILE*, as in glibc -- getmntent finds
       its buffer by matching it, which is what keeps the two streams apart. */
    return mnt_streams[i].fp;
  }
  return 0;
}

int endmntent(FILE *fp) {
  int i;
  if (!fp) return 1;
  for (i = 0; i < (int)(sizeof mnt_used / sizeof mnt_used[0]); i++)
    if (mnt_used[i] && mnt_streams[i].fp == fp) {
      fclose(fp);
      mnt_streams[i].fp = 0;
      mnt_used[i] = 0;
      return 1;                 /* glibc always returns 1 */
    }
  fclose(fp);
  return 1;
}

struct mntent *getmntent(FILE *fp) {
  struct pxx_mntstream *st = 0;
  char *rest, *f;
  int i;

  for (i = 0; i < (int)(sizeof mnt_used / sizeof mnt_used[0]); i++)
    if (mnt_used[i] && mnt_streams[i].fp == fp) { st = &mnt_streams[i]; break; }
  if (!st) return 0;

  while (fgets(st->line, (int)sizeof st->line, st->fp)) {
    if (st->line[0] == '#' || st->line[0] == '\n' || st->line[0] == '\0')
      continue;
    /* A line that did not fit has no newline: drain and skip, so its tail is
       never parsed as a fresh entry. */
    if (!strchr(st->line, '\n')) {
      int c;
      while ((c = fgetc(st->fp)) != '\n' && c != EOF) { }
      continue;
    }
    rest = st->line;
    st->ent.mnt_fsname = mnt_field(rest, &rest);
    st->ent.mnt_dir    = mnt_field(rest, &rest);
    st->ent.mnt_type   = mnt_field(rest, &rest);
    st->ent.mnt_opts   = mnt_field(rest, &rest);
    if (!st->ent.mnt_fsname || !st->ent.mnt_dir ||
        !st->ent.mnt_type   || !st->ent.mnt_opts)
      continue;                              /* fewer than four fields */
    f = mnt_field(rest, &rest);
    st->ent.mnt_freq   = f ? atoi(f) : 0;
    f = mnt_field(rest, &rest);
    st->ent.mnt_passno = f ? atoi(f) : 0;
    mnt_unescape(st->ent.mnt_fsname);
    mnt_unescape(st->ent.mnt_dir);
    mnt_unescape(st->ent.mnt_type);
    mnt_unescape(st->ent.mnt_opts);
    return &st->ent;
  }
  return 0;
}

/* hasmntopt(3): the option must be a WHOLE comma-separated element, not a
   substring. `ro' must not match `errors=remount-ro' and `rw' must not match
   `rwmode' -- the substring reading is the classic wrong one here, and it
   answers yes to a question nobody asked. Returns a pointer INTO mnt_opts. */
char *hasmntopt(const struct mntent *mnt, const char *opt) {
  const char *p;
  size_t n;
  if (!mnt || !mnt->mnt_opts || !opt) return 0;
  n = strlen(opt);
  if (!n) return 0;
  p = mnt->mnt_opts;
  for (;;) {
    if (strncmp(p, opt, n) == 0 && (p[n] == '\0' || p[n] == ',' || p[n] == '='))
      return (char *)p;
    p = strchr(p, ',');
    if (!p) return 0;
    p++;
  }
}
