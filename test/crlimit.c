/* getrlimit / setrlimit against the gcc oracle.
 *
 * <sys/resource.h> deliberately declared NO functions until now -- the header
 * says so, and says the fix is PAL work (prlimit64), not header work. This is
 * that work. Needed by busybox's `ulimit' (shell/shell_common.c:616), found
 * attempting rung 2.
 *
 * TWO THINGS ARE BEING TESTED AND THEY ARE INDEPENDENT.
 *
 * 1. The WIDTH CONVERSION. prlimit64 reads and writes two __u64; crtl's
 *    struct rlimit is two rlim_t, which is `unsigned long' -- 64 bits on
 *    x86-64/aarch64 and 32 on i386/arm32/riscv32/xtensa. Passing the user's
 *    struct straight to the kernel works perfectly on the targets anyone tests
 *    on and lets the kernel write 16 bytes into an 8-byte object everywhere
 *    else. The round-trip rows below would not catch that on x86-64 -- only
 *    running the 32-bit targets can -- which is exactly why this test is wired
 *    for i386, arm32 and riscv32 as well as native.
 *
 * 2. THE ARM32 SYSCALL NUMBER. Every other prlimit64 number was read off a
 *    header on the build host; arm32's (369) could not be, so it is verified by
 *    RUNNING this under qemu-arm rather than by assertion. A wrong number
 *    answers with an error or with garbage instead of a plausible RLIMIT_NOFILE,
 *    and the rows below fail. That is the same discipline the xtensa numbers in
 *    platform_backend.pas were established with, and it is why xtensa REFUSES
 *    here instead of guessing.
 *
 * Values are the host's, so they are not compared -- only invariants are.
 * A machine with different ulimits must not fail this.
 */
#include <sys/resource.h>
#include <stdio.h>
#include <errno.h>

int main(void) {
  struct rlimit a, b;
  int rc;

  rc = getrlimit(RLIMIT_NOFILE, &a);
  printf("nofile rc=%d\n", rc);
  /* cur <= max is the one relation the kernel guarantees. */
  printf("nofile ordered=%d\n",
         a.rlim_max == RLIM_INFINITY || a.rlim_cur <= a.rlim_max);
  printf("nofile plausible=%d\n", a.rlim_cur >= 16);

  /* STACK is commonly unlimited-ish and is the row where a 64-bit limit meets a
     32-bit rlim_t. Only the invariant is printed, for the same reason. */
  rc = getrlimit(RLIMIT_STACK, &b);
  printf("stack rc=%d\n", rc);
  printf("stack ordered=%d\n",
         b.rlim_max == RLIM_INFINITY || b.rlim_cur <= b.rlim_max);

  /* Lowering the soft limit and putting it back must round-trip EXACTLY.
     This is the row that catches a botched narrow/widen: a value that survives
     one direction and not the other comes back different. */
  {
    struct rlimit lower, back;
    lower.rlim_cur = a.rlim_cur > 64 ? 64 : a.rlim_cur;
    lower.rlim_max = a.rlim_max;
    rc = setrlimit(RLIMIT_NOFILE, &lower);
    printf("set rc=%d\n", rc);
    rc = getrlimit(RLIMIT_NOFILE, &back);
    printf("roundtrip cur=%d max=%d\n",
           back.rlim_cur == lower.rlim_cur, back.rlim_max == lower.rlim_max);
    /* restore */
    setrlimit(RLIMIT_NOFILE, &a);
  }

  /* An invalid resource is EINVAL, not a crash and not a silent zero. */
  errno = 0;
  rc = getrlimit(9999, &a);
  printf("bogus rc=%d einval=%d\n", rc, errno == EINVAL);
  return 42;
}
