/* The crtl calls that have NO PAL syscall behind them. Each must fail with
   -1 / ENOSYS — a defined, loud answer a caller can act on — and must never
   report a success it did not perform. That silent-success case is the one
   this file exists to catch: it would make a privilege drop, a chroot or a
   fork look done when nothing happened.

   Not a glibc differential, deliberately: these rows assert our documented
   divergence, so the oracle is the contract, not a binary. Delete a row here
   the day the PAL grows that syscall and the stub becomes a real
   implementation.

   FORK AND VFORK WERE DELETED ON 2026-09-01, per that instruction. e2ba5a1e1
   found that the PAL had had fork the whole time under the misleading name
   PalVfork, wired crtl's fork() and vfork() to it, and both now succeed. They
   are covered POSITIVELY by test/cfork.c against a gcc oracle, so this is a
   row moving, not coverage being dropped. Leaving them here did not merely go
   red: fork() SUCCEEDING means the CHILD ran the remaining rows too, so the
   output interleaved two processes and no row after it could be read at all.

   errno is read in a statement of its own: argument evaluation order is
   unspecified, so `printf("%d %d", fork(), errno == ENOSYS)` may read errno
   BEFORE the call that sets it — which is how an earlier draft of this file
   printed a passing 0. feature-c-corpus-busybox-applet */
#include <stdio.h>
#include <unistd.h>
#include <errno.h>

#define ENOSYS_ROW(name, call) \
  do { int r; errno = 0; r = (call); \
       printf("%s: %d %d\n", name, r, errno == ENOSYS); } while (0)

int main(void)
{
  ENOSYS_ROW("chroot",  chroot("/tmp"));
  ENOSYS_ROW("setuid",  setuid(0));
  ENOSYS_ROW("setgid",  setgid(0));
  ENOSYS_ROW("seteuid", seteuid(0));
  ENOSYS_ROW("setegid", setegid(0));
  return 0;
}
