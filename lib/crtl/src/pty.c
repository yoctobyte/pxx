/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: openpty / forkpty / login_tty.
 *
 * openpty's NAME BUFFER HAS NO SIZE. glibc and the BSDs both just strcpy the
 * slave's path into it, and callers size it themselves (dropbear passes NULL
 * and calls ttyname() afterwards). 64 bytes covers "/dev/pts/" plus any
 * number the kernel can hand out. Nobody passes a smaller buffer, and we
 * cannot check one we cannot see.
 */
#include <pty.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <termios.h>
#include <sys/ioctl.h>

int openpty(int *amaster, int *aslave, char *name,
            const struct termios *termp, const struct winsize *winp)
{
	char path[64];
	int m, s, e;

	m = posix_openpt(O_RDWR | O_NOCTTY);
	if (m < 0)
		return -1;
	if (grantpt(m) != 0 || unlockpt(m) != 0)
		goto fail;
	e = ptsname_r(m, path, sizeof path);
	if (e != 0) {
		errno = e;
		goto fail;
	}
	s = open(path, O_RDWR | O_NOCTTY);
	if (s < 0)
		goto fail;
	if (termp)
		tcsetattr(s, TCSAFLUSH, termp);
	if (winp)
		ioctl(s, TIOCSWINSZ, winp);
	if (name)
		strcpy(name, path);
	*amaster = m;
	*aslave = s;
	return 0;
fail:
	e = errno;
	close(m);
	errno = e;
	return -1;
}

/* Make fd the controlling terminal and stdin/stdout/stderr of a new session.
   The setsid comes first: TIOCSCTTY only works for a session leader that has
   no controlling terminal yet. */
int login_tty(int fd)
{
	setsid();
	if (ioctl(fd, TIOCSCTTY, 0) != 0)
		return -1;
	dup2(fd, 0);
	dup2(fd, 1);
	dup2(fd, 2);
	if (fd > 2)
		close(fd);
	return 0;
}

pid_t forkpty(int *amaster, char *name,
              const struct termios *termp, const struct winsize *winp)
{
	int m, s;
	pid_t pid;

	if (openpty(&m, &s, name, termp, winp) != 0)
		return -1;
	pid = fork();
	if (pid < 0) {
		close(m);
		close(s);
		return -1;
	}
	if (pid == 0) {
		close(m);
		if (login_tty(s) != 0)
			_exit(1);
		return 0;
	}
	close(s);
	*amaster = m;
	return pid;
}
