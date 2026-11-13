/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: /etc/shadow lookups. Shaped like pwd.c, and the same rules hold:
 * no NSS, an over-long line is SKIPPED by the plain calls (never truncated
 * into a plausible-wrong entry), and the _r form answers ERANGE instead.
 *
 * Needed by dropbear (see <shadow.h> for why on every login).
 */
#include <shadow.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>

#define SP_LINE_MAX 1024

static FILE *sp_fp;
static char sp_line[SP_LINE_MAX];
static struct spwd sp_ent;

/* An empty numeric field means "not set" and reads as -1. */
static long sp_num(const char *s) {
  if (!s || !*s) return -1;
  return strtol(s, 0, 10);
}

/* Parse one shadow(5) line in place: nine ':'-separated fields, of which the
   last (the reserved flag) may be missing on hand-written files. Returns 0 for
   a comment, a blank or a line with fewer than two fields. */
static int sp_parse(char *line, struct spwd *out) {
  char *f[9];
  char *p = line;
  int n = 0;
  char *e;

  if (line[0] == '#' || line[0] == '\n' || line[0] == '\0') return 0;
  e = line + strlen(line);
  while (e > line && (e[-1] == '\n' || e[-1] == '\r')) *--e = '\0';

  f[n++] = p;
  while (*p && n < 9) {
    if (*p == ':') { *p = '\0'; f[n++] = p + 1; }
    p++;
  }
  if (n < 2) return 0;
  while (n < 9) f[n++] = "";

  out->sp_namp   = f[0];
  out->sp_pwdp   = f[1];
  out->sp_lstchg = sp_num(f[2]);
  out->sp_min    = sp_num(f[3]);
  out->sp_max    = sp_num(f[4]);
  out->sp_warn   = sp_num(f[5]);
  out->sp_inact  = sp_num(f[6]);
  out->sp_expire = sp_num(f[7]);
  out->sp_flag   = (unsigned long)sp_num(f[8]);
  return 1;
}

void setspent(void) {
  if (sp_fp) { fclose(sp_fp); sp_fp = 0; }
  sp_fp = fopen(SHADOW, "r");
}

void endspent(void) {
  if (sp_fp) { fclose(sp_fp); sp_fp = 0; }
}

struct spwd *getspent(void) {
  if (!sp_fp) {
    sp_fp = fopen(SHADOW, "r");
    if (!sp_fp) return 0;          /* errno from fopen: EACCES for non-root */
  }
  while (fgets(sp_line, (int)sizeof sp_line, sp_fp)) {
    if (!strchr(sp_line, '\n') && !feof(sp_fp)) {
      int c;
      while ((c = fgetc(sp_fp)) != '\n' && c != EOF) { }
      continue;
    }
    if (sp_parse(sp_line, &sp_ent)) return &sp_ent;
  }
  return 0;
}

struct spwd *getspnam(const char *name) {
  struct spwd *s;
  int saved;
  if (!name) { errno = EINVAL; return 0; }
  setspent();
  if (!sp_fp) return 0;
  while ((s = getspent()) != 0)
    if (strcmp(s->sp_namp, name) == 0) { endspent(); return s; }
  saved = errno;
  endspent();
  errno = saved;
  return 0;
}

struct spwd *sgetspent(const char *s) {
  size_t n;
  if (!s) { errno = EINVAL; return 0; }
  n = strlen(s);
  if (n >= sizeof sp_line) { errno = ERANGE; return 0; }
  memcpy(sp_line, s, n + 1);
  return sp_parse(sp_line, &sp_ent) ? &sp_ent : 0;
}

int getspnam_r(const char *name, struct spwd *spbuf, char *buf, size_t buflen,
               struct spwd **result) {
  FILE *fp;

  if (result) *result = 0;
  if (!name || !spbuf || !buf || !result || buflen == 0) return EINVAL;
  fp = fopen(SHADOW, "r");
  if (!fp) return errno;
  while (fgets(buf, (int)buflen, fp)) {
    if (!strchr(buf, '\n') && !feof(fp)) { fclose(fp); return ERANGE; }
    if (!sp_parse(buf, spbuf)) continue;
    if (strcmp(spbuf->sp_namp, name) == 0) {
      fclose(fp);
      *result = spbuf;
      return 0;
    }
  }
  fclose(fp);
  return 0;
}
