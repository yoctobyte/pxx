/* realpath(): `.`/`..` folding, symlinks (relative, absolute, to a directory
   followed by `..`), and the error paths, each with glibc's errno. Run in a
   fresh directory; results are printed relative to it so the output is the
   same wherever it runs. The .expected is glibc's output.
   crtl's realpath used to be an identity copy: every row below printed its
   own input, and no error path existed (tcc's tests2/18, #pragma once). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <limits.h>
#include <unistd.h>
#include <sys/stat.h>
#include <fcntl.h>

static char base[PATH_MAX];
static size_t baselen;

static const char *ename(int e) {
  switch (e) {
    case ENOENT: return "ENOENT";
    case ENOTDIR: return "ENOTDIR";
    case ELOOP: return "ELOOP";
    case EINVAL: return "EINVAL";
    case ENAMETOOLONG: return "ENAMETOOLONG";
    default: return "other";
  }
}

static void show_as(const char *label, const char *p);
static void show(const char *p) { show_as(p, p); }

static void show_as(const char *label, const char *p) {
  char buf[PATH_MAX];
  char *a, *b;
  errno = 0;
  a = realpath(p, NULL);
  int ea = errno;
  errno = 0;
  b = realpath(p, buf);
  int eb = errno;
  if (!a) {
    printf("%-16s -> NULL %s%s\n", label, ename(ea), (!b && ea == eb) ? "" : " (buffer form differs)");
    return;
  }
  if (!b || strcmp(a, b) != 0) printf("%-16s -> buffer form differs\n", label);
  if (strncmp(a, base, baselen) == 0) printf("%-16s -> BASE%s\n", label, a + baselen);
  else printf("%-16s -> %s\n", label, a);
  free(a);
}

int main(void) {
  /* The scratch root in the order tools/testmgr_hardcoded_tmp_devtest.py
     asks for: testmgr's per-run dir, then make's, then the default. The
     output prints paths relative to the resolved base, so it is the same
     whichever root is used. */
  const char *root = getenv("TESTMGR_TMP");
  if (!root) root = getenv("TESTTMP");
  if (!root) root = "/tmp";
  char tmpl[PATH_MAX];
  snprintf(tmpl, sizeof tmpl, "%s/pxxrpXXXXXX", root);
  char abs_target[PATH_MAX + 8];
  char *dir = mkdtemp(tmpl);
  if (!dir || chdir(dir) != 0) { printf("setup failed\n"); return 1; }
  /* base is the physical path of the directory (a /tmp symlink resolves) */
  if (!getcwd(base, sizeof base)) { printf("getcwd failed\n"); return 1; }
  baselen = strlen(base);
  mkdir("d", 0755);
  mkdir("d/sub", 0755);
  close(open("d/f", O_CREAT | O_WRONLY, 0644));
  symlink("d", "lnk");
  symlink("d/sub", "lsub");
  snprintf(abs_target, sizeof abs_target, "%s/d/f", base);
  symlink(abs_target, "labs");
  symlink("loop2", "loop1");
  symlink("loop1", "loop2");
  symlink("nope", "dangling");
  symlink("../f", "d/sub/up");

  show(".");
  show("d");
  show("./d/./sub/../f");
  show("d//sub///");
  /* `..` past the root stays at the root. The scratch dir's depth depends on
     TESTMGR_TMP/TESTTMP, so climb far more levels than any of them has. */
  char up[40 * 3 + 3] = "";
  for (int k = 0; k < 40; k++) strcat(up, "../");
  strcat(up, "..");
  show_as("../ x40 ..", up);
  show("lnk");
  show("lnk/sub");
  show("lsub/..");
  show("labs");
  show("d/sub/up");
  show("nope");
  show("d/nope/x");
  show("dangling");
  show("loop1");
  show("d/f/");
  show("d/f/..");
  show("d/f/x");
  show("");
  {
    char *r;
    int e;
    errno = 0;
    r = realpath(NULL, NULL);
    e = errno;
    printf("%-16s -> %s %s\n", "(null)", r ? "non-NULL" : "NULL", ename(e));
  }
  unlink("d/sub/up"); unlink("dangling"); unlink("loop2"); unlink("loop1");
  unlink("labs"); unlink("lsub"); unlink("lnk"); unlink("d/f");
  rmdir("d/sub"); rmdir("d");
  if (chdir("/") == 0) rmdir(base);
  return 0;
}
