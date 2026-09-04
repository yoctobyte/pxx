/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: getrandom(2).
 *
 * OVER THE RAW SYSCALL BRIDGE and not over a PAL entry, for the reason
 * <sys/random.h> states: the flags are the point. GRND_NONBLOCK and
 * GRND_INSECURE select between "fail rather than wait for entropy" and "give
 * me bytes now, seeded or not", and a PAL entry that returned random bytes
 * without them would answer a different question while looking correct.
 *
 * ERRNO CONVENTION, and the two in this runtime look identical at the call
 * site. syscall() in src/unistd.c has ALREADY turned the kernel's -errno into
 * -1 plus errno; the PAL entries hand back -errno for the caller to translate.
 * Applying the PAL idiom here would overwrite the real errno with 1 (EPERM)
 * and report "operation not permitted" for every failure -- measured in
 * src/sys/statfs.c on 2026-09-02, where only the error ROW of the test showed
 * it. So this returns what syscall() returned, untouched.
 *
 * THE RETURN VALUE IS A LENGTH. Kernels before 5.18 could return a short count
 * for a request over 256 bytes, so a caller must loop; busybox's seedrng does.
 * Not looping here is the contract, not an omission.
 */
#include <sys/random.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <errno.h>

ssize_t getrandom(void *buf, size_t buflen, unsigned int flags)
{
#ifdef SYS_getrandom
  return (ssize_t)syscall(SYS_getrandom, buf, (long)buflen, (long)flags);
#else
  /* No number for this target. ENOSYS is what the kernel itself answers for an
     unimplemented call, so a caller's existing fallback path takes over
     unchanged -- which is exactly what seedrng has. */
  (void)buf; (void)buflen; (void)flags;
  errno = ENOSYS;
  return -1;
#endif
}
