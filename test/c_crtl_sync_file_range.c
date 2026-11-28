/* sync_file_range(2) and its flags, against glibc (both widths): git's
   wrapper.c calls it under HAVE_SYNC_FILE_RANGE, which git's build turns on
   for Linux, and crtl had neither the function nor the flags. On i386 each
   64-bit value goes in two registers, so an offset above 4 GiB and a
   negative one check that the high word is passed.
   feature-crtl-sync-file-range */
#define _GNU_SOURCE
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#include <unistd.h>

static void row(const char *what, int rc)
{
	printf("%-28s rc=%d errno=%s\n", what, rc, rc < 0 ? strerror(errno) : "-");
}

int main(void)
{
	char path[] = "/tmp/pxx-sfr-XXXXXX";
	char buf[8192];
	int fd = mkstemp(path), bad;

	if (fd < 0) { perror("mkstemp"); return 1; }
	memset(buf, 'g', sizeof buf);
	if (write(fd, buf, sizeof buf) != (ssize_t)sizeof buf) { perror("write"); return 1; }
	printf("flags %d %d %d %d\n", SYNC_FILE_RANGE_WAIT_BEFORE, SYNC_FILE_RANGE_WRITE,
	       SYNC_FILE_RANGE_WAIT_AFTER, SYNC_FILE_RANGE_WRITE_AND_WAIT);
	errno = 0;
	row("write, whole file", sync_file_range(fd, 0, 0, SYNC_FILE_RANGE_WRITE));
	row("write and wait, a range", sync_file_range(fd, 4096, 4096, SYNC_FILE_RANGE_WRITE_AND_WAIT));
	row("wait only", sync_file_range(fd, 0, 8192, SYNC_FILE_RANGE_WAIT_AFTER));
	row("past 4 GiB", sync_file_range(fd, 5LL << 30, 4096, SYNC_FILE_RANGE_WRITE));
	row("no flags", sync_file_range(fd, 0, 0, 0));
	row("bad flags", sync_file_range(fd, 0, 0, 0x80));
	row("negative offset", sync_file_range(fd, -4096, 4096, SYNC_FILE_RANGE_WRITE));
	bad = fd + 100;
	row("bad fd", sync_file_range(bad, 0, 0, SYNC_FILE_RANGE_WRITE));
	close(fd);
	unlink(path);
	return 0;
}
