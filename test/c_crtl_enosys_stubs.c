/* The crtl calls that have NO PAL syscall behind them. Each must fail with
   -1 / ENOSYS — a defined, loud answer a caller can act on — and must never
   report a success it did not perform. That silent-success case is the one
   this file exists to catch: it would make a privilege drop, a chroot or a
   fork look done when nothing happened.

   Not a glibc differential, deliberately: glibc's fork() SUCCEEDS. These rows
   assert our documented divergence, so the oracle is the contract, not a
   binary. Delete a row here the day the PAL grows that syscall and the stub
   becomes a real implementation.

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
  ENOSYS_ROW("fork",    fork());
  ENOSYS_ROW("vfork",   vfork());
  ENOSYS_ROW("chroot",  chroot("/tmp"));
  ENOSYS_ROW("setuid",  setuid(0));
  ENOSYS_ROW("setgid",  setgid(0));
  ENOSYS_ROW("seteuid", seteuid(0));
  ENOSYS_ROW("setegid", setegid(0));
  return 0;
}
