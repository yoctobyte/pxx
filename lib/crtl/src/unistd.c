/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: unistd — libc-free fsync/getpid/sysconf for sqlite's unix VFS.
 * fsync/getpid forward to the Pascal PAL syscalls; sysconf answers the one
 * query sqlite makes (_SC_PAGESIZE) from a constant, no syscall.
 */

#include <unistd.h>
#include <errno.h>

extern long long __pxx_read(int fd, void *buf, long long n);
extern long long __pxx_write(int fd, void *buf, long long n);
extern int __pxx_close(int fd);
extern long long __pxx_seek(int fd, long long offset, int whence);
extern int __pxx_fsync(int fd);
extern int __pxx_dup(int oldFd);
extern int __pxx_chdir(const char *path);
extern int __pxx_getuid(void);
extern int __pxx_isatty(int fd);
extern int __pxx_getgid(void);
extern int __pxx_getegid(void);
extern int __pxx_getppid(void);
extern int __pxx_pipe2(int *fds, int flags);
extern int __pxx_nanosleep(long long sec, long long nsec);
extern int __pxx_symlink(const char *target, const char *linkpath);
extern int __pxx_link(const char *oldpath, const char *newpath);
extern int __pxx_dup2(int oldFd, int newFd);
extern int __pxx_getpid(void);
extern int __pxx_getcwd(char *buf, unsigned long size);
extern int __pxx_remove(const char *path);
extern int __pxx_ftruncate(int fd, long length);
extern int __pxx_access(const char *path, int mode);
extern int __pxx_fchown(int fd, int owner, int group);
extern int __pxx_geteuid(void);
extern int __pxx_readlink(const char *path, void *buf, int bufsz);
extern int __pxx_rmdir(const char *path);

/* The four most basic POSIX calls, and they were DECLARED here and implemented
   nowhere — so every C program doing raw I/O silently imported them from glibc
   and stopped being statically linked. Same shape as the socket veneer
   (bug-cfront-spurious-dt-needed-libc-with-no-imports); found by probing every
   crtl declaration for an implementation rather than by reading the headers.

   The PAL returns the byte count / 0 on success or -errno; C wants -1 with
   errno set, which is the translation every function in this file does. */
ssize_t read(int fd, void *buf, size_t count) {
  long long rc = __pxx_read(fd, buf, (long long)count);
  if (rc < 0) { errno = (int)-rc; return -1; }
  return (ssize_t)rc;
}

ssize_t write(int fd, const void *buf, size_t count) {
  long long rc = __pxx_write(fd, (void *)buf, (long long)count);
  if (rc < 0) { errno = (int)-rc; return -1; }
  return (ssize_t)rc;
}

int close(int fd) {
  int rc = __pxx_close(fd);
  if (rc < 0) { errno = -rc; return -1; }
  return 0;
}

off_t lseek(int fd, off_t offset, int whence) {
  long long rc = __pxx_seek(fd, (long long)offset, whence);
  if (rc < 0) { errno = (int)-rc; return (off_t)-1; }
  return (off_t)rc;
}

/* Positioned I/O. There is no PAL pread/pwrite syscall, so this preserves the
   file offset by hand: save it, seek, transfer, restore. POSIX requires exactly
   that observable behaviour, and sqlite's USE_PREAD path (os_unix
   seekAndRead/seekAndWrite) depends on it.

   NOT atomic with respect to a concurrent reader on the same fd — a real
   pread() is. crtl's sqlite runs SQLITE_THREADSAFE=0 on a single fd, so the
   difference is unobservable there; anything relying on the atomicity wants a
   real syscall, which is noted on feature-crtl-implement-libc-assumptions. */
ssize_t pread(int fd, void *buf, size_t count, off_t off) {
  long long cur = __pxx_seek(fd, 0, 1 /* SEEK_CUR */);
  long long s, r;
  if (cur < 0) { errno = (int)-cur; return -1; }
  s = __pxx_seek(fd, (long long)off, 0 /* SEEK_SET */);
  if (s < 0) { errno = (int)-s; return -1; }
  r = __pxx_read(fd, buf, (long long)count);
  __pxx_seek(fd, cur, 0);
  if (r < 0) { errno = (int)-r; return -1; }
  return (ssize_t)r;
}

ssize_t pwrite(int fd, const void *buf, size_t count, off_t off) {
  long long cur = __pxx_seek(fd, 0, 1 /* SEEK_CUR */);
  long long s, r;
  if (cur < 0) { errno = (int)-cur; return -1; }
  s = __pxx_seek(fd, (long long)off, 0 /* SEEK_SET */);
  if (s < 0) { errno = (int)-s; return -1; }
  r = __pxx_write(fd, (void *)buf, (long long)count);
  __pxx_seek(fd, cur, 0);
  if (r < 0) { errno = (int)-r; return -1; }
  return (ssize_t)r;
}

/* The PAL returns the raw kernel convention (0/positive, or a NEGATIVE errno).
   Most of this file already translates that to C's -1 + errno inline; the
   one-line forwards below did not, so fsync/dup/dup2/chdir/symlink/link/pipe
   handed the caller -9 or -2 with errno untouched. `if (rc < 0)` still caught
   it, but `if (rc == -1)` did not, and perror() printed "Success".
   Found by tools/gcc_diff_probe.sh. */
static int sysret(int rc) {
  if (rc < 0) { errno = -rc; return -1; }
  return rc;
}

int fsync(int fd) { return sysret(__pxx_fsync(fd)); }

int getpid(void) { return __pxx_getpid(); }

/* sqlite's unix VFS needs these; all forward to a PAL syscall (LP64/ILP32 safe).
   Kernel returns 0/positive on success or -errno; translate to the C -1+errno. */
int ftruncate(int fd, off_t length) {
  int rc = __pxx_ftruncate(fd, (long)length);
  if (rc < 0) { errno = -rc; return -1; }
  return 0;
}

int access(const char *path, int mode) {
  int rc = __pxx_access(path, mode);
  if (rc < 0) { errno = -rc; return -1; }
  return 0;
}

int fchown(int fd, uid_t owner, gid_t group) {
  int rc = __pxx_fchown(fd, (int)owner, (int)group);
  if (rc < 0) { errno = -rc; return -1; }
  return 0;
}

uid_t geteuid(void) { return (uid_t)__pxx_geteuid(); }

ssize_t readlink(const char *path, char *buf, size_t bufsz) {
  int rc = __pxx_readlink(path, buf, (int)bufsz);
  if (rc < 0) { errno = -rc; return -1; }
  return rc;
}

/* Kernel getcwd returns the path length incl. NUL, or -errno. */
char *getcwd(char *buf, size_t size) {
  int r = __pxx_getcwd(buf, (unsigned long)size);
  if (r < 0) { errno = -r; return 0; }
  return buf;
}

/* Link-only stub: no PATH walk / PalExecve bridge yet. Callers see a failed
   exec (tcc's -run re-exec corner) and carry on. */
int execvp(const char *file, char *const argv[]) {
  (void)file; (void)argv;
  errno = 2; /* ENOENT */
  return -1;
}

/* unlink(2) on a file == the PAL's remove (unlinkat, no REMOVEDIR). */
int unlink(const char *path) {
  int rc = __pxx_remove(path);
  if (rc < 0) { errno = -rc; return -1; }
  return 0;
}

/* rmdir(2) == the PAL's rmdir (unlinkat + AT_REMOVEDIR). sqlite deletes its
   temp-directory / journal dirs through this; without it the reference decayed
   to a null slot (same class as the pread file-VFS null-call). */
int rmdir(const char *path) {
  int rc = __pxx_rmdir(path);
  if (rc < 0) { errno = -rc; return -1; }
  return 0;
}

long sysconf(int name) {
  if (name == _SC_PAGESIZE) return 4096;
  return -1;
}

/* isatty: 1 when fd is a terminal, 0 otherwise.
 *
 * The TCGETS ioctl, which is what libc does and the only test that separates a
 * terminal from another character device. fstat + S_ISCHR does NOT work:
 * /dev/null is a character device and is not a tty, so that version answers 1
 * for redirected output and every "am I interactive" branch — colour, progress
 * bars, prompting — takes the wrong path. Verified in both directions against
 * gcc: /dev/ptmx is a tty, /dev/null and a directory are not. */
int isatty(int fd) {
  int r = __pxx_isatty(fd);
  /* isatty answers 0/1, never -1: a negative PAL result (EBADF, ENOTTY) means
     "not a terminal" and must not leak out as a NEGATIVE, which every
     `if (isatty(fd))` would read as TRUE. */
  if (r < 0) { errno = -r; return 0; }
  return r ? 1 : 0;
}

/* dup/dup2: duplicate a descriptor. dup2 makes newfd refer to oldfd, closing
   whatever newfd was; dup picks the lowest free descriptor, which is what
   fcntl(F_DUPFD, 0) means and therefore is the primitive, not a substitute for
   a missing one. Both return the new descriptor, or -errno. */
int dup(int oldfd) { return sysret(__pxx_dup(oldfd)); }
int dup2(int oldfd, int newfd) { return sysret(__pxx_dup2(oldfd, newfd)); }

/* chdir changes PROCESS-GLOBAL state: every later relative path in the program
   resolves against it. Nothing in lib/rtl memoises the working directory
   (checked before adding this), so there is no stale cache to invalidate.

   symlink/link reach the kernel through symlinkat/linkat with AT_FDCWD, since
   aarch64 and riscv have no legacy symlink/link syscalls at all. */
int chdir(const char *path) { return sysret(__pxx_chdir(path)); }
int symlink(const char *target, const char *linkpath) {
  return sysret(__pxx_symlink(target, linkpath));
}
int link(const char *oldpath, const char *newpath) {
  return sysret(__pxx_link(oldpath, newpath));
}

/* Real ids, not zero: geteuid was already here, the rest were simply missing —
   and code that branches on getuid() == 0 to decide "am I root" would have
   taken the privileged path for everyone. */
int getuid(void)  { return __pxx_getuid(); }
int getgid(void)  { return __pxx_getgid(); }
int getegid(void) { return __pxx_getegid(); }
int getppid(void) { return __pxx_getppid(); }

int pipe(int fds[2]) { return sysret(__pxx_pipe2(fds, 0)); }

/* sleep/usleep over nanosleep, which crtl already had. sleep() returns the
   number of seconds LEFT if interrupted, which is 0 on a completed sleep — not
   a status code, so returning 0 unconditionally would be wrong only for the
   interrupted case the PAL does not surface. Documented rather than faked. */
unsigned int sleep(unsigned int seconds) {
  __pxx_nanosleep((long long)seconds, 0);
  return 0;
}

int usleep(unsigned int usec) {
  __pxx_nanosleep((long long)(usec / 1000000u), (long long)(usec % 1000000u) * 1000LL);
  return 0;
}

/* Linux is 4096 everywhere pxx targets. sysconf(_SC_PAGESIZE) is the portable
   spelling and returns the same thing. */
int getpagesize(void) { return 4096; }

/* ---- pre-main initialization ---------------------------------------------
 *
 * `environ` is a variable C code reads directly, so nothing can be lazy about
 * it the way getenv() is lazy about /proc/self/environ: by the time anyone
 * looks, it has to already hold the right pointer. It was a clean compile
 * producing NULL, which is worse than a diagnostic.
 *
 * __pxx_run_initializers is the pre-main shell the C entry stub calls before
 * it hands main its arguments. It receives the raw Linux initial stack
 * pointer, which is the one thing only the stub knows, and derives what it
 * needs here in C rather than in five hand-assembled stub sequences -- so the
 * next thing that must happen before main is a statement in this function.
 *
 * The initial stack is [argc][argv0]..[argvN-1][NULL][envp0]..[NULL], one
 * machine word per slot, and `long` is exactly that word on every target pxx
 * builds for (8 on LP64, 4 on ILP32), so the pointer arithmetic below scales
 * itself: envp starts at slot argc+2.
 *
 * ONE MEASURED DIVERGENCE FROM GCC, recorded rather than hidden: a program
 * that DEFINES `char **environ;` itself (rather than declaring it extern) gets
 * ours filled, where gcc leaves that program's own zero-initialised object
 * alone. POSIX reserves the name for the implementation and every real user in
 * this repo's corpora writes `extern char **environ;` (tcc's tccrun.c,
 * quickjs-libc.c); the one bare definition is in a win32 test tcc never builds
 * here. Filling it is the more useful answer and the divergence is on a shape
 * POSIX does not sanction, so it stands -- but it IS a divergence, and a
 * program relying on gcc's answer would see a different one.
 *
 * feature-c-entry-stub-must-run-initializers-for-environ
 */
char **environ;

void __pxx_run_initializers(long *sp)
{
  long argc = sp[0];
  environ = (char **)(sp + argc + 2);
}
