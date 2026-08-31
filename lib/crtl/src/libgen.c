/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: POSIX basename() and dirname().
 *
 * The edge cases ARE the specification here, and they are the reason this is
 * not four lines of strrchr. Verified row by row against glibc:
 *
 *   path        basename   dirname
 *   "/usr/lib"  "lib"      "/usr"
 *   "/usr/"     "usr"      "/"
 *   "usr"       "usr"      "."
 *   "/"         "/"        "/"
 *   "."         "."        "."
 *   ".."        ".."       "."
 *   ""          "."        "."
 *   NULL        "."        "."
 *   "//"        "/"        "//"     <- exactly two slashes: preserved
 *   "///"       "/"        "/"
 *   "a//b//"    "b"        "a"
 *
 * Trailing slashes are stripped BEFORE the last component is found (so
 * "/usr/" is "usr", not ""), and a path that is all slashes is "/" -- except
 * that dirname("//") is "//", the implementation-defined two-slash prefix
 * POSIX allows and glibc keeps. Those rules are what a strrchr one-liner gets
 * wrong.
 *
 * Both write into the caller's buffer, which POSIX permits and callers rely
 * on: dirname("/usr/lib") returns a pointer to the same array with the '/'
 * before "lib" replaced by NUL. The static "." and "/" are returned for the
 * degenerate cases, so the result is not always inside the argument.
 */
#include <libgen.h>

static char pxx_dot[] = ".";
static char pxx_slash[] = "/";

char *basename(char *path)
{
  char *p, *end;

  if (path == 0 || path[0] == 0) return pxx_dot;

  /* strip trailing slashes */
  end = path;
  while (*end) end++;
  while (end > path && end[-1] == '/') end--;
  if (end == path) return pxx_slash;   /* the path was all slashes */
  *end = 0;

  p = end;
  while (p > path && p[-1] != '/') p--;
  return p;
}

char *dirname(char *path)
{
  char *end, *p;

  if (path == 0 || path[0] == 0) return pxx_dot;

  end = path;
  while (*end) end++;
  while (end > path && end[-1] == '/') end--;
  /* All slashes. POSIX makes a path beginning with EXACTLY two slashes an
     implementation-defined prefix, and glibc preserves that one case only:
     dirname("//") is "//", while "///" and "////" are plain "/". Both halves
     measured against glibc, not assumed. */
  if (end == path) {
    if (path[0] == '/' && path[1] == '/' && path[2] == 0) return path;
    return pxx_slash;
  }

  /* back over the last component */
  p = end;
  while (p > path && p[-1] != '/') p--;
  if (p == path) return pxx_dot;       /* no directory part at all */

  /* back over the slashes separating it from the directory */
  while (p > path && p[-1] == '/') p--;
  if (p == path) return pxx_slash;     /* the directory IS the root */

  *p = 0;
  return path;
}
