/* <sys/signalfd.h>: the record's layout (against gcc + glibc's header) and a
   real round trip -- block SIGUSR1, raise it, read it from the signalfd.
   libsystemd's sd-event.h includes this header (Panorama's bus helper).
   feature-crtl-sys-signalfd-h */
#include <stdio.h>
#include <stddef.h>
#include <signal.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/signalfd.h>

int main(void) {
  printf("size %d signo %d pid %d uid %d int %d ptr %d addr %d lsb %d syscall %d call %d arch %d\n",
         (int)sizeof(struct signalfd_siginfo),
         (int)offsetof(struct signalfd_siginfo, ssi_signo),
         (int)offsetof(struct signalfd_siginfo, ssi_pid),
         (int)offsetof(struct signalfd_siginfo, ssi_uid),
         (int)offsetof(struct signalfd_siginfo, ssi_int),
         (int)offsetof(struct signalfd_siginfo, ssi_ptr),
         (int)offsetof(struct signalfd_siginfo, ssi_addr),
         (int)offsetof(struct signalfd_siginfo, ssi_addr_lsb),
         (int)offsetof(struct signalfd_siginfo, ssi_syscall),
         (int)offsetof(struct signalfd_siginfo, ssi_call_addr),
         (int)offsetof(struct signalfd_siginfo, ssi_arch));
  printf("flags %d %d\n", SFD_CLOEXEC == O_CLOEXEC, SFD_NONBLOCK == O_NONBLOCK);

  sigset_t m;
  sigemptyset(&m);
  sigaddset(&m, SIGUSR1);
  if (sigprocmask(SIG_BLOCK, &m, NULL) != 0) { printf("sigprocmask failed\n"); return 1; }
  int fd = signalfd(-1, &m, SFD_CLOEXEC | SFD_NONBLOCK);
  if (fd < 0) { printf("signalfd failed\n"); return 1; }
  printf("cloexec %d nonblock %d\n", (fcntl(fd, F_GETFD) & FD_CLOEXEC) != 0,
         (fcntl(fd, F_GETFL) & O_NONBLOCK) != 0);
  struct signalfd_siginfo si;
  printf("empty read %d\n", (int)read(fd, &si, sizeof si));
  kill(getpid(), SIGUSR1);
  ssize_t n = read(fd, &si, sizeof si);
  printf("read %d signo-is-usr1 %d pid-is-mine %d uid-is-mine %d\n", (int)n,
         si.ssi_signo == SIGUSR1, si.ssi_pid == (unsigned)getpid(),
         si.ssi_uid == (unsigned)getuid());
  close(fd);
  return 0;
}
