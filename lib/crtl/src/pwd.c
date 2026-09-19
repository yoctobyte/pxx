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
#include <errno.h>

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
static int pw_parse(char *line, struct passwd *out) {
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

  out->pw_name   = f[0];
  out->pw_passwd = f[1];
  out->pw_uid    = (uid_t)strtoul(f[2], 0, 10);
  out->pw_gid    = (gid_t)strtoul(f[3], 0, 10);
  out->pw_gecos  = f[4];
  out->pw_dir    = f[5];
  out->pw_shell  = f[6];
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
    if (pw_parse(pw_line, &pw_ent)) return &pw_ent;
  }
  return 0;
}

/* THE PLAIN LOOKUPS ARE NOT WRAPPERS OVER THESE, AND THE REASON IS A CONTRACT
   DIFFERENCE RATHER THAN LAZINESS. Sharing the scan is the obvious move and it
   was written that way first; it is wrong here, because the two forms must
   answer an over-long line DIFFERENTLY:

     plain  -- SKIP it and keep looking. This file's header says so outright,
               and the argument there is that a skipped line at worst answers
               "no such user" while a truncated one invents a user whose home
               directory is a prefix of the real one.
     _r     -- return ERANGE. POSIX requires it, and it is the only correct
               answer: the caller chose the buffer, so silently skipping the
               very entry they asked for would be a wrong ANSWER, and they can
               retry with a bigger one.

   Written as a wrapper, ONE over-long line anywhere in /etc/passwd turns
   getpwnam() into "no such user" for every entry after it. That is a real
   regression and it is invisible on a normal file, which is exactly why it is
   spelled out here instead of being rediscovered.

   WHAT IS SHARED IS THE PARSER, which is where duplication would actually
   hurt: pw_parse() takes its output struct, so there is one copy of "what the
   seven fields mean". The remaining overlap is a four-line match loop.

   These own their own `FILE *` and touch NO static -- sharing `pw_fp` would
   make two threads consume each other's lines, and sharing `pw_line` would
   hand the caller a struct whose fields point into a buffer another thread is
   rewriting. */
static int pw_lookup_r(const char *name, uid_t uid, int by_name,
                       struct passwd *pwd, char *buf, size_t buflen,
                       struct passwd **result) {
  FILE *fp;

  if (result) *result = 0;
  if (!pwd || !buf || !result || buflen == 0) return EINVAL;
  if (by_name && !name) return EINVAL;

  fp = fopen("/etc/passwd", "r");
  if (!fp) return ENOENT;

  while (fgets(buf, (int)buflen, fp)) {
    /* No newline has TWO causes and they need different answers: the buffer
       was too small (the caller must retry bigger -- ERANGE), or this is a
       last line with no trailing newline (perfectly normal, parse it). Telling
       them apart by feof is the only way; treating both as ERANGE would fail
       on a valid file, and treating both as a short line would silently match
       against a TRUNCATED name, which is the plausible-wrong-value shape this
       file's own header refuses for the non-reentrant path. */
    if (!strchr(buf, '\n') && !feof(fp)) { fclose(fp); return ERANGE; }

    if (!pw_parse(buf, pwd)) continue;
    if (by_name ? (strcmp(pwd->pw_name, name) == 0) : (pwd->pw_uid == uid)) {
      fclose(fp);
      *result = pwd;
      return 0;
    }
  }

  fclose(fp);
  return 0;                      /* not found: 0 with *result == NULL */
}

int getpwnam_r(const char *name, struct passwd *pwd, char *buf, size_t buflen,
               struct passwd **result) {
  return pw_lookup_r(name, (uid_t)0, 1, pwd, buf, buflen, result);
}

int getpwuid_r(uid_t uid, struct passwd *pwd, char *buf, size_t buflen,
               struct passwd **result) {
  return pw_lookup_r(0, uid, 0, pwd, buf, buflen, result);
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
