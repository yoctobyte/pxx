/* Headers crtl lacked that Nodisx recipes include (found building on a
   target with no host headers): <ulimit.h> (mksh), <sys/timeb.h> (GNU make),
   <linux/landlock.h> (xz's sandbox), <values.h> (mksh), <ar.h> (GNU make). Layouts, constants, and the calls
   behind them, compared with gcc. feature-crtl-the-headers-a-hostless-target-lacks */
#include <stdio.h>
#include <stddef.h>
#include <errno.h>
#include <time.h>
#include <unistd.h>
#include <sys/wait.h>
#include <sys/syscall.h>
#include <sys/prctl.h>
#include <sys/resource.h>
#include <ulimit.h>
#include <sys/timeb.h>
#include <linux/landlock.h>
#include <values.h>
#include <ar.h>

int main(void) {
  struct timeb tb;
  time_t before = time(NULL);
  long lim;
  int abi, st;
  pid_t pid;

  printf("timeb %d %d %d %d\n", (int)sizeof(struct timeb), (int)offsetof(struct timeb, millitm),
         (int)offsetof(struct timeb, timezone), (int)offsetof(struct timeb, dstflag));
  printf("ftime %d", ftime(&tb));
  printf(" sane %d %d\n", tb.time >= before && tb.time <= time(NULL), tb.millitm < 1000);

  printf("values %d %d %d %d %ld %d %d %g\n", BITSPERBYTE, (int)SHORTBITS, (int)INTBITS, (int)LONGBITS,
         MAXLONG, HIBITS, DMAXEXP, (double)MAXFLOAT);
  printf("ar %s|%d %d %d %d %d %d\n", ARMAG, SARMAG, (int)sizeof(struct ar_hdr), (int)offsetof(struct ar_hdr, ar_date),
         (int)offsetof(struct ar_hdr, ar_mode), (int)offsetof(struct ar_hdr, ar_size), (int)offsetof(struct ar_hdr, ar_fmag));
  printf("ulimit cmds %d %d\n", UL_GETFSIZE, UL_SETFSIZE);
  lim = ulimit(UL_GETFSIZE);
  printf("ulimit get %s\n", lim > 0 ? "positive" : "not");
  fflush(stdout);
  pid = fork();   /* lowering a limit is one-way: in a child */
  if (pid == 0) {
    long r = ulimit(UL_SETFSIZE, 2048L);
    struct rlimit rl;
    getrlimit(RLIMIT_FSIZE, &rl);
    printf("ulimit set %ld get %ld rlimit %lld %lld\n", r, ulimit(UL_GETFSIZE),
           (long long)rl.rlim_cur, (long long)rl.rlim_max);
    errno = 0;
    r = ulimit(99);
    printf("ulimit bad %ld %d\n", r, errno == EINVAL);
    fflush(stdout);
    _exit(0);
  }
  waitpid(pid, &st, 0);

  printf("landlock sizes %d %d %d\n", (int)sizeof(struct landlock_ruleset_attr),
         (int)sizeof(struct landlock_path_beneath_attr), (int)sizeof(struct landlock_net_port_attr));
  printf("landlock offs %d %d\n", (int)offsetof(struct landlock_ruleset_attr, scoped),
         (int)offsetof(struct landlock_path_beneath_attr, parent_fd));
  printf("landlock bits %llx %llx %llx %u %d %d\n",
         (unsigned long long)LANDLOCK_ACCESS_FS_IOCTL_DEV, (unsigned long long)LANDLOCK_ACCESS_NET_CONNECT_TCP,
         (unsigned long long)LANDLOCK_SCOPE_SIGNAL, LANDLOCK_CREATE_RULESET_VERSION,
         LANDLOCK_RULE_PATH_BENEATH, LANDLOCK_RULE_NET_PORT);
  abi = (int)syscall(SYS_landlock_create_ruleset, (void *)0, 0, LANDLOCK_CREATE_RULESET_VERSION);
  printf("landlock abi %s\n", abi >= 1 ? "available" : "unavailable");
  if (abi >= 1) {
    /* sandbox a child the way xz does: no writes anywhere, then try one */
    fflush(stdout);
    pid = fork();
    if (pid == 0) {
      struct landlock_ruleset_attr attr = { LANDLOCK_ACCESS_FS_WRITE_FILE | LANDLOCK_ACCESS_FS_MAKE_REG, 0, 0 };
      int fd = (int)syscall(SYS_landlock_create_ruleset, &attr, sizeof attr.handled_access_fs * (abi >= 4 ? 2 : 1), 0);
      int ok = fd >= 0 && prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) == 0 &&
               syscall(SYS_landlock_restrict_self, fd, 0) == 0;
      FILE *f = fopen("/tmp/c_nohost_headers.landlock", "w");
      printf("landlock restrict %d write-refused %d\n", ok, f == NULL);
      fflush(stdout);
      _exit(0);
    }
    waitpid(pid, &st, 0);
  }
  return 0;
}
