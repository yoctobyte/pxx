/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: unistd — libc-free fsync/getpid/sysconf for sqlite's unix VFS.
 * fsync/getpid forward to the Pascal PAL syscalls; sysconf answers the one
 * query sqlite makes (_SC_PAGESIZE) from a constant, no syscall.
 */

#include <unistd.h>
#include <errno.h>
#include <limits.h>
#include <string.h>
#include <stdlib.h>
#include <pwd.h>
#include <grp.h>
#include <sys/utsname.h>
#include <sys/syscall.h>
#include <sys/resource.h>  /* nice() is getpriority + setpriority */
#include <stdarg.h>

extern int __pxx_open(const char *path, int flags, int mode);
extern long long __pxx_read(int fd, void *buf, long long n);
extern long long __pxx_write(int fd, void *buf, long long n);
extern int __pxx_close(int fd);
extern long long __pxx_seek(int fd, long long offset, int whence);
extern int __pxx_fsync(int fd);
extern int __pxx_fdatasync(int fd);
extern int __pxx_sync(void);
extern int __pxx_setsid(void);
extern int __pxx_getgroups(int count, void *list);
extern int __pxx_getsid(int pid);
extern int __pxx_setpgid(int pid, int pgid);
extern int __pxx_getpgid(int pid);
extern int __pxx_alarm(unsigned int seconds);
extern int __pxx_sethostname(const char *name, int len);
extern int __pxx_setgroups(int count, void *list);
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
extern int __pxx_truncate(const char *path, long long length);
extern int __pxx_execve(const char *path, void *argv, void *envp);
extern int __pxx_access(const char *path, int mode);
extern int __pxx_fchown(int fd, int owner, int group);
extern int __pxx_chown(const char *path, int owner, int group);
extern int __pxx_lchown(const char *path, int owner, int group);
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

/* fdatasync(2): the DATA, and only the metadata a later read needs to find it.
   Not an alias for fsync -- the difference is the whole reason the call
   exists, and aliasing it gives a correct-but-slower answer under a name that
   promised a faster one. busybox's coreutils/shred.c and `sync -d' are the
   callers; busybox ASSUMES it exists (include/platform.h: HAVE_FDATASYNC 1 is
   the default), so there is no fallback path for it to take. */
int fdatasync(int fd) {
  int rc = __pxx_fdatasync(fd);
  if (rc < 0) { errno = -rc; return -1; }
  return 0;
}

/* sync(2) returns void in POSIX, so there is nothing to report and nothing to
   check -- the PAL's status is deliberately discarded here rather than
   smuggled out through errno, which no caller of sync() reads. On xtensa,
   ESP and WASI the PAL refuses (PAL_ERR_UNSUPPORTED) and this is a no-op,
   which is what a platform with no global buffer cache should do. */
void sync(void) { (void)__pxx_sync(); }

int getpid(void) { return __pxx_getpid(); }

/* sqlite's unix VFS needs these; all forward to a PAL syscall (LP64/ILP32 safe).
   Kernel returns 0/positive on success or -errno; translate to the C -1+errno. */
int ftruncate(int fd, off_t length) {
  int rc = __pxx_ftruncate(fd, (long)length);
  if (rc < 0) { errno = -rc; return -1; }
  return 0;
}

/* truncate by PATH. Unlike chown/lchown this is a real syscall on every target
   including the asm-generic ones -- there is no truncateat to route through. */
int truncate(const char *path, off_t length) {
  int rc = __pxx_truncate(path, (long long)length);
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

/* chown follows a symlink, lchown changes the LINK itself. The pair is not
   interchangeable and the difference is the reason lchown exists: busybox's
   libbb/copy_file.c uses it to preserve ownership when copying a tree, where
   following the link would chown whatever the link happens to point at --
   possibly outside the tree being copied.

   `owner`/`group` of (uid_t)-1 mean "leave unchanged", which survives the cast
   to int as -1 and reaches the kernel as the same sentinel. */
int chown(const char *path, uid_t owner, gid_t group) {
  int rc = __pxx_chown(path, (int)owner, (int)group);
  if (rc < 0) { errno = -rc; return -1; }
  return 0;
}

int lchown(const char *path, uid_t owner, gid_t group) {
  int rc = __pxx_lchown(path, (int)owner, (int)group);
  if (rc < 0) { errno = -rc; return -1; }
  return 0;
}

uid_t geteuid(void) { return (uid_t)__pxx_geteuid(); }

/* ---- process termination -------------------------------------------------- */

/* _exit(2) is _Exit's POSIX spelling: terminate WITHOUT running atexit
   handlers or flushing streams. Not an alias of exit(); the difference is the
   whole point of the name, and code that reaches for it (busybox after a
   failed exec) depends on the handlers not firing. */
extern void __pxx_exit(int code);
void _exit(int status) { __pxx_exit(status); }

/* ---- fd-relative and tty helpers ------------------------------------------ */

/* fchdir(2) and ttyname_r(3) have no PAL syscall of their own, so both go
   through /proc/self/fd/N, which is where the kernel already publishes the
   answer. That is a LINUX-ONLY route and it needs /proc mounted: in a chroot
   or a container without /proc, both fail with ENOSYS rather than guessing.
   Documented here rather than discovered later. */
static int pxx_fd_path(int fd, char *out, size_t outsz)
{
  char link[32];
  char digits[16];
  unsigned u = (unsigned)fd;
  int nd = 0, k = 0, i, rc, n;
  const char *pre = "/proc/self/fd/";

  if (fd < 0) { errno = EBADF; return -1; }
  do { digits[nd++] = (char)('0' + (u % 10)); u /= 10; } while (u);
  for (i = 0; pre[i]; i++) link[k++] = pre[i];
  while (nd > 0) link[k++] = digits[--nd];
  link[k] = 0;

  rc = __pxx_readlink(link, out, (int)outsz - 1);
  if (rc < 0) { errno = -rc; return -1; }
  n = rc;
  if ((size_t)n >= outsz) { errno = ERANGE; return -1; }
  out[n] = 0;
  return n;
}

int fchdir(int fd)
{
  char path[4096];
  if (pxx_fd_path(fd, path, sizeof(path)) < 0) return -1;
  { int rc = __pxx_chdir(path);
    if (rc < 0) { errno = -rc; return -1; } }
  return 0;
}

int ttyname_r(int fd, char *buf, size_t buflen)
{
  int n;
  if (!__pxx_isatty(fd)) { errno = ENOTTY; return ENOTTY; }
  n = pxx_fd_path(fd, buf, buflen);
  if (n < 0) return errno;
  return 0;
}

char *ttyname(int fd)
{
  static char pxx_ttyname_buf[4096];
  if (ttyname_r(fd, pxx_ttyname_buf, sizeof(pxx_ttyname_buf)) != 0) return 0;
  return pxx_ttyname_buf;
}

/* ---- link-only stubs: no PAL syscall exists for these --------------------- */

/* Same shape and the same honesty as execvp above: rather than fake a success
   these fail the way a libc on a platform without the call fails, -1 / ENOSYS.
   That is a defined answer a caller can act on, and it is loud — the
   alternative, a silent success that did nothing, is the failure mode that
   costs days.

   They exist at all because REFERENCING them is enough to break a link: real
   programs carry code paths they never take (busybox's libbb declares the
   privilege-dropping helpers in a TU whose only used function is a string
   routine). Providing the symbol lets that program link; taking the path it
   never takes gets an error, not a lie.

   *** WHICH OF THESE THE PAL COULD ACTUALLY SERVE — because an earlier draft
   of this comment got it wrong, AND THEN A LATER ONE GOT IT WRONG AGAIN IN THE
   OPPOSITE DIRECTION. *** chroot and setuid/setgid/seteuid/setegid have no PAL
   entry: those really are missing syscalls. setgroups DID belong on that list
   and no longer does -- PalSetGroups arrived with the busybox userland work,
   so its body below is real and this sentence was corrected rather than left
   to become the third wrong version of it.

   fork() IS NOT ONE OF THEM, and it never was. The previous version of this
   comment argued that the PAL offered only a `PalVfork', that vfork is not
   fork (the child shares the parent's memory and may do nothing but exec or
   _exit), and that wiring fork to it would therefore be a silent corruption.
   Every sentence of that is true about VFORK and none of it was true about the
   entry: PalVfork's body issued SYS_fork, or clone with SIGCHLD and no
   CLONE_VM, which IS fork. The reasoning ran off the NAME and stopped there —
   in a comment whose own closing line says to MEASURE the PAL before believing
   that an entry is missing. busybox ash then failed with `can't fork' against
   a PAL that had had fork since it was written.

   The entry is now called PalFork (see the note at PalBackendFork for why
   renaming it beat leaving it), and fork() below is real. */
int chroot(const char *path)   { (void)path; errno = ENOSYS; return -1; }

extern int __pxx_fork(void);

pid_t fork(void) {
  int rc = __pxx_fork();
  if (rc < 0) { errno = -rc; return -1; }
  return (pid_t)rc;
}

/* vfork is given fork's semantics, which is a DIVERGENCE worth naming rather
   than a synonym. A program that honours vfork's contract — the child does
   nothing but exec or _exit — cannot tell the two apart, and that is every
   real caller including busybox. A program that VIOLATES the contract, by
   having the child write a variable the parent then reads, gets the standard's
   undefined behaviour and will read the old value here where a true vfork
   would show the new one. Diverging in that direction is the safe one: the
   child can no longer corrupt the parent's stack. The cost is that vfork's
   performance reason for existing is gone, which is a fair trade for a
   runtime that has no copy-on-write-free path to offer anyway. */
pid_t vfork(void) {
  return fork();
}
int setuid(uid_t uid)          { (void)uid; errno = ENOSYS; return -1; }
int setgid(gid_t gid)          { (void)gid; errno = ENOSYS; return -1; }
int seteuid(uid_t uid)         { (void)uid; errno = ENOSYS; return -1; }
int setegid(gid_t gid)         { (void)gid; errno = ENOSYS; return -1; }

/* setgroups(2) IS REAL NOW -- PalSetGroups sits on setgroups32 where the target
   needs it (i386, arm32), which is the same *32 choice getgroups already makes.
   It is left here among the privilege calls rather than moved, because the
   sentence above about which of these the PAL could serve is the thing that has
   to stay true, and moving the body would leave that list naming a function
   that is no longer on it. */
int setgroups(size_t n, const gid_t *list) {
  int rc = __pxx_setgroups((int)n, n == 0 ? 0 : (void *)list);
  if (rc < 0) { errno = -rc; return -1; }
  return 0;
}


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

/* execve: replace the process image. On SUCCESS IT DOES NOT RETURN, so every
   return here is a failure -- there is no rc==0 path to write. */
int execve(const char *path, char *const argv[], char *const envp[]) {
  int rc = __pxx_execve(path, (void *)argv, (void *)envp);
  errno = -rc;
  return -1;
}

/* execvp: search PATH for `file' and exec it.
 *
 * This was a LINK-ONLY STUB that always set ENOENT and returned -1. That is
 * worse than it looks: ENOENT means "no such file", so a caller was told the
 * program did not exist when it did, and the two cases are indistinguishable
 * to it. Now that there is an execve bridge the real thing is short, so the
 * stub is gone rather than documented.
 *
 * Semantics that are easy to get subtly wrong and are deliberate here:
 *   - a `file' containing '/' is NOT searched; it is used as given, per POSIX.
 *   - an empty PATH entry means the current directory ("::" and a leading or
 *     trailing ':'), which is historical POSIX behaviour real scripts rely on.
 *   - ENOENT while walking is not fatal: keep trying later entries and report
 *     the LAST meaningful error, so a name present in the second PATH entry is
 *     found even though the first missed.
 *   - EACCES anywhere is remembered and preferred over a trailing ENOENT,
 *     because "found but not executable" is the more useful diagnosis and is
 *     what execvp is specified to report.
 */
extern char **environ;

int execvp(const char *file, char *const argv[]) {
  const char *path;
  char buf[PATH_MAX];
  int sawEaccess = 0;
  size_t flen;

  if (!file || !*file) { errno = ENOENT; return -1; }

  if (strchr(file, '/')) {
    execve(file, argv, environ);
    return -1;                      /* errno already set by execve */
  }

  path = getenv("PATH");
  if (!path) path = "/bin:/usr/bin";

  flen = strlen(file);
  while (*path) {
    const char *seg = path;
    size_t seglen;
    while (*path && *path != ':') path++;
    seglen = (size_t)(path - seg);
    if (*path == ':') path++;

    /* An empty entry is the current directory. */
    if (seglen == 0) { seg = "."; seglen = 1; }
    if (seglen + 1 + flen + 1 > sizeof buf) continue;   /* cannot fit; skip */

    memcpy(buf, seg, seglen);
    buf[seglen] = '/';
    memcpy(buf + seglen + 1, file, flen);
    buf[seglen + 1 + flen] = '\0';

    execve(buf, argv, environ);
    if (errno == EACCES) sawEaccess = 1;
    else if (errno != ENOENT) return -1;   /* a real error: stop here */
  }

  errno = sawEaccess ? EACCES : ENOENT;
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
  /* USER_HZ, not CONFIG_HZ: the kernel's internal tick rate is a build option,
     but the one it reports through times(2) and /proc has been 100 on every
     Linux ABI pxx targets since 2.6. A shell divides times() by this to print
     `time' output, so a wrong value is a plausible wrong NUMBER rather than a
     failure. */
  if (name == _SC_CLK_TCK) return 100;
  /* The default RLIMIT_NOFILE soft limit. Callers use it to size a descriptor
     table or to bound a close-all loop, so answering -1 here is worse than
     answering the conventional value. */
  if (name == _SC_OPEN_MAX) return 1024;
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

/* The half that knows what `environ` IS, split out from the half that knows
 * where a PROCESS keeps it.
 *
 * A shared library has no Linux initial stack to read: at DT_INIT time the
 * stack pointer is somewhere inside ld.so, and reading argc off it yields
 * whatever happens to be there. What a .so DOES get is the loader's own
 * (argc, argv, envp) arguments, so the shared-library init thunk calls this
 * one directly with envp and never touches sp.
 *
 * Two callers, one fact: the stack layout stays in __pxx_run_initializers
 * alone, and the assignment stays here alone, so neither can drift into the
 * other. A .so that read `environ` got (nil) before this existed.
 * bug-a-c-a-shared-library-never-runs-its-initialisation
 */
void __pxx_set_environ(char **envp)
{
  environ = envp;
}

void __pxx_run_initializers(long *sp)
{
  long argc = sp[0];
  __pxx_set_environ((char **)(sp + argc + 2));
}

/* ---------------------------------------------------------------------------
   getopt — option scanning, matching glibc rather than bare POSIX.

   Written because busybox's getopt32 is the first thing every applet calls and
   crtl had no getopt at all: `optind` came out as "undeclared identifier used
   as value (treated as 0)" and `getopt` as a call to an undeclared function.

   GNU PERMUTATION IS IMPLEMENTED, and that was a deliberate second pass. POSIX
   stops at the first non-option, so `cat file -n` would treat `-n` as a
   filename -- while every oracle we diff against is glibc-built, and glibc
   permutes. Matching the standard rather than the oracle would have produced a
   difference in exactly the shape this corpus exists to detect, and called it
   conformance. Differential-tested against glibc over the argv shapes at the
   bottom of this comment.

   Reset: glibc reinitialises when optind is set to 0, BSD when optreset is set
   to 1. Both work, because busybox chooses between the two spellings at compile
   time (GETOPT_RESET) and other real code does too.

   NOT implemented: the leading `+` / `-` optstring modes. A leading ':' IS
   honoured -- it costs one branch and callers use it to tell a missing
   argument from an unknown option. getopt_long and getopt_long_only ARE
   implemented (below, over the one parser pxx_getopt_impl); this line said they
   were not, and stayed that way after they landed. Checked 2026-09-02 by
   running `--file=abc -v --verbose rest' against glibc, not by reading it.

   Verified identical to glibc, stdout and stderr and exit status, for:
     -a -b -o X f1 f2 | -abo Y f | -a -- -b | f -a | -z | -o
     f1 -a f2 -o X f3 | -- -a | f -- -a | (no args)                          */
char *optarg = 0;
int optind = 1;
int opterr = 1;
int optopt = 0;
int optreset = 0;

static int pxx_optpos = 1;   /* index of the next char INSIDE argv[optind] */

static void pxx_getopt_err(const char *prog, const char *msg, char c)
{
    /* glibc's exact format: "<argv[0]>: invalid option -- 'z'". Written from
       the pieces we have rather than with fprintf, so option parsing does not
       drag stdio into a program that did not ask for it. */
    char buf[4];
    const char *p;
    for (p = prog; p && *p; p++) __pxx_write(2, (void *)p, 1);
    __pxx_write(2, (void *)": ", 2);
    for (p = msg; *p; p++) __pxx_write(2, (void *)p, 1);
    buf[0] = '\''; buf[1] = c; buf[2] = '\''; buf[3] = '\n';
    __pxx_write(2, buf, 4);
}

/* The long-option half of the error format. glibc writes
     <prog>: unrecognized option '--xyz'
     <prog>: option '--xyz' requires an argument
   and the quoting and the dash count are part of what a transcript comparison
   sees, so the caller passes the dash count it actually parsed -- `-name' under
   getopt_long_only prints with ONE dash, not two. */
static void pxx_getopt_lerr(const char *prog, const char *pre, int dashes,
                            const char *name, int nlen, const char *post)
{
    const char *p;
    int i;
    for (p = prog; p && *p; p++) __pxx_write(2, (void *)p, 1);
    __pxx_write(2, (void *)": ", 2);
    for (p = pre; *p; p++) __pxx_write(2, (void *)p, 1);
    __pxx_write(2, (void *)"'", 1);
    for (i = 0; i < dashes; i++) __pxx_write(2, (void *)"-", 1);
    for (i = 0; i < nlen; i++) __pxx_write(2, (void *)&name[i], 1);
    __pxx_write(2, (void *)"'", 1);
    for (p = post; *p; p++) __pxx_write(2, (void *)p, 1);
    __pxx_write(2, (void *)"\n", 1);
}

/* glibc does not stop at "is ambiguous": it lists the candidates, and the list
   is part of what a transcript comparison sees. Written out here rather than
   documented as a divergence, because the whole point of this file is that a
   program built with pxx prints what the same program built with glibc prints.
     <prog>: option '--ca' is ambiguous; possibilities: '--car' '--cart'   */
static void pxx_getopt_amb(const char *prog, int dashes, const char *name,
                           int nlen, const struct option *longopts)
{
    const char *p;
    int i, j;
    for (p = prog; p && *p; p++) __pxx_write(2, (void *)p, 1);
    __pxx_write(2, (void *)": option '", 10);
    for (i = 0; i < dashes; i++) __pxx_write(2, (void *)"-", 1);
    for (i = 0; i < nlen; i++) __pxx_write(2, (void *)&name[i], 1);
    __pxx_write(2, (void *)"' is ambiguous; possibilities:", 30);
    for (i = 0; longopts[i].name; i++) {
        j = 0;
        while (j < nlen && longopts[i].name[j] && longopts[i].name[j] == name[j]) j++;
        if (j != nlen) continue;
        __pxx_write(2, (void *)" '", 2);
        for (j = 0; j < dashes; j++) __pxx_write(2, (void *)"-", 1);
        for (p = longopts[i].name; *p; p++) __pxx_write(2, (void *)p, 1);
        __pxx_write(2, (void *)"'", 1);
    }
    __pxx_write(2, (void *)"\n", 1);
}

static int pxx_is_opt(const char *s)
{
    return s != 0 && s[0] == '-' && s[1] != 0;
}

/* glibc's own bookkeeping, and the reason for it is case
   `f1 -a f2 -o X f3`: a naive "rotate the option to optind as you find it"
   takes the option's separate ARGUMENT from the permuted vector and comes back
   with optarg = "f1" instead of "X". glibc avoids that by DEFERRING the
   exchange to the next option boundary, so an option and its argument are
   always consumed from their original positions. [first_nonopt, last_nonopt)
   is the run of non-options skipped so far. */
static int pxx_first_nonopt = 1;
static int pxx_last_nonopt = 1;

static void pxx_exchange(char **av)
{
    /* Move the skipped non-options [first_nonopt, last_nonopt) to sit AFTER
       the options that followed them, [last_nonopt, optind). A left-rotation
       of [first_nonopt, optind) by (last_nonopt - first_nonopt) does it, and
       keeps both groups in their original relative order. */
    int lo = pxx_first_nonopt, mid = pxx_last_nonopt, hi = optind;
    int n = mid - lo, i, j;
    char *tmp;
    if (n <= 0 || hi <= mid) return;
    for (i = 0; i < n; i++) {
        tmp = av[lo];
        for (j = lo; j + 1 < hi; j++) av[j] = av[j + 1];
        av[hi - 1] = tmp;
    }
    pxx_first_nonopt += hi - mid;
    pxx_last_nonopt = hi;
}

/* ONE parser for getopt, getopt_long and getopt_long_only. They differ only in
   whether a `--name' (or, for long_only, a `-name') at an argument boundary is
   looked up in a table before the character loop runs, and in nothing else --
   the permutation bookkeeping, the `--' terminator, the reset rules and the
   error formats are shared. Writing the long form as a second parser would
   duplicate all of that, and the copy is the one that stays broken. */
static int pxx_getopt_impl(int argc, char *const argv[], const char *optstring,
                           const struct option *longopts, int *longindex,
                           int long_only)
{
    const char *spec;
    char **av = (char **)argv;     /* glibc permutes in place too */
    const char *prog;
    char c;
    int silent;

    if (optind == 0 || optreset) {   /* glibc-style / BSD-style reset */
        optind = 1;
        optreset = 0;
        pxx_optpos = 1;
        pxx_first_nonopt = 1;
        pxx_last_nonopt = 1;
    }
    if (optstring == 0) return -1;
    silent = (optstring[0] == ':');
    if (silent) optstring++;
    prog = (argc > 0 && av[0]) ? av[0] : "";

    if (pxx_optpos == 1) {
        /* At an argument boundary. Settle any deferred permutation, then skip
           over the non-options to the next option. */
        if (pxx_last_nonopt > optind) pxx_last_nonopt = optind;
        if (pxx_first_nonopt > optind) pxx_first_nonopt = optind;
        if (pxx_first_nonopt != pxx_last_nonopt && pxx_last_nonopt != optind)
            pxx_exchange(av);
        else if (pxx_last_nonopt != optind)
            pxx_first_nonopt = optind;
        while (optind < argc && av[optind] != 0 && !pxx_is_opt(av[optind])) optind++;
        pxx_last_nonopt = optind;

        if (optind < argc && av[optind] != 0
            && av[optind][1] == '-' && av[optind][2] == 0) {
            /* "--": the options end here. Consume the marker, flush the
               permutation, and leave optind on the first operand. */
            optind++;
            if (pxx_first_nonopt != pxx_last_nonopt && pxx_last_nonopt != optind)
                pxx_exchange(av);
            else if (pxx_first_nonopt == pxx_last_nonopt)
                pxx_first_nonopt = optind;
            pxx_last_nonopt = argc;
            optind = pxx_first_nonopt;
            return -1;
        }
        if (optind >= argc || av[optind] == 0) {
            /* Out of arguments: leave optind on the first non-option, which is
               where the caller's own operand loop starts. */
            optind = pxx_first_nonopt;
            return -1;
        }
    }

    /* ---- long options -------------------------------------------------
       Only at an argument boundary: `-abc' mid-cluster is never a long name,
       and checking there would make `-l' inside `-al' match a `--list'. */
    if (longopts && pxx_optpos == 1 && av[optind][0] == '-') {
        const char *arg = av[optind];
        int dashes = (arg[1] == '-') ? 2 : 1;
        if (dashes == 2 || (long_only && arg[1] != 0)) {
            const char *nm = arg + dashes;
            const char *eq = nm;
            int nlen, i, match = -1, nmatch = 0;
            while (*eq && *eq != '=') eq++;
            nlen = (int)(eq - nm);
            for (i = 0; longopts[i].name; i++) {
                int j = 0;
                while (j < nlen && longopts[i].name[j]
                       && longopts[i].name[j] == nm[j]) j++;
                if (j != nlen) continue;
                if (longopts[i].name[nlen] == 0) { match = i; nmatch = 1; break; }
                /* a PREFIX: glibc accepts it when it is unique */
                if (match < 0) match = i;
                nmatch++;
            }
            /* long_only: a single-dash argument that is not a long name falls
               through to the SHORT parser, which is the whole point of the
               "only" form -- `-h' must still work when `--help' exists. */
            if (nmatch == 0 && dashes == 1) goto short_option;

            optind++;
            pxx_optpos = 1;
            if (nmatch == 0) {
                if (opterr && !silent)
                    pxx_getopt_lerr(prog, "unrecognized option ", dashes, nm, nlen, "");
                optopt = 0;
                return '?';
            }
            if (nmatch > 1) {
                /* DIVERGENCE, documented: glibc goes on to list the candidates
                   ("; possibilities: '--aa' '--ab'"). We say it is ambiguous and
                   stop. The decision -- reject -- is the same one, and it is the
                   decision a program branches on. */
                if (opterr && !silent)
                    pxx_getopt_amb(prog, dashes, nm, nlen, longopts);
                optopt = 0;
                return '?';
            }
            optarg = 0;
            if (*eq == '=') {
                if (longopts[match].has_arg == no_argument) {
                    if (opterr && !silent)
                        pxx_getopt_lerr(prog, "option ", dashes, nm, nlen,
                                        " doesn't allow an argument");
                    optopt = longopts[match].val;
                    return '?';
                }
                optarg = (char *)eq + 1;
            } else if (longopts[match].has_arg == required_argument) {
                if (optind >= argc || av[optind] == 0) {
                    if (opterr && !silent)
                        pxx_getopt_lerr(prog, "option ", dashes, nm, nlen,
                                        " requires an argument");
                    optopt = longopts[match].val;
                    return silent ? ':' : '?';
                }
                optarg = av[optind];
                optind++;
            }
            if (longindex) *longindex = match;
            if (longopts[match].flag) {
                *longopts[match].flag = longopts[match].val;
                return 0;
            }
            return longopts[match].val;
        }
    }
short_option:
    c = av[optind][pxx_optpos];
    optopt = (int)(unsigned char)c;

    spec = optstring;
    while (*spec && *spec != c) spec++;
    if (*spec == 0 || c == ':') {
        /* Unknown option. Advance past it exactly as a known one would, or the
           next call re-reads the same character forever. */
        pxx_optpos++;
        if (av[optind][pxx_optpos] == 0) { optind++; pxx_optpos = 1; }
        if (opterr && !silent) pxx_getopt_err(prog, "invalid option -- ", c);
        return '?';
    }

    if (spec[1] == ':') {           /* the option takes an argument */
        if (av[optind][pxx_optpos + 1] != 0) {
            optarg = &av[optind][pxx_optpos + 1];         /* -ovalue */
            optind++;
        } else {
            optind++;
            if (optind >= argc || av[optind] == 0) {      /* -o with nothing after it */
                pxx_optpos = 1;
                if (opterr && !silent) pxx_getopt_err(prog, "option requires an argument -- ", c);
                return silent ? ':' : '?';
            }
            optarg = av[optind];                          /* -o value */
            optind++;
        }
        pxx_optpos = 1;
        return (int)(unsigned char)c;
    }

    /* A flag. Walk to the next character in the same cluster (-abc), and move
       to the next argv only when the cluster is exhausted. */
    pxx_optpos++;
    if (av[optind][pxx_optpos] == 0) { optind++; pxx_optpos = 1; }
    return (int)(unsigned char)c;
}

int getopt(int argc, char *const argv[], const char *optstring)
{
    return pxx_getopt_impl(argc, argv, optstring, 0, 0, 0);
}

int getopt_long(int argc, char *const argv[], const char *optstring,
                const struct option *longopts, int *longindex)
{
    return pxx_getopt_impl(argc, argv, optstring, longopts, longindex, 0);
}

int getopt_long_only(int argc, char *const argv[], const char *optstring,
                     const struct option *longopts, int *longindex)
{
    return pxx_getopt_impl(argc, argv, optstring, longopts, longindex, 1);
}

/* ---- login name ----------------------------------------------------------- */

/* getlogin_r(3) / getlogin(3).
 *
 * A DELIBERATE DIVERGENCE, and the reason is that glibc answers a different
 * question than the name suggests: it looks up the CONTROLLING TERMINAL in
 * utmp, so it reports who logged in on this tty and fails outright when there
 * is no tty -- in a pipeline, a cron job, or a container with no utmp. There is
 * no utmp on the systems pxx targets and no way to synthesise one.
 *
 * So this answers the question callers actually mean: LOGNAME, then USER, then
 * the passwd entry for the real uid. busybox's coreutils/logname.c is the
 * consumer and prints exactly this. The difference is observable -- `su' to
 * another user leaves LOGNAME pointing at the original on some systems, where
 * glibc would still report the tty's owner -- and is documented rather than
 * hidden. Returns 0, or an errno value (never -1): ERANGE when the buffer is
 * too small, ENXIO when no name can be determined.
 */
int getlogin_r(char *buf, size_t bufsize) {
  const char *nm;
  struct passwd *pw;
  size_t n;

  if (!buf || bufsize == 0) return EINVAL;
  nm = getenv("LOGNAME");
  if (!nm || !*nm) nm = getenv("USER");
  if (!nm || !*nm) {
    pw = getpwuid(getuid());
    nm = pw ? pw->pw_name : 0;
  }
  if (!nm || !*nm) return ENXIO;
  n = strlen(nm);
  if (n + 1 > bufsize) return ERANGE;
  memcpy(buf, nm, n + 1);
  return 0;
}

char *getlogin(void) {
  /* One static buffer, invalidated by the next call -- glibc's contract. */
  static char pxx_login_buf[256];
  if (getlogin_r(pxx_login_buf, sizeof pxx_login_buf) != 0) return 0;
  return pxx_login_buf;
}

/* setsid(2): make the caller a session leader. busybox's
   libbb/vfork_daemon_rexec.c calls it in bb_daemonize_or_rexec, which is how
   every daemonising applet detaches from its controlling terminal.
   Returns the new session id (which is the pid) or -1/errno. */
int setsid(void) {
  int rc = __pxx_setsid();
  if (rc < 0) { errno = -rc; return -1; }
  return rc;
}

/* getgroups(2). size == 0 asks only for the COUNT and must not touch list --
   that is the call every caller makes first, to size its array, so it is the
   one that has to be right. Otherwise -1/EINVAL when the list is shorter than
   the answer, which is the kernel's own behaviour and is what tells a caller
   its buffer was too small. */
int getgroups(int size, gid_t list[]) {
  int rc;
  if (size < 0) { errno = EINVAL; return -1; }
  rc = __pxx_getgroups(size, size == 0 ? 0 : (void *)list);
  if (rc < 0) { errno = -rc; return -1; }
  return rc;
}

/* getsid(2): the session id of `pid', or of the caller when pid is 0.
   procps/kill.c uses it to skip the session leader when killing a whole
   session, so a wrong answer there kills the wrong process rather than
   failing. */
int getsid(pid_t pid) {
  int rc = __pxx_getsid((int)pid);
  if (rc < 0) { errno = -rc; return -1; }
  return rc;
}

/* setpgid(2). pid 0 is the caller; pgid 0 is "the pid's own value", so
   setpgid(0, 0) makes the caller a process-group leader. */
int setpgid(pid_t pid, pid_t pgid) {
  int rc = __pxx_setpgid((int)pid, (int)pgid);
  if (rc < 0) { errno = -rc; return -1; }
  return 0;
}

pid_t getpgid(pid_t pid) {
  int rc = __pxx_getpgid((int)pid);
  if (rc < 0) { errno = -rc; return -1; }
  return (pid_t)rc;
}

/* setpgrp(): POSIX's zero-argument form, which IS setpgid(0, 0). The BSD
   two-argument setpgrp(pid, pgid) is a different function with the same name
   and is NOT provided -- a program written against it would compile here and
   silently ignore both arguments, which is worse than not compiling. */
int setpgrp(void) {
  return setpgid(0, 0);
}

/* alarm(2). RETURNS THE OLD ALARM'S REMAINING SECONDS, not an error code --
   there is no error case a caller can act on, and a `return 0' stub would be
   indistinguishable from "no alarm was pending", which is a real answer. The
   part-second rounding happens in the PAL, next to the timer values it read. */
unsigned int alarm(unsigned int seconds) {
  int rc = __pxx_alarm(seconds);
  if (rc < 0) return 0;
  return (unsigned int)rc;
}

int gethostname(char *name, size_t len) {
  struct utsname u;
  size_t n;
  if (!name) { errno = EFAULT; return -1; }
  if (uname(&u) < 0) return -1;
  n = strlen(u.nodename);
  /* ENAMETOOLONG rather than a truncated copy: `n + 1 > len' counts the
     terminator, because a name that exactly fills the buffer has nowhere to
     put it and POSIX leaves that case unspecified -- refusing is the answer
     that cannot hand back an unterminated string. */
  if (n + 1 > len) { errno = ENAMETOOLONG; return -1; }
  memcpy(name, u.nodename, n + 1);
  return 0;
}

/* ---- gethostid ------------------------------------------------------------
 *
 * Parses /etc/hosts itself rather than going through gethostbyname, and that is
 * a consequence of the crtl splice model rather than a preference: a header
 * pulls in the .c file paired with it, so a program that includes only
 * <unistd.h> must find every unistd.h function HERE. Reaching into
 * src/netinet/in.c from this file would leave that program with an undefined
 * symbol at link. If gethostbyname ever becomes real (it is a stub today,
 * returning 0 for every name), this stays the /etc/hosts reader for <unistd.h>
 * and the two are expected to agree -- so change them together.
 */
static int pxx_hosts_addr(const char *want, unsigned int *out)
{
  /* /etc/hosts: "<address> <name> [alias...]", '#' to end of line. Matches the
     FIRST line that carries `want' as the canonical name or as an alias, which
     is the order glibc's files backend uses. */
  char buf[8192];
  int fd, i, n, start;
  long long got;
  fd = __pxx_open("/etc/hosts", 0, 0);
  if (fd < 0) return 0;
  got = __pxx_read(fd, buf, (long long)sizeof(buf) - 1);
  __pxx_close(fd);
  if (got <= 0) return 0;
  buf[got] = 0;
  n = (int)got;
  i = 0;
  while (i < n) {
    int eol, tok, tlen, fieldno = 0;
    unsigned int a0 = 0, a1 = 0, a2 = 0, a3 = 0;
    int haveaddr = 0, matched = 0;
    start = i;
    eol = i;
    while (eol < n && buf[eol] != '\n') eol++;
    /* strip a comment */
    { int c = start; while (c < eol && buf[c] != '#') c++; if (c < eol) eol = c; }
    i = eol;
    while (i < n && buf[i] != '\n') i++;
    i++;                              /* past the newline */
    tok = start;
    while (tok < eol) {
      while (tok < eol && (buf[tok] == ' ' || buf[tok] == '\t')) tok++;
      tlen = 0;
      while (tok + tlen < eol && buf[tok + tlen] != ' ' && buf[tok + tlen] != '\t') tlen++;
      if (tlen == 0) break;
      if (fieldno == 0) {
        /* dotted quad only -- an IPv6 line has no address this call can use,
           and glibc's own fallback asks for an AF_INET address too */
        int k = 0; unsigned int v = 0; int part = 0, digits = 0;
        haveaddr = 1;
        for (k = 0; k <= tlen; k++) {
          if (k < tlen && buf[tok + k] >= '0' && buf[tok + k] <= '9') {
            v = v * 10u + (unsigned int)(buf[tok + k] - '0');
            digits++;
            if (v > 255u) { haveaddr = 0; break; }
          } else if ((k < tlen && buf[tok + k] == '.') || k == tlen) {
            if (digits == 0) { haveaddr = 0; break; }
            if (part == 0) a0 = v; else if (part == 1) a1 = v;
            else if (part == 2) a2 = v; else if (part == 3) a3 = v;
            part++; v = 0; digits = 0;
            if (part > 4) { haveaddr = 0; break; }
          } else { haveaddr = 0; break; }
        }
        if (part != 4) haveaddr = 0;
      } else {
        int k = 0;
        while (k < tlen && want[k] && buf[tok + k] == want[k]) k++;
        if (k == tlen && want[k] == 0) matched = 1;
      }
      tok += tlen;
      fieldno++;
    }
    if (haveaddr && matched) {
      /* NETWORK byte order, the same value a struct in_addr would hold */
      *out = (a0) | (a1 << 8) | (a2 << 16) | (a3 << 24);
      return 1;
    }
  }
  return 0;
}

long gethostid(void)
{
  unsigned char idbuf[4];
  char host[256];
  unsigned int a = 0;
  int fd;
  long long got;

  fd = __pxx_open("/etc/hostid", 0, 0);
  if (fd >= 0) {
    got = __pxx_read(fd, idbuf, 4);
    __pxx_close(fd);
    /* The file holds the id as a 32-bit value in HOST byte order, which is what
       sethostid wrote; glibc reads it straight back. */
    if (got == 4)
      return (long)(int)((unsigned int)idbuf[0] | ((unsigned int)idbuf[1] << 8)
                       | ((unsigned int)idbuf[2] << 16) | ((unsigned int)idbuf[3] << 24));
  }
  if (gethostname(host, sizeof(host)) != 0) return 0;
  host[sizeof(host) - 1] = 0;
  if (!pxx_hosts_addr(host, &a)) return 0;
  /* glibc's exact transform, halves swapped. 127.0.1.1 is 0x0101007f in a
     struct in_addr on a little-endian box, and 0x007f0101 after the swap --
     which is the number glibc prints, so this is not a re-derivation but the
     same arithmetic. */
  return (long)(int)((a << 16) | (a >> 16));
}

int sethostname(const char *name, size_t len) {
  int rc;
  if (!name) { errno = EFAULT; return -1; }
  rc = __pxx_sethostname((char *)name, (int)len);
  if (rc < 0) { errno = -rc; return -1; }
  return 0;
}

/* initgroups(3): the supplementary groups of `user', plus `group' itself.

   THE PRIMARY GROUP IS INCLUDED and that is not an accident of the interface:
   POSIX has the caller pass it separately because /etc/group's member lists do
   NOT name a user in their own primary group. Dropping it drops exactly the
   group most likely to matter. getgrouplist already applies that rule, so this
   is a size-then-fill over it rather than a second walk of the file. */
int initgroups(const char *user, gid_t group) {
  gid_t stackbuf[64];
  gid_t *list = stackbuf;
  int n = (int)(sizeof stackbuf / sizeof stackbuf[0]);
  int rc;

  if (!user) { errno = EINVAL; return -1; }
  if (getgrouplist(user, group, list, &n) < 0) {
    /* getgrouplist wrote the TRUE count into n on failure (glibc's contract),
       so the retry is sized rather than doubled blindly. */
    if (n <= 0) { errno = EINVAL; return -1; }
    list = (gid_t *)malloc((size_t)n * sizeof(gid_t));
    if (!list) { errno = ENOMEM; return -1; }
    if (getgrouplist(user, group, list, &n) < 0) { free(list); errno = EINVAL; return -1; }
  }
  rc = setgroups(n, list);
  if (list != stackbuf) free(list);
  return rc;
}

/* ---- the `l' forms of exec, plus execv ------------------------------------
 *
 * All four are wrappers -- there is one syscall (execve) and execvp's PATH
 * search sits above it. What is worth care here is the TERMINATOR and the
 * BOUND, because both failure modes are silent:
 *
 *  - The variadic list ends at a NULL argument. A caller that forgets it makes
 *    the loop read past the arguments actually passed, and the program is
 *    exec'd with garbage argv entries rather than failing. Nothing can detect
 *    that from inside; the terminator IS the contract.
 *  - The list is capped at PXX_EXEC_MAXARGS. Over that, E2BIG -- NOT a
 *    truncated argv, which would run the program with fewer arguments than the
 *    source wrote and look like success.
 *
 * execle's envp comes AFTER the terminating NULL, which is the one genuinely
 * surprising part of the family's shape and why it fetches one more argument
 * once the loop has ended.
 *
 * Found attempting busybox rung 2: init/halt.c and miscutils/crontab.c call
 * execlp; init/init.c and shell/ash.c call execl and execv.
 */
#define PXX_EXEC_MAXARGS 63

/* Collect the variadic list into `out'. Returns the count, or -1 if the list
   ran past the cap. `*envp_out', when asked for, receives the argument that
   follows the terminating NULL (execle's environment). */
static int exec_collect(const char *arg, va_list ap, char **out,
                        char ***envp_out) {
  int n = 0;
  out[n++] = (char *)arg;
  if (arg != 0) {
    for (;;) {
      char *a;
      if (n > PXX_EXEC_MAXARGS) return -1;
      a = va_arg(ap, char *);
      out[n++] = a;
      if (a == 0) break;
    }
  }
  if (envp_out) *envp_out = va_arg(ap, char **);
  return n;
}

int execv(const char *path, char *const argv[]) {
  return execve(path, argv, environ);   /* environ is declared in <unistd.h> */
}

int execl(const char *path, const char *arg, ...) {
  char *argv[PXX_EXEC_MAXARGS + 2];
  va_list ap;
  int n;
  va_start(ap, arg);
  n = exec_collect(arg, ap, argv, 0);
  va_end(ap);
  if (n < 0) { errno = E2BIG; return -1; }
  return execv(path, argv);
}

int execlp(const char *file, const char *arg, ...) {
  char *argv[PXX_EXEC_MAXARGS + 2];
  va_list ap;
  int n;
  va_start(ap, arg);
  n = exec_collect(arg, ap, argv, 0);
  va_end(ap);
  if (n < 0) { errno = E2BIG; return -1; }
  return execvp(file, argv);
}

int execle(const char *path, const char *arg, ...) {
  char *argv[PXX_EXEC_MAXARGS + 2];
  char **envp = 0;
  va_list ap;
  int n;
  va_start(ap, arg);
  n = exec_collect(arg, ap, argv, &envp);
  va_end(ap);
  if (n < 0) { errno = E2BIG; return -1; }
  return execve(path, argv, envp);
}

/*
 * syscall(2): the raw kernel interface, for calls the PAL has no entry for.
 *
 * IT LIVES HERE, NOT IN src/sys/syscall.c, because crtl auto-pulls src/<x>.c
 * when <x.h> COMPLETES and the declaration is in <unistd.h>. A program that
 * included only <unistd.h> -- which is where every libc declares it, and the
 * only header that declares it here -- reached the declaration and never the
 * definition, and silently acquired the symbol from the system C library
 * instead, ABI unchecked. tools/crtl_reachability.py is the lint that says so.
 * <sys/syscall.h> is numbers only and needs no sibling .c at all.
 *
 * The escape hatch, and it is one on purpose. Everything else crtl offers goes
 * through a named PAL entry that the non-Linux backends can refuse in terms
 * of; this hands the kernel interface to the caller directly, because a
 * program spelling syscall(2) has asked for exactly that. busybox's
 * util-linux/ionice.c (ioprio_get/ioprio_set) and modutils (finit_module) are
 * why it exists -- the alternative is a bespoke PAL entry per exotic call,
 * each used once, and none of them portable anyway.
 *
 * SIX ARGUMENTS ARE ALWAYS FETCHED, however many were passed. That is what
 * every libc does (in asm, which is why it is not UB there), and it is safe
 * for the same reason: the kernel reads only the registers the call number
 * defines, so the extra words are never looked at. A variadic C version cannot
 * know the count -- the number decides it -- so there is nothing else to do.
 *
 * The PAL returns the kernel's answer untranslated: negative is -errno, and
 * the conversion to -1/errno happens here, once. A call that legitimately
 * returns a large negative value (there is none in Linux's table -- the kernel
 * reserves -1..-4095 for errors precisely so this works) would be
 * misinterpreted, which is the same trade glibc makes.
 */
extern long __pxx_syscall(long num, long a1, long a2, long a3,
                          long a4, long a5, long a6);

long syscall(long number, ...) {
  va_list ap;
  long a[6];
  int i;
  long rc;

  va_start(ap, number);
  for (i = 0; i < 6; i++) a[i] = va_arg(ap, long);
  va_end(ap);

  rc = __pxx_syscall(number, a[0], a[1], a[2], a[3], a[4], a[5]);
  if (rc < 0 && rc > -4096) { errno = (int)-rc; return -1; }
  return rc;
}

/* ---- acct / pause / nice -------------------------------------------------
 * All three found attempting busybox at 394 applets
 * (feature-b-crtl-function-gaps-at-394-busybox-applets).
 */

/* acct(2). NULL turns accounting OFF -- it is not a missing argument, and a
 * defensive `if (!filename) return -1;' here would break bootchartd.c:274,
 * which is the only way it ever stops accounting. */
int acct(const char *filename)
{
#ifdef SYS_acct
  return (int)syscall(SYS_acct, (long)filename);
#else
  (void)filename;
  errno = ENOSYS;
  return -1;
#endif
}

/* pause(2). THERE IS NO SUCCESS RETURN: it returns only when a handled signal
 * arrives, and then it is always -1/EINTR.
 *
 * aarch64 and riscv HAVE NO SYS_pause -- the kernel dropped it from the
 * generic syscall table -- so this is not a target where ENOSYS would be
 * acceptable: mpstat would stop working on two live targets. glibc's answer is
 * ppoll with no descriptors and no timeout, which blocks until a signal, and
 * both targets have SYS_ppoll. The fallback is that call, not a refusal, and
 * the ordering matters: prefer the real syscall where it exists so the strace
 * of an x86-64 run says `pause' rather than something that merely behaves like
 * it. */
int pause(void)
{
#if defined(SYS_pause)
  return (int)syscall(SYS_pause);
#elif defined(SYS_ppoll)
  return (int)syscall(SYS_ppoll, (long)0, (long)0, (long)0, (long)0);
#else
  errno = ENOSYS;
  return -1;
#endif
}

/* nice(2), over getpriority/setpriority because Linux has no nice syscall on
 * any target pxx builds for.
 *
 * -1 IS A LEGAL RETURN. Callers must clear errno first and test it after, and
 * busybox runit/chpst.c:468 does exactly that -- so this must not use -1 as
 * its own private failure marker for anything getpriority can legitimately
 * answer.
 *
 * DELIBERATE DIVERGENCE FROM GLIBC, and it is the accurate direction: glibc
 * returns `old + inc' WITHOUT re-reading, so nice(100) reports 119 while the
 * process is actually at 19, because the kernel clamped and glibc did not
 * look. POSIX says nice() returns the new nice value. This re-reads and
 * returns what the process ACTUALLY has. The two agree for every increment
 * that does not hit a clamp, which is every call in the corpus; they disagree
 * only where glibc's answer is untrue.
 */
int nice(int inc)
{
  int old, got;
  errno = 0;
  old = getpriority(PRIO_PROCESS, 0);
  if (old == -1 && errno != 0) return -1;
  if (setpriority(PRIO_PROCESS, 0, old + inc) == -1) {
    /* setpriority reports a refused decrease as EACCES; nice(2) documents
       EPERM for it, and a caller printing strerror(errno) should say
       "Operation not permitted" rather than "Permission denied". */
    if (errno == EACCES) errno = EPERM;
    return -1;
  }
  errno = 0;
  got = getpriority(PRIO_PROCESS, 0);
  if (got == -1 && errno != 0) return -1;
  return got;
}
