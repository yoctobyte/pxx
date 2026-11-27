/* SPDX-License-Identifier: Zlib */
/* The seccomp UAPI that dhcpcd's privilege separation uses (privsep-linux.c):
   <linux/seccomp.h>, <linux/audit.h>'s AUDIT_ARCH_* (from <linux/elf-em.h>)
   and <linux/net.h>'s socketcall numbers, compared against GCC'S VIEW OF
   THE SAME SOURCE, the shape of c_crtl_uapi_constants.c: no expected value
   is written down, and the two sides are compiled from different header
   trees. A filter that names the wrong arch or reads seccomp_data at the
   wrong offset kills its own process at the first syscall, or lets through
   what it meant to stop.
   Then a filter of dhcpcd's shape is installed for real (arch check, then
   one syscall answered with an errno, everything else allowed): uname()
   must fail with EPERM and the rest go on. At both widths, so the i386 arch
   and syscall numbers are the ones checked there. */
#define _GNU_SOURCE 1
#include <stdio.h>
#include <stddef.h>
#include <errno.h>
#include <unistd.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/utsname.h>
#include <linux/ioctl.h>   /* the kernel seccomp.h spells its ioctls with _IOWR and leaves it to the includer */
#include <linux/audit.h>
#include <linux/filter.h>
#include <linux/net.h>
#include <linux/seccomp.h>

#define P(x) printf("%-34s %lu\n", #x, (unsigned long)(x))
#define O(s, f) printf("%-34s %ld\n", "offsetof(" #s ", " #f ")", (long)offsetof(s, f))

#if defined(__x86_64__)
#define MY_ARCH AUDIT_ARCH_X86_64
#elif defined(__i386__)
#define MY_ARCH AUDIT_ARCH_I386
#endif

int main(void)
{
  P(SECCOMP_MODE_DISABLED); P(SECCOMP_MODE_STRICT); P(SECCOMP_MODE_FILTER);
  P(SECCOMP_SET_MODE_STRICT); P(SECCOMP_SET_MODE_FILTER); P(SECCOMP_GET_ACTION_AVAIL);
  P(SECCOMP_GET_NOTIF_SIZES);
  P(SECCOMP_FILTER_FLAG_TSYNC); P(SECCOMP_FILTER_FLAG_LOG); P(SECCOMP_FILTER_FLAG_SPEC_ALLOW);
  P(SECCOMP_FILTER_FLAG_NEW_LISTENER); P(SECCOMP_FILTER_FLAG_TSYNC_ESRCH);
  P(SECCOMP_FILTER_FLAG_WAIT_KILLABLE_RECV);
  P(SECCOMP_RET_KILL_PROCESS); P(SECCOMP_RET_KILL_THREAD); P(SECCOMP_RET_KILL);
  P(SECCOMP_RET_TRAP); P(SECCOMP_RET_ERRNO); P(SECCOMP_RET_USER_NOTIF); P(SECCOMP_RET_TRACE);
  P(SECCOMP_RET_LOG); P(SECCOMP_RET_ALLOW); P(SECCOMP_RET_ACTION_FULL); P(SECCOMP_RET_ACTION);
  P(SECCOMP_RET_DATA); P(SECCOMP_USER_NOTIF_FLAG_CONTINUE); P(SECCOMP_USER_NOTIF_FD_SYNC_WAKE_UP);
  P(SECCOMP_ADDFD_FLAG_SETFD); P(SECCOMP_ADDFD_FLAG_SEND);
  P(SECCOMP_IOCTL_NOTIF_RECV); P(SECCOMP_IOCTL_NOTIF_SEND); P(SECCOMP_IOCTL_NOTIF_ID_VALID);
  P(SECCOMP_IOCTL_NOTIF_ADDFD); P(SECCOMP_IOCTL_NOTIF_SET_FLAGS);
  P(sizeof(struct seccomp_data));
  O(struct seccomp_data, nr); O(struct seccomp_data, arch);
  O(struct seccomp_data, instruction_pointer); O(struct seccomp_data, args);
  P(sizeof(struct seccomp_notif_sizes)); P(sizeof(struct seccomp_notif));
  O(struct seccomp_notif, pid); O(struct seccomp_notif, data);
  P(sizeof(struct seccomp_notif_resp)); O(struct seccomp_notif_resp, val);
  O(struct seccomp_notif_resp, error); P(sizeof(struct seccomp_notif_addfd));
  O(struct seccomp_notif_addfd, newfd_flags);

  P(AUDIT_ARCH); P(__AUDIT_ARCH_64BIT); P(__AUDIT_ARCH_LE); P(__AUDIT_ARCH_CONVENTION_MASK);
  P(AUDIT_ARCH_AARCH64); P(AUDIT_ARCH_ALPHA); P(AUDIT_ARCH_ARCOMPACT); P(AUDIT_ARCH_ARCOMPACTBE);
  P(AUDIT_ARCH_ARCV2); P(AUDIT_ARCH_ARCV2BE); P(AUDIT_ARCH_ARM); P(AUDIT_ARCH_ARMEB);
  P(AUDIT_ARCH_C6X); P(AUDIT_ARCH_CRIS); P(AUDIT_ARCH_CSKY); P(AUDIT_ARCH_FRV);
  P(AUDIT_ARCH_H8300); P(AUDIT_ARCH_HEXAGON); P(AUDIT_ARCH_I386); P(AUDIT_ARCH_IA64);
  P(AUDIT_ARCH_M32R); P(AUDIT_ARCH_M68K); P(AUDIT_ARCH_MICROBLAZE); P(AUDIT_ARCH_MIPS);
  P(AUDIT_ARCH_MIPSEL); P(AUDIT_ARCH_MIPS64); P(AUDIT_ARCH_MIPS64N32); P(AUDIT_ARCH_MIPSEL64);
  P(AUDIT_ARCH_MIPSEL64N32); P(AUDIT_ARCH_NDS32); P(AUDIT_ARCH_NIOS2); P(AUDIT_ARCH_OPENRISC);
  P(AUDIT_ARCH_PARISC); P(AUDIT_ARCH_PARISC64); P(AUDIT_ARCH_PPC); P(AUDIT_ARCH_PPC64);
  P(AUDIT_ARCH_PPC64LE); P(AUDIT_ARCH_RISCV32); P(AUDIT_ARCH_RISCV64); P(AUDIT_ARCH_S390);
  P(AUDIT_ARCH_S390X); P(AUDIT_ARCH_SH); P(AUDIT_ARCH_SHEL); P(AUDIT_ARCH_SH64);
  P(AUDIT_ARCH_SHEL64); P(AUDIT_ARCH_SPARC); P(AUDIT_ARCH_SPARC64); P(AUDIT_ARCH_TILEGX);
  P(AUDIT_ARCH_TILEPRO); P(AUDIT_ARCH_UNICORE); P(AUDIT_ARCH_X86_64); P(AUDIT_ARCH_XTENSA);
  P(AUDIT_ARCH_LOONGARCH32); P(AUDIT_ARCH_LOONGARCH64);
  P(EM_BPF); P(EM_S390_OLD); P(EM_CYGNUS_MN10300);

  P(SYS_SOCKET); P(SYS_BIND); P(SYS_CONNECT); P(SYS_LISTEN); P(SYS_ACCEPT); P(SYS_GETSOCKNAME);
  P(SYS_GETPEERNAME); P(SYS_SOCKETPAIR); P(SYS_SEND); P(SYS_RECV); P(SYS_SENDTO);
  P(SYS_RECVFROM); P(SYS_SHUTDOWN); P(SYS_SETSOCKOPT); P(SYS_GETSOCKOPT); P(SYS_SENDMSG);
  P(SYS_RECVMSG); P(SYS_ACCEPT4); P(SYS_RECVMMSG); P(SYS_SENDMMSG);
  P(SS_FREE); P(SS_UNCONNECTED); P(SS_CONNECTING); P(SS_CONNECTED); P(SS_DISCONNECTING);
  P(__SO_ACCEPTCON); P(sizeof(socket_state));

  /* a live filter, dhcpcd's shape */
  struct sock_filter f[] = {
    BPF_STMT(BPF_LD + BPF_W + BPF_ABS, offsetof(struct seccomp_data, arch)),
    BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, MY_ARCH, 1, 0),
    BPF_STMT(BPF_RET + BPF_K, SECCOMP_RET_KILL),
    BPF_STMT(BPF_LD + BPF_W + BPF_ABS, offsetof(struct seccomp_data, nr)),
    BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, SYS_uname, 0, 1),
    BPF_STMT(BPF_RET + BPF_K, SECCOMP_RET_ERRNO | (EPERM & SECCOMP_RET_DATA)),
    BPF_STMT(BPF_RET + BPF_K, SECCOMP_RET_ALLOW),
  };
  struct sock_fprog prog = { (unsigned short)(sizeof f / sizeof f[0]), f };
  struct utsname u;
  int r;
  r = uname(&u);
  printf("uname before: %d\n", r);
  r = prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0);
  printf("no_new_privs: %d\n", r);
  r = prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &prog);
  printf("set seccomp: %d\n", r);
  r = prctl(PR_GET_SECCOMP, 0, 0, 0, 0);
  printf("get seccomp: %d\n", r);
  errno = 0;
  r = uname(&u);
  printf("uname after: %d errno %d\n", r, errno);
  r = prctl(PR_GET_NO_NEW_PRIVS, 0, 0, 0, 0);
  printf("get no_new_privs: %d\n", r);
  return 0;
}
