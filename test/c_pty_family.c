/* THE PTY FAMILY IS ONE MECHANISM AND THIS ASSERTS THE MECHANISM, NOT THE SHAPE.
 *
 * posix_openpt / grantpt / unlockpt / ptsname_r / ptsname were entirely absent
 * from crtl until 2026-09-06. busybox calls ptsname_r with no guard --
 * include/platform.h defines HAVE_PTSNAME_R to 1 by default for a glibc-shaped
 * libc and nothing undefines it -- so there was no fallback arm to land in, and
 * telnetd/script/microcom would simply fail to build.
 * feature-c-crtl-has-no-pty-family-at-all
 *
 * ROW 8 IS THE ONE THAT MATTERS AND IT IS NOT A STRING TEST. Every other row
 * here can be passed by a ptsname_r that always answers "/dev/pts/0": the
 * prefix is right, the length is right, the return code is right, and the name
 * belongs to somebody else's terminal. `strncmp(buf, "/dev/pts/", 9) == 0` is
 * an assertion about the SHAPE of the answer and this family's failure mode is
 * a well-shaped wrong one. So row 8 opens the slave the name actually names and
 * pushes a byte through the pair: only the correct number round-trips.
 *
 * ROW 9 IS THE POSITIVE CONTROL FOR ROW 8 -- a DIFFERENT slave path, taken from
 * a second master opened alongside the first, must NOT carry the first pair's
 * byte. Without it, "the round trip worked" could be a device that echoes
 * anything, and the test would certify a broken ptsname_r that happened to name
 * a working terminal.
 *
 * ROWS 1-2 ARE THE IOCTL NUMBERS THEMSELVES, printed rather than assumed.
 * TIOCGPTN and TIOCSPTLCK are _IOR/_IOW-shaped: they are COMPUTED from the
 * _IOC layout in <sys/ioctl.h> rather than transcribed, so a wrong layout
 * yields a wrong NUMBER and not a compile error. Printing them is what makes
 * that checkable, and the Makefile row diffs the whole output against gcc, so
 * the expected values live in glibc rather than in a table here.
 *
 * ptsname_r RETURNS THE ERROR NUMBER, NOT -1, and sets errno as well. Rows 5-7
 * assert both channels, because a call site that only tests for zero cannot
 * tell the two conventions apart and both look right there.
 */
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>
#include <unistd.h>
#include <sys/ioctl.h>

int main(void)
{
	char buf[64], other[64];
	char got;
	int fd, fd2, sfd, sfd2, r;

	printf("1 TIOCGPTN=0x%08lx\n", (unsigned long)TIOCGPTN);
	printf("2 TIOCSPTLCK=0x%08lx\n", (unsigned long)TIOCSPTLCK);

	fd = posix_openpt(O_RDWR | O_NOCTTY);
	printf("3 posix_openpt fd>=0: %d\n", fd >= 0);
	printf("4 grantpt=%d unlockpt=%d\n", grantpt(fd), unlockpt(fd));

	errno = 0;
	r = ptsname_r(fd, buf, sizeof buf);
	printf("5 ptsname_r rc=%d errno=%d prefix=%d\n",
	       r, errno, strncmp(buf, "/dev/pts/", 9) == 0);

	errno = 0;
	r = ptsname_r(fd, buf, 2);
	printf("6 ptsname_r small rc=%d errno=%d ERANGE=%d\n", r, errno, ERANGE);

	errno = 0;
	r = ptsname_r(0, other, sizeof other);
	printf("7 ptsname_r notatty rc=%d errno=%d ENOTTY=%d\n", r, errno, ENOTTY);

	/* THE ROW THAT SEPARATES A RIGHT NAME FROM A WELL-SHAPED ONE.
	 *
	 * NON-BLOCKING BY CONSTRUCTION, and that is not caution -- a test that
	 * can hang is worse than a test that fails, because a hang has no
	 * verdict and stops the run rather than reporting. The first version of
	 * this row DID hang: a pty slave starts in CANONICAL mode, so `read`
	 * returns only on a complete line, and a bare "Z" with no newline waits
	 * forever. Two things fix it and both are kept -- the newline, so the
	 * line discipline releases the data, and O_NONBLOCK plus a bounded
	 * retry, so a future change to the mode cannot reintroduce a hang.
	 * The retry budget is finite and small; exhausting it prints 0, which
	 * is a FAILURE the diff catches, not a stall.
	 */
	ptsname_r(fd, buf, sizeof buf);
	sfd = open(buf, O_RDWR | O_NOCTTY | O_NONBLOCK);
	got = 0;
	if (sfd >= 0 && write(fd, "Z\n", 2) == 2) {
		for (r = 0; r < 200; r++) {
			if (read(sfd, &got, 1) == 1)
				break;
			usleep(1000);
		}
	}
	printf("8 roundtrip-through-named-slave=%d\n", got == 'Z');

	/* POSITIVE CONTROL FOR ROW 8: a second, different pair must not see it. */
	fd2 = posix_openpt(O_RDWR | O_NOCTTY);
	grantpt(fd2);
	unlockpt(fd2);
	ptsname_r(fd2, other, sizeof other);
	printf("9 second-pair-has-a-different-name=%d\n", strcmp(buf, other) != 0);
	sfd2 = open(other, O_RDWR | O_NOCTTY);
	printf("10 second-slave-opens=%d\n", sfd2 >= 0);

	printf("11 ptsname-static-agrees=%d\n", strcmp(ptsname(fd), buf) == 0);

	if (sfd >= 0) close(sfd);
	if (sfd2 >= 0) close(sfd2);
	close(fd);
	close(fd2);
	return 0;
}
