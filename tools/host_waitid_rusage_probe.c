/* HOST CAPABILITY PROBE -- not a test, and deliberately not wired into a tier.
   Run it by hand on a box whose cross-target verdicts you are trying to
   explain:  gcc -O0 -o /tmp/waitid_probe tools/host_waitid_rusage_probe.c

   Does the HOST KERNEL fill waitid's rusage?  No qemu, no pxx, no crtl --
   x86-64 native, glibc, raw syscall.  Build: gcc -O0 -o probe probe.c

   WHY THIS EXISTS.  test-core#src:test/c_crtl_wait.c is red on seven and green
   on plexus on one row: riscv32's `wait4-rusage rusage=UNTOUCHED` against an
   expected `written`.  riscv32 is the one target with no wait4, so pxx's
   PalBackendWait4 reaches it through SYS_waitid with the rusage pointer in
   arg5 -- and BOTH the emulator and the host kernel sit on that path.  seven
   and plexus differ in both (qemu 8.2.2 / kernel 6.8.0-138 vs qemu 10.2.1 /
   kernel 7.0.0-30), so the version delta is consistent with the hypothesis and
   does not discriminate.

   This probe removes qemu from the path entirely and asks the kernel alone.
   Run it on BOTH boxes:

     both print rusage=written  -> both kernels honour waitid's arg5, the
                                   kernel is exonerated, and qemu is the only
                                   remaining variable on the riscv32 path.
     seven prints UNTOUCHED     -> the kernel is the cause and the qemu delta
                                   is a coincidence; the ticket is wrong.

   glibc's waitid() wrapper takes no rusage argument, so the raw syscall is not
   an optimisation here -- it is the only way to ask the question.

   MEASURED 2026-09-04, both boxes, this source:

     plexus (kernel 7.0.0-30-generic):  rusage=written  ru_maxrss=256
     seven  (kernel 6.8.0-138-generic): rusage=written  ru_maxrss=192
     control row on both:               rusage=UNTOUCHED

   Both kernels honour arg5, so the kernel is eliminated and the riscv32
   divergence is the emulator: seven runs qemu-riscv32 8.2.2 where plexus runs
   10.2.1. See bug-t-tstate-fingerprints-the-code-and-the-hardware-but-not-the-
   emulator-toolchain. */
#define _GNU_SOURCE
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>
#include <sys/syscall.h>
#include <sys/resource.h>
#include <sys/wait.h>

int main(void)
{
	siginfo_t si;
	struct rusage ru;
	pid_t p;
	long rc;
	int e, i, untouched = 1;
	const unsigned char *q = (const unsigned char *)&ru;

	memset(&si, 0, sizeof si);
	memset(&ru, 0x5a, sizeof ru);            /* same sentinel as c_crtl_wait.c */

	p = fork();
	if (p == 0) _exit(9);

	errno = 0;
	rc = syscall(SYS_waitid, P_PID, (int)p, &si, WEXITED, &ru);
	e = errno;

	for (i = 0; i < (int)sizeof ru; i++) if (q[i] != 0x5a) { untouched = 0; break; }

	printf("waitid rc=%ld errno=%d si_pid=%d si_code=%d si_status=%d rusage=%s\n",
	       rc, e, (int)si.si_pid, si.si_code, si.si_status,
	       untouched ? "UNTOUCHED" : "written");
	/* utime+stime printed so a reader can see the write was a real one and not
	   one stray byte: a child that _exit(9)s immediately still gets a zeroed
	   rusage written over the sentinel, which is the observable. */
	printf("               ru_maxrss=%ld ru_utime=%ld.%06ld ru_stime=%ld.%06ld\n",
	       ru.ru_maxrss, (long)ru.ru_utime.tv_sec, (long)ru.ru_utime.tv_usec,
	       (long)ru.ru_stime.tv_sec, (long)ru.ru_stime.tv_usec);

	/* POSITIVE CONTROL, and the probe is worthless without it: the sentinel
	   scan must be ABLE to say UNTOUCHED on this box.  Same call, arg5 NULL --
	   nothing may write the buffer, so a run that prints  on both
	   rows is reading something other than the kernel's copy-back and its
	   first row proves nothing. */
	memset(&si, 0, sizeof si);
	memset(&ru, 0x5a, sizeof ru);
	p = fork();
	if (p == 0) _exit(9);
	rc = syscall(SYS_waitid, P_PID, (int)p, &si, WEXITED, (struct rusage *)0);
	untouched = 1;
	for (i = 0; i < (int)sizeof ru; i++) if (q[i] != 0x5a) { untouched = 0; break; }
	printf("control (arg5 NULL) rc=%ld rusage=%s   <- MUST be UNTOUCHED\n",
	       rc, untouched ? "UNTOUCHED" : "written");
	return 0;
}
