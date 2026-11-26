/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <spawn.h>, POSIX posix_spawn. Built on fork + execve (see
 * src/spawn.c): an error from exec, or from a file action, reaches the parent
 * as posix_spawn's return value, as POSIX asks, through a close-on-exec pipe.
 * dhcpcd runs its hook script with it.
 *
 * Supported attributes: SETSIGMASK, SETSIGDEF, SETPGROUP, SETSID, RESETIDS.
 * SETSCHEDULER/SETSCHEDPARAM are accepted and ignored (no scheduler
 * policy in crtl). File actions: open, close, dup2, chdir, fchdir.
 */
#ifndef _CRTL_SPAWN_H
#define _CRTL_SPAWN_H
#include <sys/types.h>
#include <signal.h>
#include <sched.h>

#define POSIX_SPAWN_RESETIDS      0x01
#define POSIX_SPAWN_SETPGROUP     0x02
#define POSIX_SPAWN_SETSIGDEF     0x04
#define POSIX_SPAWN_SETSIGMASK    0x08
#define POSIX_SPAWN_SETSCHEDPARAM 0x10
#define POSIX_SPAWN_SETSCHEDULER  0x20
#define POSIX_SPAWN_USEVFORK      0x40
#define POSIX_SPAWN_SETSID        0x80

typedef struct {
  short __flags;
  pid_t __pgrp;
  sigset_t __sd;     /* signals reset to SIG_DFL */
  sigset_t __ss;     /* the child's signal mask */
  int __policy;
  int __prio;
} posix_spawnattr_t;

struct __crtl_spawn_action;
typedef struct {
  int __used;
  int __allocated;
  struct __crtl_spawn_action *__actions;
} posix_spawn_file_actions_t;

int posix_spawn(pid_t *pid, const char *path,
                const posix_spawn_file_actions_t *file_actions,
                const posix_spawnattr_t *attrp,
                char *const argv[], char *const envp[]);
int posix_spawnp(pid_t *pid, const char *file,
                 const posix_spawn_file_actions_t *file_actions,
                 const posix_spawnattr_t *attrp,
                 char *const argv[], char *const envp[]);

int posix_spawnattr_init(posix_spawnattr_t *attr);
int posix_spawnattr_destroy(posix_spawnattr_t *attr);
int posix_spawnattr_getflags(const posix_spawnattr_t *attr, short *flags);
int posix_spawnattr_setflags(posix_spawnattr_t *attr, short flags);
int posix_spawnattr_getpgroup(const posix_spawnattr_t *attr, pid_t *pgroup);
int posix_spawnattr_setpgroup(posix_spawnattr_t *attr, pid_t pgroup);
int posix_spawnattr_getsigdefault(const posix_spawnattr_t *attr, sigset_t *sigdefault);
int posix_spawnattr_setsigdefault(posix_spawnattr_t *attr, const sigset_t *sigdefault);
int posix_spawnattr_getsigmask(const posix_spawnattr_t *attr, sigset_t *sigmask);
int posix_spawnattr_setsigmask(posix_spawnattr_t *attr, const sigset_t *sigmask);
int posix_spawnattr_getschedpolicy(const posix_spawnattr_t *attr, int *policy);
int posix_spawnattr_setschedpolicy(posix_spawnattr_t *attr, int policy);

int posix_spawn_file_actions_init(posix_spawn_file_actions_t *fa);
int posix_spawn_file_actions_destroy(posix_spawn_file_actions_t *fa);
int posix_spawn_file_actions_addopen(posix_spawn_file_actions_t *fa, int fd,
                                     const char *path, int oflag, mode_t mode);
int posix_spawn_file_actions_addclose(posix_spawn_file_actions_t *fa, int fd);
int posix_spawn_file_actions_adddup2(posix_spawn_file_actions_t *fa, int fd, int newfd);
int posix_spawn_file_actions_addchdir_np(posix_spawn_file_actions_t *fa, const char *path);
int posix_spawn_file_actions_addfchdir_np(posix_spawn_file_actions_t *fa, int fd);

#endif
