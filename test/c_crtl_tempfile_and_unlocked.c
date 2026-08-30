/* crtl's mkstemp/mkdtemp, the stdio _unlocked family, and the fd-relative
   helpers fchdir/ttyname_r — every expected line here was taken from a
   glibc-built binary of this same file, which is why the file compiles clean
   under gcc too (the _unlocked names need _GNU_SOURCE there).

   The _unlocked spellings are ALIASES in crtl, not stubs: a crtl FILE has no
   lock, so skipping it is a no-op and the semantics are the locked ones. That
   is exactly what these rows assert — same answers, same stream state.

   The ENOSYS set (fork/chroot/set*id) is deliberately NOT here: those diverge
   from glibc on purpose, so they belong in an assertion, not in a differential.
   feature-c-corpus-busybox-applet */
#define _GNU_SOURCE 1
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>

int main(void)
{
  /* THE DIRECTORY COMES FROM THE ENVIRONMENT, and the order is not cosmetic.
     These templates are written at RUN TIME by this compiled program, so no
     Makefile sweep reaches them and testmgr's per-run privatisation cannot
     either -- two concurrent runs (a watcher beside a dev session is the normal
     state) would share one file, and what that produces is a WRONG RESULT, not
     a crash. TESTMGR_TMP first because testmgr launches jobs through an
     environment allowlist (PXX_ TESTMGR_ LC_ QEMU_), so $TESTTMP alone does not
     reach the job; TESTTMP second because that is what
     `make test TESTTMP=$(mktemp -d)` exports; /tmp last so a bare run is
     byte-identical. mkstemp's own XXXXXX does NOT solve this -- it randomises
     the leaf, never the directory, and `noXs` has no template at all.
     bug-c-three-hardcoded-tmp-paths-in-the-new-crtl-tempfile-test */
  const char *dir = getenv("TESTMGR_TMP");
  char tmpl[512], tmpl0[512], tmpl2[512], tmpl20[512], bad[512];
  char buf[64];
  int fd, n;

  if (!dir) dir = getenv("TESTTMP");
  if (!dir) dir = "/tmp";
  snprintf(tmpl,  sizeof(tmpl),  "%s/pxxprobeXXXXXX",  dir);
  snprintf(tmpl2, sizeof(tmpl2), "%s/pxxprobedXXXXXX", dir);
  snprintf(bad,   sizeof(bad),   "%s/noXs",            dir);
  strcpy(tmpl0,  tmpl);
  strcpy(tmpl20, tmpl2);

  /* mkstemp: creates, is read/write, and the template was rewritten in place
     to the same LENGTH (the XXXXXX is replaced, never extended or trimmed). */
  fd = mkstemp(tmpl);
  printf("mkstemp fd>=0: %d\n", fd >= 0);
  printf("mkstemp name changed: %d\n", strcmp(tmpl, tmpl0) != 0);
  /* The LENGTH row asserts "unchanged", not a number: the number was 19 only
     because the directory was hardcoded, and the property being tested is that
     mkstemp rewrites the template IN PLACE -- replacing the XXXXXX, never
     extending or trimming it -- which is dir-independent. */
  printf("mkstemp len same: %d\n", (int)strlen(tmpl) == (int)strlen(tmpl0));
  n = (int)write(fd, "hello", 5);
  printf("mkstemp write: %d\n", n);
  lseek(fd, 0, SEEK_SET);
  memset(buf, 0, sizeof(buf));
  n = (int)read(fd, buf, 5);
  printf("mkstemp readback: %d [%s]\n", n, buf);
  close(fd);
  printf("mkstemp unlink: %d\n", unlink(tmpl));

  /* A template without the trailing XXXXXX is EINVAL, not a silent success. */
  { int r = mkstemp(bad);
    printf("mkstemp bad: %d errno=%d\n", r, errno); }

  { char *r = mkdtemp(tmpl2);
    printf("mkdtemp ok: %d changed: %d\n", r != 0,
           strcmp(tmpl2, tmpl20) != 0);
    if (r) rmdir(tmpl2); }

  printf("fileno_unlocked(stdout): %d\n", fileno_unlocked(stdout));
  printf("ferror_unlocked(stdout): %d\n", ferror_unlocked(stdout));
  printf("feof_unlocked(stdout): %d\n", feof_unlocked(stdout));
  fputs_unlocked("fputs_unlocked ok\n", stdout);
  putchar_unlocked('p'); putchar_unlocked('c'); putchar_unlocked('\n');
  fwrite_unlocked("fwrite_unlocked ok\n", 1, 19, stdout);
  flockfile(stdout); funlockfile(stdout);
  printf("ftrylockfile: %d\n", ftrylockfile(stdout));

  /* fchdir has no PAL syscall; it resolves the fd through /proc/self/fd/N and
     chdir()s to what it finds. The row asserts it LANDED, not merely returned.

     NO PATH IS PRINTED, deliberately: testmgr rewrites an absolute /tmp path
     inside an EXPECTED string to the run's scratch directory, but does not
     rewrite the test SOURCE — so a row that printed one compared a rewritten
     expectation against an unrewritten actual and went red on the sweeping
     host while passing locally. Instead both sides come from getcwd(), which
     also makes the comparison immune to /tmp being a symlink. */
  { char cwd0[512], cwd1[512], viaChdir[512];
    int d = open("/tmp", O_RDONLY);
    if (!getcwd(cwd0, sizeof(cwd0))) cwd0[0] = 0;
    if (chdir("/tmp")) viaChdir[0] = 0;
    else if (!getcwd(viaChdir, sizeof(viaChdir))) viaChdir[0] = 0;
    if (chdir(cwd0)) { }
    printf("fchdir: %d\n", fchdir(d));
    if (!getcwd(cwd1, sizeof(cwd1))) cwd1[0] = 0;
    printf("fchdir landed: %d\n",
           viaChdir[0] != 0 && strcmp(cwd1, viaChdir) == 0);
    close(d);
    if (chdir(cwd0)) { }
  }

  /* fd 0 under the harness is a pipe or a file, never a tty, so ttyname_r's
     answer is ENOTTY on both sides. Printed as a CLASS so the row stays stable
     if someone runs it on a terminal by hand. */
  { char t[256]; int r = ttyname_r(0, t, sizeof(t));
    printf("ttyname_r(0) rc class: %d\n", r == 0 ? 0 : (r == ENOTTY ? 1 : 2)); }
  return 0;
}
