/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: /etc/group lookups.
 *
 * The header said this "belongs to whichever corpus target first calls them".
 * That target arrived: a 79-applet busybox userland wants getgrnam (libbb/
 * bb_pwd.c), getgrgid (coreutils/stat.c) and getgrouplist (coreutils/id.c).
 * Found by attempting the target, feature-c-crtl-gaps-for-a-79-applet-busybox-
 * userland.
 *
 * NO NSS, exactly as pwd.c: this reads /etc/group and nothing else. A system
 * whose groups live in a directory service gets "no such group" here where
 * glibc would find one. Deliberate -- a libc-free runtime cannot dlopen a
 * name-service module -- and the right answer for the targets pxx exists for.
 *
 * A line longer than the buffer is SKIPPED rather than truncated, for pwd.c's
 * reason: a truncated line yields a plausible wrong group rather than a
 * failure.
 *
 * THE MEMBER LIST IS THE PART THAT IS NOT LIKE pwd.c. gr_mem is a
 * NULL-terminated array of pointers, so it needs storage of its own; it points
 * into the same line buffer, and is invalidated by the next call exactly as
 * the string fields are. A group with more than GR_MEM_MAX members is reported
 * with the first GR_MEM_MAX -- the alternative is failing a lookup that only
 * wanted the gid.
 */
#include <grp.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#define GR_LINE_MAX 4096
#define GR_MEM_MAX   256

static FILE *gr_fp;
static char  gr_line[GR_LINE_MAX];
static char *gr_mem[GR_MEM_MAX + 1];
static struct group gr_ent;

/* Split at the next ':', NUL-terminating it; *next is the field after it, or
   NULL at end of line. Empty fields are legal (gr_passwd usually is). */
static char *gr_field(char *s, char **next) {
  char *p = s;
  if (!s) { *next = 0; return 0; }
  while (*p && *p != ':' && *p != '\n') p++;
  if (*p == '\0') { *next = 0; return s; }
  *p = '\0';
  *next = p + 1;
  return s;
}

/* Parse one /etc/group line in place. 0 for a line that is not an entry (a
   comment, a blank, or too few fields): skipped, not end of file. */
static int gr_parse(char *line) {
  char *rest, *f[4], *p;
  int i, n;

  if (line[0] == '#' || line[0] == '\n' || line[0] == '\0') return 0;

  rest = line;
  for (i = 0; i < 4; i++) {
    if (!rest && i < 3) return 0;      /* the member list may be absent */
    f[i] = rest ? gr_field(rest, &rest) : (char *)"";
    if (!f[i]) return 0;
  }
  /* Trailing newline on the member list. */
  p = f[3] + strlen(f[3]);
  while (p > f[3] && (p[-1] == '\n' || p[-1] == '\r')) *--p = '\0';

  /* Members: comma-separated, and an EMPTY field means zero members rather
     than one empty one -- `wheel:x:10:' is a group with nobody in it. */
  n = 0;
  if (f[3][0]) {
    p = f[3];
    while (*p && n < GR_MEM_MAX) {
      gr_mem[n++] = p;
      while (*p && *p != ',') p++;
      if (*p == ',') *p++ = '\0';
    }
  }
  gr_mem[n] = 0;

  gr_ent.gr_name   = f[0];
  gr_ent.gr_passwd = f[1];
  gr_ent.gr_gid    = (gid_t)strtoul(f[2], 0, 10);
  gr_ent.gr_mem    = gr_mem;
  return 1;
}

void setgrent(void) {
  if (gr_fp) { fclose(gr_fp); gr_fp = 0; }
  gr_fp = fopen("/etc/group", "r");
}

void endgrent(void) {
  if (gr_fp) { fclose(gr_fp); gr_fp = 0; }
}

struct group *getgrent(void) {
  if (!gr_fp) {
    gr_fp = fopen("/etc/group", "r");
    if (!gr_fp) return 0;
  }
  while (fgets(gr_line, (int)sizeof gr_line, gr_fp)) {
    /* A line that did not fit has no newline: drain and skip, rather than
       parsing its tail as a fresh entry. */
    if (!strchr(gr_line, '\n')) {
      int c;
      while ((c = fgetc(gr_fp)) != '\n' && c != EOF) { }
      continue;
    }
    if (gr_parse(gr_line)) return &gr_ent;
  }
  return 0;
}

struct group *getgrnam(const char *name) {
  struct group *g;
  if (!name) return 0;
  setgrent();
  while ((g = getgrent()) != 0)
    if (strcmp(g->gr_name, name) == 0) { endgrent(); return g; }
  endgrent();
  return 0;
}

struct group *getgrgid(gid_t gid) {
  struct group *g;
  setgrent();
  while ((g = getgrent()) != 0)
    if (g->gr_gid == gid) { endgrent(); return g; }
  endgrent();
  return 0;
}

/* getgrouplist(3): every group `user' belongs to, with `group' first whether
   or not /etc/group lists it -- that argument is the user's PRIMARY gid from
   /etc/passwd, which is not a member entry.
 *
 * The return convention is the awkward part and is glibc's: *ngroups is BOTH
 * the caller's capacity on the way in and the real count on the way out, and
 * the result is -1 when the real count exceeded the capacity. Callers size a
 * buffer from a first failing call, so writing the true count on failure is
 * load-bearing rather than informational.
 */
int getgrouplist(const char *user, gid_t group, gid_t *groups, int *ngroups) {
  struct group *g;
  int have = 0, cap;
  int i;

  if (!ngroups) return -1;
  cap = *ngroups;

  if (cap > 0 && groups) groups[0] = group;
  have = 1;

  setgrent();
  while ((g = getgrent()) != 0) {
    char **m;
    if (g->gr_gid == group) continue;        /* already carried as primary */
    if (!user || !g->gr_mem) continue;
    for (m = g->gr_mem; *m; m++) {
      if (strcmp(*m, user) != 0) continue;
      /* A group may legitimately name the user twice, and two entries may
         share a gid; neither should produce a duplicate. */
      for (i = 0; i < have && i < cap; i++)
        if (groups && groups[i] == g->gr_gid) break;
      if (i < have && i < cap) break;
      if (have < cap && groups) groups[have] = g->gr_gid;
      have++;
      break;
    }
  }
  endgrent();

  if (have > cap) { *ngroups = have; return -1; }
  *ngroups = have;
  return have;
}
