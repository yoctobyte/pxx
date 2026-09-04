/* SPDX-License-Identifier: Zlib */
/* glob(3), diffed against glibc over a tree this program builds itself.
 *
 * THE TREE IS BUILT HERE RATHER THAN BY THE MAKEFILE so that the two runs
 * cannot be comparing different filesystems. A tree laid down by a shell
 * script and then read by both binaries would still be one tree, but it
 * would also be a THIRD instrument: a `mkdir -p a/b' that half-failed would
 * make both runs agree on a wrong answer, and agreement is exactly what this
 * test reads as success. Building it in the code under test means a failure
 * to build it is a failure of this program, which is visible.
 *
 * EVERY ROW PRINTS THE RETURN CODE AS WELL AS THE PATHS, because the three
 * ways glob() can decline -- GLOB_NOMATCH, GLOB_ABORTED, GLOB_NOSPACE -- are
 * different facts and all three produce an empty gl_pathv. A row that
 * printed only the paths would read `pattern: ' for all three and pass a
 * stub that returns GLOB_NOSPACE unconditionally.
 *
 * THE ESCAPE ROWS ARE THE ONES THAT CANNOT PASS BY ACCIDENT. `a\*b' must
 * match the file literally named `a*b' and NOT the two files a?b matches;
 * an implementation that ignores backslashes returns three paths where the
 * right answer is one, and an implementation that strips them too eagerly
 * returns the pattern with the backslash still in it. The two failures look
 * nothing alike, which is what makes the row worth having.
 *
 * NO EXPECTED CONSTANTS ANYWHERE. The Makefile diffs this against gcc on the
 * same box and the same tree, so the assertion is "pxx agrees with glibc",
 * which is the actual claim. Writing the expected paths down here would have
 * meant choosing them, and the value of a `.' or `..' appearing in a result
 * is precisely what nobody would think to write down. */

#define _GNU_SOURCE 1
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <glob.h>

static int errcalls;
static int errseen;

static int counting_errfunc(const char *path, int e)
{
  (void)path;
  errcalls++;
  errseen = e;
  return 0;                 /* "log it and carry on" -- the usual shape */
}

static int stopping_errfunc(const char *path, int e)
{
  (void)path; (void)e;
  errcalls++;
  return 1;                 /* asks glob() to abort even without GLOB_ERR */
}

static void mkf(const char *p)
{
  int fd = creat(p, 0644);
  if (fd < 0) { fprintf(stderr, "creat %s: %s\n", p, strerror(errno)); exit(2); }
  close(fd);
}

static void mkd(const char *p)
{
  if (mkdir(p, 0755) != 0) { fprintf(stderr, "mkdir %s: %s\n", p, strerror(errno)); exit(2); }
}

/* One row: pattern, flags, printed as `flags pattern -> rc : paths'. */
static void row(const char *tag, const char *pat, int flags)
{
  glob_t g;
  int rc;
  size_t i;
  memset(&g, 0, sizeof g);
  rc = glob(pat, flags, NULL, &g);
  printf("%-10s %-12s rc=%d n=%lu :", tag, pat, rc, (unsigned long)g.gl_pathc);
  for (i = 0; i < g.gl_pathc; i++) printf(" %s", g.gl_pathv[i]);
  printf("\n");
  globfree(&g);
}

int main(int argc, char **argv)
{
  if (argc < 2) { fprintf(stderr, "usage: %s <empty-dir>\n", argv[0]); return 2; }
  if (chdir(argv[1]) != 0) { perror("chdir"); return 2; }

  /* The tree. Names chosen so that several rows discriminate: `abc' and
     `axc' differ only where `a?c' looks; `a*b' exists as a literal file so
     the escape rows have something to be right about; `.hidden' and `.x'
     make the leading-dot rule visible in both directions. */
  mkf("abc"); mkf("axc"); mkf("bcd"); mkf("one.c"); mkf("two.c");
  mkf("a*b"); mkf("aQb"); mkf("aRb");
  mkf(".hidden"); mkf(".x");
  mkd("sub"); mkf("sub/one.h"); mkf("sub/two.h"); mkf("sub/nested.c");
  mkd("sub/deep"); mkf("sub/deep/leaf");
  mkd("empty");
  if (symlink("nowhere-at-all", "dangling") != 0) { perror("symlink"); return 2; }

  row("plain",  "*",            0);
  row("plain",  "*.c",          0);
  row("plain",  "a?c",          0);
  row("plain",  "[ab]*",        0);
  row("plain",  "[!a]*",        0);
  row("dot",    ".*",           0);
  row("dot",    "*",            GLOB_PERIOD);
  row("dir",    "sub/*",        0);
  row("dir",    "*/*.h",        0);
  row("dir",    "sub/deep/*",   0);
  row("dir",    "*/",           0);
  row("dir",    "sub/",         0);
  row("dir",    "empty/*",      0);
  row("nomatch","zzz*",         0);
  row("nomatch","zzz*",         GLOB_NOCHECK);
  row("nomatch","zzz",          0);
  row("nomatch","zzz",          GLOB_NOMAGIC);
  row("nomatch","zzz*",         GLOB_NOMAGIC);
  row("lit",    "abc",          0);
  row("lit",    "sub/one.h",    0);
  row("esc",    "a\\*b",        0);
  row("esc",    "a\\*b",        GLOB_NOESCAPE);
  row("esc",    "a*b",          0);
  row("mark",   "*",            GLOB_MARK);
  row("mark",   "sub",          GLOB_MARK);
  row("slash",  "sub//one.h",   0);
  row("slash",  ".//abc",       0);
  row("deep",   "*/*/*",        0);
  row("nodir",  "nodir/*",      0);

  /* GLOB_APPEND accumulates into one glob_t. gl_pathc is the running total
     and the second call's results follow the first's -- the WHOLE vector is
     not re-sorted, which is the part a caller depends on when it globs
     several patterns in a deliberate order. */
  {
    glob_t g;
    int r1, r2;
    size_t i;
    memset(&g, 0, sizeof g);
    r1 = glob("*.h", 0, NULL, &g);            /* no match at top level */
    r2 = glob("*.c", GLOB_APPEND, NULL, &g);
    printf("append     rc=%d,%d n=%lu :", r1, r2, (unsigned long)g.gl_pathc);
    for (i = 0; i < g.gl_pathc; i++) printf(" %s", g.gl_pathv[i]);
    printf("\n");
    globfree(&g);
  }
  {
    glob_t g;
    int r1, r2;
    size_t i;
    memset(&g, 0, sizeof g);
    r1 = glob("sub/*.h", 0, NULL, &g);
    r2 = glob("*.c", GLOB_APPEND, NULL, &g);
    printf("append2    rc=%d,%d n=%lu :", r1, r2, (unsigned long)g.gl_pathc);
    for (i = 0; i < g.gl_pathc; i++) printf(" %s", g.gl_pathv[i]);
    printf("\n");
    globfree(&g);
  }

  /* GLOB_DOOFFS reserves leading NULL slots. The row prints whether they are
     NULL rather than printing them, because a non-NULL slot here is an
     uninitialised pointer the caller would hand to execv(). */
  {
    glob_t g;
    int rc;
    size_t i;
    memset(&g, 0, sizeof g);
    g.gl_offs = 2;
    rc = glob("*.c", GLOB_DOOFFS, NULL, &g);
    printf("dooffs     rc=%d n=%lu offs=%lu slot0=%s slot1=%s :",
           rc, (unsigned long)g.gl_pathc, (unsigned long)g.gl_offs,
           g.gl_pathv[0] ? "SET" : "null", g.gl_pathv[1] ? "SET" : "null");
    for (i = 0; i < g.gl_pathc; i++) printf(" %s", g.gl_pathv[g.gl_offs + i]);
    printf("\n");
    globfree(&g);
  }

  /* GLOB_MAGCHAR is an OUTPUT flag: glob() sets it in gl_flags when the
     pattern had a wildcard. A caller reads it to tell "no match" from "there
     was nothing to expand". */
  {
    glob_t g;
    memset(&g, 0, sizeof g);
    glob("*.c", 0, NULL, &g);
    printf("magchar    star=%d", (g.gl_flags & GLOB_MAGCHAR) ? 1 : 0);
    globfree(&g);
    memset(&g, 0, sizeof g);
    glob("abc", 0, NULL, &g);
    printf(" literal=%d\n", (g.gl_flags & GLOB_MAGCHAR) ? 1 : 0);
    globfree(&g);
  }

  /* THE TWO ERROR DECISIONS ARE SEPARATE and this is the row that says so.
     An errfunc returning 0 must NOT abort the glob; GLOB_ERR must abort it
     with no errfunc at all; an errfunc returning non-zero must abort it even
     though GLOB_ERR is clear. Collapsing any pair of those into one test
     leaves the collapsed implementation passing. */
  {
    glob_t g;
    int rc;
    errcalls = 0; errseen = 0;
    memset(&g, 0, sizeof g);
    rc = glob("nodir/*", 0, counting_errfunc, &g);
    printf("err/carry  rc=%d calls=%d\n", rc, errcalls);
    globfree(&g);

    errcalls = 0;
    memset(&g, 0, sizeof g);
    rc = glob("nodir/*", GLOB_ERR, NULL, &g);
    printf("err/GLOBERR rc=%d\n", rc);
    globfree(&g);

    errcalls = 0;
    memset(&g, 0, sizeof g);
    rc = glob("nodir/*", 0, stopping_errfunc, &g);
    printf("err/stop   rc=%d calls=%d\n", rc, errcalls);
    globfree(&g);
  }

  /* glob_pattern_p: the `quote' argument flips whether a backslash hides a
     wildcard, so the two calls on the same string must disagree. A row where
     they agreed would pass an implementation that ignored the argument. */
  printf("patternp   %d %d %d %d %d %d\n",
         glob_pattern_p("abc", 1), glob_pattern_p("a*c", 1),
         glob_pattern_p("a\\*c", 1), glob_pattern_p("a\\*c", 0),
         glob_pattern_p("a[bc]d", 1), glob_pattern_p("a?d", 1));
  return 0;
}
