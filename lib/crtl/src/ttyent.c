/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <ttyent.h>'s bodies -- reading /etc/ttys (see the header for
 * the format). One static entry, overwritten by the next read, as the BSD
 * interface has it.
 */
#include <ttyent.h>
#include <stdio.h>
#include <string.h>

static FILE *__crtl_ttys;
static char __crtl_ttyline[1024];
static struct ttyent __crtl_tty;

int setttyent(void)
{
  if (__crtl_ttys) { rewind(__crtl_ttys); return 1; }
  __crtl_ttys = fopen(_PATH_TTYS, "r");
  return __crtl_ttys != 0;
}

int endttyent(void)
{
  if (__crtl_ttys) {
    int rc = fclose(__crtl_ttys);
    __crtl_ttys = 0;
    return rc == 0;
  }
  return 1;
}

/* Cut the field that starts at *pp out of the line: unquote it in place,
   NUL-terminate it and leave *pp at the next field. Returns 1 when a `#'
   ended it (the rest of the line is the comment, and *pp points at it). */
static int __crtl_ttyfield(char **pp)
{
  char *r = *pp, *w = *pp;
  int quoted = 0;
  for (; *r; r++) {
    if (*r == '"') { quoted = !quoted; continue; }
    if (quoted) {
      if (*r == '\\' && r[1] == '"') r++;
      *w++ = *r;
      continue;
    }
    if (*r == '#') { *w = 0; *pp = r + 1; return 1; }
    if (*r == ' ' || *r == '\t' || *r == '\n') {
      *w = 0;
      r++;
      while (*r == ' ' || *r == '\t' || *r == '\n') r++;
      *pp = r;
      return 0;
    }
    *w++ = *r;
  }
  *w = 0;
  *pp = r;
  return 0;
}

static int __crtl_ttyflag(const char *p, const char *name)
{
  size_t n = strlen(name);
  return strncmp(p, name, n) == 0 && (p[n] == ' ' || p[n] == '\t' || p[n] == '\n' || p[n] == 0 || p[n] == '#');
}

struct ttyent *getttyent(void)
{
  char *p, *nl;
  int hash = 0;
  if (!__crtl_ttys && !setttyent()) return 0;
  for (;;) {
    if (!fgets(__crtl_ttyline, sizeof __crtl_ttyline, __crtl_ttys)) return 0;
    if (!strchr(__crtl_ttyline, '\n')) {     /* overlong: drop the rest */
      int c;
      while ((c = fgetc(__crtl_ttys)) != '\n' && c != EOF) ;
    }
    p = __crtl_ttyline;
    while (*p == ' ' || *p == '\t') p++;
    if (*p && *p != '#' && *p != '\n') break;
  }
  if ((nl = strchr(p, '\n')) != 0) *nl = 0;
  __crtl_tty.ty_name = p;
  hash = __crtl_ttyfield(&p);
  __crtl_tty.ty_getty = __crtl_tty.ty_type = 0;
  __crtl_tty.ty_status = 0;
  __crtl_tty.ty_window = 0;
  if (!hash && *p) {
    __crtl_tty.ty_getty = p;
    hash = __crtl_ttyfield(&p);
    if (!hash && *p) {
      __crtl_tty.ty_type = p;
      hash = __crtl_ttyfield(&p);
    }
  }
  while (!hash && *p) {
    if (__crtl_ttyflag(p, _TTYS_OFF)) __crtl_tty.ty_status &= ~TTY_ON;
    else if (__crtl_ttyflag(p, _TTYS_ON)) __crtl_tty.ty_status |= TTY_ON;
    else if (__crtl_ttyflag(p, _TTYS_SECURE)) __crtl_tty.ty_status |= TTY_SECURE;
    else if (strncmp(p, _TTYS_WINDOW "=", sizeof _TTYS_WINDOW) == 0) {
      /* window=CMD: the value is the field after the `=' (unquoted in
         place, so window="cmd args" gives cmd args) */
      char *start = p;
      hash = __crtl_ttyfield(&p);
      __crtl_tty.ty_window = start + sizeof _TTYS_WINDOW;
      continue;
    }
    else break;
    hash = __crtl_ttyfield(&p);
  }
  if (*p == '#') { p++; hash = 1; }
  if (hash) while (*p == ' ' || *p == '\t') p++;
  __crtl_tty.ty_comment = *p ? p : 0;
  return &__crtl_tty;
}

struct ttyent *getttynam(const char *tty)
{
  struct ttyent *t;
  setttyent();
  while ((t = getttyent()) != 0)
    if (strcmp(tty, t->ty_name) == 0) break;
  endttyent();
  return t;
}
