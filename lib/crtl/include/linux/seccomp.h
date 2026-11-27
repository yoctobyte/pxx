/* SPDX-License-Identifier: Zlib */
/* <linux/seccomp.h>: the seccomp(2) / PR_SET_SECCOMP interface, the kernel's
   values (include/uapi/linux/seccomp.h). Not included here: user notification
   (SECCOMP_RET_USER_NOTIF's ioctls), which the Rainyday kernel does not
   implement. dhcpcd privsep installs its BPF filter through this header.
   feature-nodisx-dhcpcd-with-privilege-separation */
#ifndef _LINUX_SECCOMP_H
#define _LINUX_SECCOMP_H
#include <stdint.h>

#define SECCOMP_MODE_DISABLED   0
#define SECCOMP_MODE_STRICT     1
#define SECCOMP_MODE_FILTER     2

#define SECCOMP_SET_MODE_STRICT   0
#define SECCOMP_SET_MODE_FILTER   1
#define SECCOMP_GET_ACTION_AVAIL  2

#define SECCOMP_FILTER_FLAG_TSYNC        (1UL << 0)
#define SECCOMP_FILTER_FLAG_LOG          (1UL << 1)
#define SECCOMP_FILTER_FLAG_SPEC_ALLOW   (1UL << 2)
#define SECCOMP_FILTER_FLAG_TSYNC_ESRCH  (1UL << 4)

#define SECCOMP_RET_KILL_PROCESS 0x80000000U
#define SECCOMP_RET_KILL_THREAD  0x00000000U
#define SECCOMP_RET_KILL         SECCOMP_RET_KILL_THREAD
#define SECCOMP_RET_TRAP         0x00030000U
#define SECCOMP_RET_ERRNO        0x00050000U
#define SECCOMP_RET_TRACE        0x7ff00000U
#define SECCOMP_RET_LOG          0x7ffc0000U
#define SECCOMP_RET_ALLOW        0x7fff0000U

#define SECCOMP_RET_ACTION_FULL  0xffff0000U
#define SECCOMP_RET_ACTION       0x7fff0000U
#define SECCOMP_RET_DATA         0x0000ffffU

struct seccomp_data {
  int nr;
  uint32_t arch;
  uint64_t instruction_pointer;
  uint64_t args[6];
};
#endif
