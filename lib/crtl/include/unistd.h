/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_UNISTD_H
#define PXX_CRTL_UNISTD_H 1

#include <stddef.h>
#include <sys/types.h>

#define STDIN_FILENO 0
#define STDOUT_FILENO 1
#define STDERR_FILENO 2
#define _SC_PAGESIZE 30
#define _SC_PAGE_SIZE _SC_PAGESIZE

/* access(2) mode bits (POSIX <unistd.h>). Match the Linux kernel values so a
   real access() syscall interprets them; without these sqlite's access(path,
   F_OK) silently passed mode 0 (== F_OK, so it happened to work). */
#define F_OK 0
#define X_OK 1
#define W_OK 2
#define R_OK 4

/* POSIX declares the environment here. It is defined in unistd.c and filled
   before main by __pxx_run_initializers, which the C entry stub calls with the
   initial stack pointer (feature-c-entry-stub-must-run-initializers-for-environ). */
extern char **environ;

int close(int fd);
ssize_t read(int fd, void *buf, size_t count);
ssize_t write(int fd, const void *buf, size_t count);
off_t lseek(int fd, off_t offset, int whence);
ssize_t pread(int fd, void *buf, size_t count, off_t offset);
ssize_t pwrite(int fd, const void *buf, size_t count, off_t offset);
int fsync(int fd);

/* Descriptor duplication. dup picks the lowest free fd; dup2 forces newfd,
   closing it first if it was open. */
int dup(int oldfd);

/* Working directory and links. chdir is process-global. */
int chdir(const char *path);

/* Process and user ids. geteuid was already present; these are its siblings. */
int getuid(void);
int getgid(void);
int getegid(void);
int getppid(void);

int pipe(int fds[2]);
unsigned int sleep(unsigned int seconds);
int usleep(unsigned int usec);
int getpagesize(void);

/* 1 when fd refers to a terminal (the TCGETS ioctl), 0 otherwise. */
int isatty(int fd);
int symlink(const char *target, const char *linkpath);
int link(const char *oldpath, const char *newpath);
int dup2(int oldfd, int newfd);
int getpid(void);
char *getcwd(char *buf, size_t size);
int unlink(const char *path);
int rmdir(const char *path);
int ftruncate(int fd, off_t length);
int access(const char *path, int mode);
int fchown(int fd, uid_t owner, gid_t group);
uid_t geteuid(void);
ssize_t readlink(const char *path, char *buf, size_t bufsz);
int execvp(const char *file, char *const argv[]);
long sysconf(int name);

/* _exit(2) — _Exit's POSIX spelling: terminate without running atexit handlers
   or flushing streams. Deliberately NOT an alias of exit(). */
void _exit(int status);

/* fchdir/ttyname go through /proc/self/fd/N (no PAL syscall exists for either),
   so they are LINUX-ONLY and need /proc mounted; without it they fail cleanly
   rather than guessing. ttyname returns a pointer into a static buffer. */
int fchdir(int fd);
int ttyname_r(int fd, char *buf, size_t buflen);
char *ttyname(int fd);

/* Declared and defined, but every one of them FAILS with ENOSYS: the PAL
   exposes no syscall for them yet. They exist so that a program carrying a code
   path it never takes can still LINK — see the note in the sibling unistd.c.
   A caller that does take the path gets -1/ENOSYS, never a silent no-op. */
int chroot(const char *path);
int fork(void);
int vfork(void);
int setuid(uid_t uid);
int setgid(gid_t gid);
int seteuid(uid_t uid);
int setegid(gid_t gid);
int setgroups(size_t n, const gid_t *list);

/* getopt — POSIX 2018 declares it here, and that is where every program that
   uses it without <getopt.h> expects to find it (busybox's getopt32 among
   them). The impl is in the sibling unistd.c, so it arrives with this header
   through the ordinary crtl auto-pull.

   `optreset` is BSD's; glibc has no such variable and resets on optind == 0
   instead. Both spellings are supported, because busybox picks between them at
   compile time on __GLIBC__ and real code in the wild does the same.

   GNU argument PERMUTATION IS implemented (`cat file -n` finds the `-n`),
   using glibc's own deferred-exchange structure, so an option's separate
   argument is consumed from its ORIGINAL position rather than the permuted
   one. A leading ':' for silent missing-argument reporting is supported too.

   NOT implemented: the leading `+` / `-` optstring modes, and getopt_long. */
extern char *optarg;
extern int optind, opterr, optopt, optreset;
int getopt(int argc, char *const argv[], const char *optstring);

#endif
