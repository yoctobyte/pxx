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
 * for "a" gets an appendable stream.
 *
 * UPDATE 2026-09-02: addmntent and getmntent_r are implemented too --
 * util-linux/mount.c writes /etc/mtab and util-linux/umount.c reads it with
 * the reentrant form. addmntent ESCAPES on the way out with the same four
 * characters the reader decodes on the way in; a writer that skips that
 * produces a line its own reader cannot parse back, which is the round trip
 * this pair has to survive.
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

/* Read the next line that is not blank, not a comment and not over-long, into
   `buf'. An over-long line is DRAINED and skipped rather than truncated, so its
   tail is never parsed as a fresh entry. Returns buf, or NULL at end of file. */
static char *mnt_getline(FILE *fp, char *buf, int len) {
  while (fgets(buf, len, fp)) {
    if (buf[0] == '#' || buf[0] == '\n' || buf[0] == '\0') continue;
    if (!strchr(buf, '\n')) {
      int c;
      while ((c = fgetc(fp)) != '\n' && c != EOF) { }
      continue;
    }
    return buf;
  }
  return 0;
}

/* Split one line into `e', whose char* fields point INTO the line. Returns 0
   when the line has fewer than the four mandatory fields. */
static int mnt_parse(char *line, struct mntent *e) {
  char *rest = line, *f;
  e->mnt_fsname = mnt_field(rest, &rest);
  e->mnt_dir    = mnt_field(rest, &rest);
  e->mnt_type   = mnt_field(rest, &rest);
  e->mnt_opts   = mnt_field(rest, &rest);
  if (!e->mnt_fsname || !e->mnt_dir || !e->mnt_type || !e->mnt_opts) return 0;
  f = mnt_field(rest, &rest);
  e->mnt_freq   = f ? atoi(f) : 0;
  f = mnt_field(rest, &rest);
  e->mnt_passno = f ? atoi(f) : 0;
  mnt_unescape(e->mnt_fsname);
  mnt_unescape(e->mnt_dir);
  mnt_unescape(e->mnt_type);
  mnt_unescape(e->mnt_opts);
  return 1;
}

struct mntent *getmntent(FILE *fp) {
  struct pxx_mntstream *st = 0;
  int i;

  for (i = 0; i < (int)(sizeof mnt_used / sizeof mnt_used[0]); i++)
    if (mnt_used[i] && mnt_streams[i].fp == fp) { st = &mnt_streams[i]; break; }
  if (!st) return 0;

  while (mnt_getline(st->fp, st->line, (int)sizeof st->line))
    if (mnt_parse(st->line, &st->ent)) return &st->ent;
  return 0;
}

/* getmntent_r(3): the same walk with the caller's storage, so it needs no
   stream slot at all -- it works on any FILE*, including one fopen'd directly.
   Returns mntbuf, or NULL at end of file. glibc gives no way to distinguish a
   short buffer from EOF here and neither does this. */
struct mntent *getmntent_r(FILE *fp, struct mntent *mntbuf,
                           char *buf, int buflen) {
  if (!fp || !mntbuf || !buf || buflen <= 0) return 0;
  while (mnt_getline(fp, buf, buflen))
    if (mnt_parse(buf, mntbuf)) return mntbuf;
  return 0;
}

/* Write one field with the escapes mnt_unescape decodes. The four characters
   are exactly the four the kernel emits, and they are the four that would
   otherwise re-split the line on the way back in. */
static int mnt_wr_escaped(FILE *fp, const char *s) {
  if (!s) s = "";
  for (; *s; s++) {
    int r;
    switch (*s) {
      case ' ':  r = fputs("\\040", fp); break;
      case '\t': r = fputs("\\011", fp); break;
      case '\n': r = fputs("\\012", fp); break;
      case '\\': r = fputs("\\134", fp); break;
      default:   r = fputc(*s, fp); break;
    }
    if (r < 0) return -1;
  }
  return 0;
}

/* addmntent(3): append one entry. Returns 0 on success, 1 on failure -- note
   that this is the OPPOSITE of the usual convention and is glibc's, so a
   caller testing `if (addmntent(...))' is testing for failure. */
int addmntent(FILE *fp, const struct mntent *mnt) {
  if (!fp || !mnt) return 1;
  if (fseek(fp, 0, SEEK_END) != 0) return 1;
  if (mnt_wr_escaped(fp, mnt->mnt_fsname) < 0) return 1;
  if (fputc(' ', fp) < 0) return 1;
  if (mnt_wr_escaped(fp, mnt->mnt_dir) < 0) return 1;
  if (fputc(' ', fp) < 0) return 1;
  if (mnt_wr_escaped(fp, mnt->mnt_type) < 0) return 1;
  if (fputc(' ', fp) < 0) return 1;
  if (mnt_wr_escaped(fp, mnt->mnt_opts) < 0) return 1;
  if (fprintf(fp, " %d %d\n", mnt->mnt_freq, mnt->mnt_passno) < 0) return 1;
  if (fflush(fp) != 0) return 1;
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
