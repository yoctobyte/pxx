/* SPDX-License-Identifier: Zlib */
/* xattr and inotify, asserted by EFFECT and diffed against glibc.

   NO EXPECTED VALUES ANYWHERE. The Makefile compiles this with pxx and with
   gcc and diffs the two runs, then compares each cross target against the
   native pxx run. That matters more here than usual: whether `user.*'
   attributes work at all depends on the FILESYSTEM under the working
   directory, so a hardcoded expectation would be right on one box and wrong on
   the next. Diffing makes the row "crtl and glibc agree about this
   filesystem", which is true wherever it runs.

   ROW 3 IS THE ONE THAT SEPARATES THE l VARIANT FROM THE PLAIN ONE, and it is
   the reason all twelve xattr entries exist rather than four. setfattr -h
   means "act on the symlink, not its target". An implementation that aliased
   lsetxattr to setxattr passes every other row in this file and writes the
   attribute onto the wrong object -- a wrong ANSWER with no diagnostic. The
   row sets through the link with lsetxattr and then asks the TARGET whether it
   grew an attribute; the answer must be no.

   ROW 6 IS THE inotify_init CASCADE, AND IT TOOK A FAILED POSITIVE CONTROL TO
   GET IT RIGHT. aarch64 and riscv32 have no SYS_inotify_init at all -- their
   table starts at init1 -- so src/sys/inotify.c synthesises the no-argument
   form. The first draft of this row called inotify_init1(IN_NONBLOCK), which
   exists on every target, so DELETING THE CASCADE CHANGED NOTHING AND THE ROW
   STILL PASSED on aarch64. It now calls inotify_init(), which is also what
   busybox's inotifyd.c:118 calls, and the control fails as it should. A guard
   aimed one function away from the thing it names is not a guard.

   ROW 7 READS A REAL EVENT. It is the only row that proves the watch was
   installed rather than merely accepted: a stub inotify_add_watch returning a
   plausible small integer passes row 6 and fails here. */

#define _GNU_SOURCE 1
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/xattr.h>
#include <sys/inotify.h>

static const char *e(int saved) { return saved == ENOTSUP ? "ENOTSUP" :
                                         saved == EPERM   ? "EPERM"   :
                                         saved == ENODATA ? "ENODATA" :
                                         saved == 0       ? "-"       : "other"; }

int main(void)
{
  char buf[64];
  char evbuf[sizeof(struct inotify_event) + 64];
  struct inotify_event *ie;
  const char *f = "cxi_file", *l = "cxi_link", *d = "cxi_dir";
  int fd, wd, r, n, saved;
  ssize_t g;

  unlink(l); unlink(f); unlink("cxi_dir/made"); rmdir(d);
  fd = open(f, O_WRONLY | O_CREAT | O_TRUNC, 0600);
  if (fd < 0) { printf("setup create failed\n"); return 1; }
  close(fd);
  if (symlink(f, l) != 0) { printf("setup symlink failed\n"); return 1; }
  if (mkdir(d, 0700) != 0) { printf("setup mkdir failed\n"); return 1; }

  /* 1: set an attribute and read it back. */
  errno = 0;
  r = setxattr(f, "user.pxx", "abc", 3, 0);
  saved = errno;
  printf("1 set %d %s\n", r, e(r == 0 ? 0 : saved));

  /* 2: the value comes back byte for byte, and size 0 answers the length. */
  memset(buf, 0, sizeof buf);
  g = getxattr(f, "user.pxx", buf, sizeof buf);
  printf("2 get %zd [%s] sized %zd\n", g, g > 0 ? buf : "",
         getxattr(f, "user.pxx", 0, 0));

  /* 3: lsetxattr acts on the LINK. The target must not gain the attribute.
        This is the row an l-aliased-to-plain implementation fails. */
  errno = 0;
  r = lsetxattr(l, "user.pxxl", "z", 1, 0);
  saved = errno;
  errno = 0;
  g = getxattr(f, "user.pxxl", buf, sizeof buf);
  printf("3 lset %d %s target-has-it %d\n", r, e(r == 0 ? 0 : saved), g >= 0);

  /* 4: listxattr mentions the name we set, if setting worked at all. */
  memset(buf, 0, sizeof buf);
  g = listxattr(f, buf, sizeof buf);
  n = 0;
  if (g > 0) { char *p = buf; while (p < buf + g) { if (!strcmp(p, "user.pxx")) n = 1; p += strlen(p) + 1; } }
  printf("4 list %d\n", g > 0 ? n : (int)g);

  /* 5: remove, then the get must fail with ENODATA rather than succeed. */
  errno = 0;
  r = removexattr(f, "user.pxx");
  saved = errno;
  errno = 0;
  g = getxattr(f, "user.pxx", buf, sizeof buf);
  printf("5 remove %d %s then-get %s\n", r, e(r == 0 ? 0 : saved), e(g < 0 ? errno : 0));

  /* 6: inotify_init() -- the NO-ARGUMENT form, which is the one with no
        syscall behind it on aarch64 and riscv32, and the one busybox calls.
        init1 is checked alongside it because they are different entry points
        and only one of them has the cascade. */
  fd = inotify_init();
  r = inotify_init1(IN_NONBLOCK);
  printf("6 init %d init1 %d\n", fd >= 0, r >= 0);
  if (r >= 0) close(r);
  if (fd < 0) { printf("7 skipped\n8 skipped\n"); return 0; }

  /* 7: a real event. A stub add_watch returning a plausible integer passes
        row 6 and fails here. */
  wd = inotify_add_watch(fd, d, IN_CREATE | IN_DELETE);
  r = open("cxi_dir/made", O_WRONLY | O_CREAT, 0600);
  if (r >= 0) close(r);
  n = (int)read(fd, evbuf, sizeof evbuf);
  ie = (struct inotify_event *)evbuf;
  printf("7 watch %d event %d create %d name %s\n",
         wd >= 0, n > 0, n > 0 && (ie->mask & IN_CREATE) != 0,
         (n > 0 && ie->len) ? ie->name : "-");

  /* 8: removing the watch is accepted, and removing it twice is not. */
  r = inotify_rm_watch(fd, wd);
  n = inotify_rm_watch(fd, wd);
  printf("8 rm %d twice %d\n", r, n);
  close(fd);

  unlink("cxi_dir/made"); rmdir(d); unlink(l); unlink(f);
  return 0;
}
