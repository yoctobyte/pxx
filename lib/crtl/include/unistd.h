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
#define _SC_CLK_TCK 2
#define _SC_OPEN_MAX 4

/* access(2) mode bits (POSIX <unistd.h>). Match the Linux kernel values so a
   real access() syscall interprets them; without these sqlite's access(path,
   F_OK) silently passed mode 0 (== F_OK, so it happened to work). */
#define F_OK 0
#define X_OK 1
#define W_OK 2
#define R_OK 4

/* POSIX declares the environment here. It is defined in unistd.c and filled
   before main by __pxx_run_initializers, which the C entry stub calls with the
   initial stack pointer (feature-c-entry-stub-must-run-initializers-for-environ).

   A SHARED LIBRARY has no initial stack to read -- at DT_INIT time the stack
   pointer is inside ld.so -- so the .so init thunk calls __pxx_set_environ with
   the envp the loader passes it instead. Declared here because the compiler
   emits the call and must find the row.
   bug-a-c-a-shared-library-never-runs-its-initialisation */
extern char **environ;
void __pxx_set_environ(char **envp);

int close(int fd);
ssize_t read(int fd, void *buf, size_t count);
ssize_t write(int fd, const void *buf, size_t count);
off_t lseek(int fd, off_t offset, int whence);
ssize_t pread(int fd, void *buf, size_t count, off_t offset);
ssize_t pwrite(int fd, const void *buf, size_t count, off_t offset);
int fsync(int fd);
/* fdatasync: the data only. NOT an alias for fsync -- see src/unistd.c. It is
   PAL_ERR_UNSUPPORTED on esp and wasi (no data-only primitive there) and on
   xtensa-linux (its syscall number was never measured, and a guessed one is
   worse than a refusal). */
int fdatasync(int fd);
void sync(void);

/* setsid(2) returns the new session id; getgroups(2) with size 0 returns the
   count without touching the list. */
int setsid(void);
int getgroups(int size, gid_t list[]);
/* getsid(2): pid 0 means the caller. */
pid_t getsid(pid_t pid);

/* setpgid/getpgid: pid 0 means the caller, and for setpgid a pgid of 0 means
   "the pid's own value", so setpgid(0, 0) makes the caller a group leader.
   setpgrp() is the BSD spelling of exactly that call and is not a second
   mechanism -- POSIX's setpgrp() takes no arguments and returns 0/-1, which is
   the form busybox's crond uses. */
int setpgid(pid_t pid, pid_t pgid);
pid_t getpgid(pid_t pid);
int setpgrp(void);

/* alarm(2): schedule SIGALRM in `seconds', and return the seconds REMAINING on
   any alarm it replaced -- 0 when none was pending. A part-second left rounds
   UP to 1, because 0 is already spoken for. alarm(0) cancels. */
unsigned int alarm(unsigned int seconds);
/* gethostname/sethostname. gethostname READS uname(2)'s nodename rather than
   issuing its own syscall -- they are the same string, and Linux's gethostname
   is a libc function over uname on every architecture that dropped the legacy
   call. TRUNCATION IS AN ERROR (ENAMETOOLONG), not a short answer: a truncated
   hostname is a plausible different host. */
int gethostname(char *name, size_t len);
/* sethostname(2): root only; EPERM otherwise. */
int sethostname(const char *name, size_t len);
/* initgroups(3) is setgroups() over the groups `user' belongs to, plus `group'
   itself. It reads /etc/group, so the note on <grp.h> about NSS applies. */
int initgroups(const char *user, gid_t group);

/* syscall(2): the raw kernel interface, for calls the PAL has no entry for.
   The numbers live in <sys/syscall.h>, and they are per-target -- arm32 and
   xtensa have none, so naming one there is a compile error rather than a call
   to whatever that number means on the wrong architecture.

   ALWAYS FETCHES SIX ARGUMENTS, whatever was passed: the number decides how
   many the kernel reads, and a variadic wrapper cannot know it. That is what
   every libc does; the kernel never looks at the extra words. */
long syscall(long number, ...);

/* getlogin_r/getlogin answer from LOGNAME, then USER, then the passwd entry
   for the real uid -- NOT from utmp and the controlling terminal, which is
   what glibc does and which pxx's targets have no way to provide. See
   src/unistd.c. getlogin_r returns 0 or an errno value, never -1. */
int getlogin_r(char *buf, size_t bufsize);
char *getlogin(void);

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
int truncate(const char *path, off_t length);
int access(const char *path, int mode);
int fchown(int fd, uid_t owner, gid_t group);
int chown(const char *path, uid_t owner, gid_t group);
int lchown(const char *path, uid_t owner, gid_t group);
uid_t geteuid(void);
ssize_t readlink(const char *path, char *buf, size_t bufsz);
int execve(const char *path, char *const argv[], char *const envp[]);
int execvp(const char *file, char *const argv[]);

/* THE LIST FORMS. Each takes the arguments as a NULL-terminated variadic list
   rather than an array, and the NULL is load-bearing: without it the wrapper
   keeps fetching arguments past the end and hands the kernel whatever the
   stack held. Every one of these is a thin wrapper over execv/execve/execvp
   -- there is no separate syscall.

   execle's envp comes AFTER the terminating NULL, which is the one genuinely
   surprising part of the family's shape and the reason it is spelled out here.

   The `l' forms cap the argument list at 63 plus the terminator; a longer one
   fails with E2BIG rather than truncating, since a truncated argv runs the
   program with fewer arguments than the caller wrote and nothing says so. */
int execl(const char *path, const char *arg, ...);
int execlp(const char *file, const char *arg, ...);
int execle(const char *path, const char *arg, ...);
int execv(const char *path, char *const argv[]);
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

/* Declared and defined, but every one of them FAILS with ENOSYS. They exist so
   that a program carrying a code path it never takes can still LINK — see the
   note in the sibling unistd.c. A caller that does take the path gets
   -1/ENOSYS, never a silent no-op.

   chroot and the set*id family have no PAL entry at all. fork/vfork ARE real
   now: the entry they needed existed the whole time under the name PalVfork
   while its body issued SYS_fork. So is setgroups, which PalSetGroups serves.
   See lib/crtl/src/unistd.c. */
int chroot(const char *path);
pid_t fork(void);
pid_t vfork(void);
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
