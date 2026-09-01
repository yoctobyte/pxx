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
   of this comment got it wrong. *** chroot, setuid/setgid/seteuid/setegid and
   setgroups have no PAL entry: those really are missing syscalls. `fork` is a
   different case and the distinction matters: the PAL has PalVfork, and vfork
   is NOT fork — the child shares the parent's memory and may do nothing but
   exec or _exit — so wiring fork to it would be a silent corruption, not a
   convenience. vfork() below is being given its real implementation over
   PalVfork separately; fork() stays unavailable until there is a fork.

   The general lesson, already recorded in <sys/ioctl.h> for the same mistake:
   MEASURE the PAL before believing a line that says an entry is missing. */
int chroot(const char *path)   { (void)path; errno = ENOSYS; return -1; }
int fork(void)                 { errno = ENOSYS; return -1; }
int vfork(void)                { errno = ENOSYS; return -1; }
int setuid(uid_t uid)          { (void)uid; errno = ENOSYS; return -1; }
int setgid(gid_t gid)          { (void)gid; errno = ENOSYS; return -1; }
int seteuid(uid_t uid)         { (void)uid; errno = ENOSYS; return -1; }
int setegid(gid_t gid)         { (void)gid; errno = ENOSYS; return -1; }
int setgroups(size_t n, const gid_t *list) { (void)n; (void)list; errno = ENOSYS; return -1; }


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

   NOT implemented: getopt_long, and the leading `+` / `-` optstring modes. A
   leading ':' IS honoured -- it costs one branch and callers use it to tell a
   missing argument from an unknown option.

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

int getopt(int argc, char *const argv[], const char *optstring)
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
