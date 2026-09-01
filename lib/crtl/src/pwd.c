/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: /etc/passwd lookups.
 *
 * Needed by busybox: ash's `~user' expansion, libbb/bb_pwd.c, and
 * libbb/get_shell_name.c. Found by attempting the target
 * (feature-c-corpus-busybox-multi-applet).
 *
 * NO NSS. glibc would consult nsswitch.conf and may answer from LDAP, systemd,
 * or a network directory; this reads /etc/passwd and nothing else. That is a
 * real behavioural difference and it is deliberate rather than an oversight: a
 * libc-free runtime cannot dlopen a name-service module, and a system whose
 * users live only in a directory service will get "no such user" here where
 * glibc would find one. It is the right answer for the targets pxx exists for
 * (a minimal system with the compiler on it) and the wrong one on a corporate
 * workstation. Callers that must not care are already checking for NULL.
 *
 * A line longer than the buffer is SKIPPED rather than truncated. Truncation
 * would silently produce a user whose home directory is a prefix of the real
 * one, which is exactly the kind of plausible-wrong-value this codebase keeps
 * paying for; a skipped line at worst answers "no such user".
 */
#include <pwd.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#define PW_LINE_MAX 1024

static FILE *pw_fp;
static char pw_line[PW_LINE_MAX];
static struct passwd pw_ent;

/* Split `s' at the next ':' , NUL-terminating it, and return the start of the
   field after it (or NULL at end of line). Empty fields are legal and common
   -- pw_passwd is usually "x" but pw_gecos is often empty. */
static char *pw_field(char *s, char **next) {
  char *p = s;
  if (!s) { *next = 0; return 0; }
  while (*p && *p != ':' && *p != '\n') p++;
  if (*p == '\0') { *next = 0; return s; }
  *p = '\0';
  *next = p + 1;
  return s;
}

/* Parse one /etc/passwd line in place. Returns 0 on a line that is not a valid
   entry (a comment, a blank, or one with too few fields) -- those are skipped,
   not treated as end of file. */
static int pw_parse(char *line) {
  char *rest;
  char *f[7];
  int i;

  if (line[0] == '#' || line[0] == '\n' || line[0] == '\0') return 0;

  rest = line;
  for (i = 0; i < 7; i++) {
    if (!rest) return 0;          /* fewer than seven fields */
    f[i] = pw_field(rest, &rest);
    if (!f[i]) return 0;
  }
  /* Trailing newline on the last field. */
  {
    char *e = f[6] + strlen(f[6]);
    while (e > f[6] && (e[-1] == '\n' || e[-1] == '\r')) *--e = '\0';
  }

  pw_ent.pw_name   = f[0];
  pw_ent.pw_passwd = f[1];
  pw_ent.pw_uid    = (uid_t)strtoul(f[2], 0, 10);
  pw_ent.pw_gid    = (gid_t)strtoul(f[3], 0, 10);
  pw_ent.pw_gecos  = f[4];
  pw_ent.pw_dir    = f[5];
  pw_ent.pw_shell  = f[6];
  return 1;
}

void setpwent(void) {
  if (pw_fp) { fclose(pw_fp); pw_fp = 0; }
  pw_fp = fopen("/etc/passwd", "r");
}

void endpwent(void) {
  if (pw_fp) { fclose(pw_fp); pw_fp = 0; }
}

struct passwd *getpwent(void) {
  if (!pw_fp) {
    pw_fp = fopen("/etc/passwd", "r");
    if (!pw_fp) return 0;
  }
  while (fgets(pw_line, (int)sizeof pw_line, pw_fp)) {
    /* A line that did not fit has no newline: drain it and skip, rather than
       parsing the tail as if it were a fresh entry. */
    if (!strchr(pw_line, '\n')) {
      int c;
      while ((c = fgetc(pw_fp)) != '\n' && c != EOF) { }
      continue;
    }
    if (pw_parse(pw_line)) return &pw_ent;
  }
  return 0;
}

struct passwd *getpwnam(const char *name) {
  struct passwd *p;
  if (!name) return 0;
  setpwent();
  while ((p = getpwent()) != 0)
    if (strcmp(p->pw_name, name) == 0) { endpwent(); return p; }
  endpwent();
  return 0;
}

struct passwd *getpwuid(uid_t uid) {
  struct passwd *p;
  setpwent();
  while ((p = getpwent()) != 0)
    if (p->pw_uid == uid) { endpwent(); return p; }
  endpwent();
  return 0;
}
