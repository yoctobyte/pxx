/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: posix_spawn / posix_spawnp and their attribute and file-action
 * objects.
 *
 * FORK, NOT VFORK. The child runs the file actions and the signal set-up in
 * C, and crtl's vfork shares the parent's stack, so each of those calls
 * would overwrite the parent's frames. fork costs a page-table copy. A
 * small daemon (dhcpcd runs its hook script this way) cannot tell.
 *
 * ERRORS REACH THE PARENT, as POSIX asks of posix_spawn: "no such file" is a
 * return value, not a child that exits 127. The child holds the write end of
 * a close-on-exec pipe. A successful exec closes it, so the parent's read
 * sees EOF. A failure writes errno into it first, then the child _exits 127.
 * The parent reaps that child, so no zombie is left behind.
 *
 * ALL SIGNALS ARE BLOCKED ACROSS THE FORK, so a handler of the parent's never
 * runs in the child before the exec replaces it. The child then sets the
 * mask the attributes ask for, or the parent's own mask.
 */
#include <spawn.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <sys/wait.h>

extern char **environ;

enum { SA_OPEN = 1, SA_CLOSE, SA_DUP2, SA_CHDIR, SA_FCHDIR };

struct __crtl_spawn_action {
  int kind;
  int fd;
  int newfd;      /* dup2's target */
  int oflag;
  mode_t mode;
  char *path;     /* open, chdir: owned copy */
};

/* ---- attributes ---- */

int posix_spawnattr_init(posix_spawnattr_t *attr)
{
  memset(attr, 0, sizeof *attr);
  sigemptyset(&attr->__sd);
  sigemptyset(&attr->__ss);
  return 0;
}

int posix_spawnattr_destroy(posix_spawnattr_t *attr) { (void)attr; return 0; }

int posix_spawnattr_getflags(const posix_spawnattr_t *attr, short *flags)
{
  *flags = attr->__flags;
  return 0;
}

int posix_spawnattr_setflags(posix_spawnattr_t *attr, short flags)
{
  if (flags & ~(POSIX_SPAWN_RESETIDS | POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF |
                POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSCHEDPARAM |
                POSIX_SPAWN_SETSCHEDULER | POSIX_SPAWN_USEVFORK | POSIX_SPAWN_SETSID))
    return EINVAL;
  attr->__flags = flags;
  return 0;
}

int posix_spawnattr_getpgroup(const posix_spawnattr_t *attr, pid_t *pgroup)
{
  *pgroup = attr->__pgrp;
  return 0;
}

int posix_spawnattr_setpgroup(posix_spawnattr_t *attr, pid_t pgroup)
{
  attr->__pgrp = pgroup;
  return 0;
}

int posix_spawnattr_getsigdefault(const posix_spawnattr_t *attr, sigset_t *sigdefault)
{
  *sigdefault = attr->__sd;
  return 0;
}

int posix_spawnattr_setsigdefault(posix_spawnattr_t *attr, const sigset_t *sigdefault)
{
  attr->__sd = *sigdefault;
  return 0;
}

int posix_spawnattr_getsigmask(const posix_spawnattr_t *attr, sigset_t *sigmask)
{
  *sigmask = attr->__ss;
  return 0;
}

int posix_spawnattr_setsigmask(posix_spawnattr_t *attr, const sigset_t *sigmask)
{
  attr->__ss = *sigmask;
  return 0;
}

int posix_spawnattr_getschedpolicy(const posix_spawnattr_t *attr, int *policy)
{
  *policy = attr->__policy;
  return 0;
}

int posix_spawnattr_setschedpolicy(posix_spawnattr_t *attr, int policy)
{
  attr->__policy = policy;
  return 0;
}

/* ---- file actions ---- */

int posix_spawn_file_actions_init(posix_spawn_file_actions_t *fa)
{
  memset(fa, 0, sizeof *fa);
  return 0;
}

int posix_spawn_file_actions_destroy(posix_spawn_file_actions_t *fa)
{
  int i;
  for (i = 0; i < fa->__used; i++) free(fa->__actions[i].path);
  free(fa->__actions);
  memset(fa, 0, sizeof *fa);
  return 0;
}

static struct __crtl_spawn_action *spawn_add(posix_spawn_file_actions_t *fa)
{
  struct __crtl_spawn_action *a;
  if (fa->__used == fa->__allocated) {
    int n = fa->__allocated ? fa->__allocated * 2 : 4;
    a = realloc(fa->__actions, (size_t)n * sizeof *a);
    if (!a) return NULL;
    fa->__actions = a;
    fa->__allocated = n;
  }
  a = &fa->__actions[fa->__used++];
  memset(a, 0, sizeof *a);
  return a;
}

int posix_spawn_file_actions_addopen(posix_spawn_file_actions_t *fa, int fd,
                                     const char *path, int oflag, mode_t mode)
{
  struct __crtl_spawn_action *a;
  char *p;
  if (fd < 0) return EBADF;
  p = strdup(path);
  if (!p) return ENOMEM;
  a = spawn_add(fa);
  if (!a) { free(p); return ENOMEM; }
  a->kind = SA_OPEN; a->fd = fd; a->path = p; a->oflag = oflag; a->mode = mode;
  return 0;
}

int posix_spawn_file_actions_addclose(posix_spawn_file_actions_t *fa, int fd)
{
  struct __crtl_spawn_action *a;
  if (fd < 0) return EBADF;
  a = spawn_add(fa);
  if (!a) return ENOMEM;
  a->kind = SA_CLOSE; a->fd = fd;
  return 0;
}

int posix_spawn_file_actions_adddup2(posix_spawn_file_actions_t *fa, int fd, int newfd)
{
  struct __crtl_spawn_action *a;
  if (fd < 0 || newfd < 0) return EBADF;
  a = spawn_add(fa);
  if (!a) return ENOMEM;
  a->kind = SA_DUP2; a->fd = fd; a->newfd = newfd;
  return 0;
}

int posix_spawn_file_actions_addchdir_np(posix_spawn_file_actions_t *fa, const char *path)
{
  struct __crtl_spawn_action *a;
  char *p = strdup(path);
  if (!p) return ENOMEM;
  a = spawn_add(fa);
  if (!a) { free(p); return ENOMEM; }
  a->kind = SA_CHDIR; a->path = p;
  return 0;
}

int posix_spawn_file_actions_addfchdir_np(posix_spawn_file_actions_t *fa, int fd)
{
  struct __crtl_spawn_action *a;
  if (fd < 0) return EBADF;
  a = spawn_add(fa);
  if (!a) return ENOMEM;
  a->kind = SA_FCHDIR; a->fd = fd;
  return 0;
}

/* ---- the spawn ---- */

/* the child: never returns. err is the pipe's write end. */
static void spawn_child(int err, int usepath, const char *file,
                        const posix_spawn_file_actions_t *fa,
                        const posix_spawnattr_t *attr, const sigset_t *oldmask,
                        char *const argv[], char *const envp[])
{
  int i, e;
  short flags = attr ? attr->__flags : 0;

  if (flags & POSIX_SPAWN_SETSIGDEF) {
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = SIG_DFL;
    for (i = 1; i < NSIG; i++)
      if (sigismember(&attr->__sd, i) == 1) sigaction(i, &sa, NULL);
  }
  if ((flags & POSIX_SPAWN_SETSID) && setsid() < 0) goto fail;
  if ((flags & POSIX_SPAWN_SETPGROUP) && setpgid(0, attr->__pgrp) < 0) goto fail;
  if (flags & POSIX_SPAWN_RESETIDS) {
    if (setgid(getgid()) < 0 || setuid(getuid()) < 0) goto fail;
  }
  if (fa) {
    for (i = 0; i < fa->__used; i++) {
      const struct __crtl_spawn_action *a = &fa->__actions[i];
      int fd;
      switch (a->kind) {
      case SA_OPEN:
        fd = open(a->path, a->oflag, a->mode);
        if (fd < 0) goto fail;
        if (fd != a->fd) {
          if (dup2(fd, a->fd) < 0) goto fail;
          close(fd);
        }
        break;
      case SA_CLOSE:
        close(a->fd);          /* closing a closed slot is not an error here */
        break;
      case SA_DUP2:
        if (a->fd == a->newfd) {
          /* POSIX: dup2 onto itself clears close-on-exec */
          int fl = fcntl(a->fd, F_GETFD);
          if (fl < 0 || fcntl(a->fd, F_SETFD, fl & ~FD_CLOEXEC) < 0) goto fail;
        } else if (dup2(a->fd, a->newfd) < 0) goto fail;
        break;
      case SA_CHDIR:
        if (chdir(a->path) < 0) goto fail;
        break;
      case SA_FCHDIR:
        if (fchdir(a->fd) < 0) goto fail;
        break;
      }
    }
  }
  sigprocmask(SIG_SETMASK, (flags & POSIX_SPAWN_SETSIGMASK) ? &attr->__ss : oldmask, NULL);

  if (!usepath || strchr(file, '/')) {
    execve(file, argv, envp);
  } else {
    /* posix_spawnp: PATH as execvp searches it; EACCES from any candidate is
       reported if nothing ran, else the last error */
    const char *path = getenv("PATH"), *p, *q;
    char buf[4096];
    int sawEacces = 0;
    size_t fl = strlen(file), dl;
    if (!path || !*path) path = "/bin:/usr/bin";
    for (p = path; ; p = q + 1) {
      q = strchr(p, ':');
      if (!q) q = p + strlen(p);
      dl = (size_t)(q - p);
      if (dl + 1 + fl + 1 <= sizeof buf) {
        if (dl == 0) { memcpy(buf, file, fl + 1); }
        else {
          memcpy(buf, p, dl);
          buf[dl] = '/';
          memcpy(buf + dl + 1, file, fl + 1);
        }
        execve(buf, argv, envp);
        if (errno == EACCES) sawEacces = 1;
        else if (errno != ENOENT && errno != ENOTDIR) break;
      }
      if (*q == '\0') break;
    }
    if (sawEacces) errno = EACCES;
  }
fail:
  e = errno;
  while (write(err, &e, sizeof e) < 0 && errno == EINTR)
    ;
  _exit(127);
}

static int spawn_common(pid_t *pidp, int usepath, const char *file,
                        const posix_spawn_file_actions_t *fa,
                        const posix_spawnattr_t *attr,
                        char *const argv[], char *const envp[])
{
  int p[2], e, st;
  ssize_t n;
  pid_t pid;
  sigset_t all, old;

  if (!envp) envp = environ;
  if (pipe(p) < 0) return errno;
  if (fcntl(p[0], F_SETFD, FD_CLOEXEC) < 0 || fcntl(p[1], F_SETFD, FD_CLOEXEC) < 0) {
    e = errno;
    close(p[0]); close(p[1]);
    return e;
  }
  sigfillset(&all);
  sigprocmask(SIG_BLOCK, &all, &old);
  pid = fork();
  if (pid == 0) {
    close(p[0]);
    spawn_child(p[1], usepath, file, fa, attr, &old, argv, envp);
  }
  e = errno;
  sigprocmask(SIG_SETMASK, &old, NULL);
  close(p[1]);
  if (pid < 0) {
    close(p[0]);
    return e;
  }
  do n = read(p[0], &e, sizeof e); while (n < 0 && errno == EINTR);
  close(p[0]);
  if (n == (ssize_t)sizeof e) {
    /* the child failed before or at exec: reap it, report its errno */
    while (waitpid(pid, &st, 0) < 0 && errno == EINTR)
      ;
    return e;
  }
  if (pidp) *pidp = pid;
  return 0;
}

int posix_spawn(pid_t *pid, const char *path,
                const posix_spawn_file_actions_t *file_actions,
                const posix_spawnattr_t *attrp,
                char *const argv[], char *const envp[])
{
  return spawn_common(pid, 0, path, file_actions, attrp, argv, envp);
}

int posix_spawnp(pid_t *pid, const char *file,
                 const posix_spawn_file_actions_t *file_actions,
                 const posix_spawnattr_t *attrp,
                 char *const argv[], char *const envp[])
{
  return spawn_common(pid, 1, file, file_actions, attrp, argv, envp);
}
