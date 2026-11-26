/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <linux/landlock.h>, the Landlock LSM's user ABI (kernel 5.13+):
 * the ruleset and rule structures that landlock_create_ruleset(2),
 * landlock_add_rule(2) and landlock_restrict_self(2) take, and their flag
 * bits. Written from the documented ABI (Documentation/userspace-api/
 * landlock.rst), not copied from the kernel's header. The syscall numbers are
 * <sys/syscall.h>'s (444..446); there are no libc wrappers, callers use
 * syscall(). xz's sandbox.c (ABI 1..4) is the user that found it missing.
 *
 * Layout matters: the kernel copies `size` bytes of the attribute struct and
 * refuses non-zero bytes it does not know, so a field must never be added
 * out of order. handled_access_net is ABI 4 (6.7), scoped ABI 6 (6.12).
 */
#ifndef _CRTL_LINUX_LANDLOCK_H
#define _CRTL_LINUX_LANDLOCK_H
#include <linux/types.h>

struct landlock_ruleset_attr {
  __u64 handled_access_fs;
  __u64 handled_access_net;
  __u64 scoped;
};

/* landlock_create_ruleset() flags */
#define LANDLOCK_CREATE_RULESET_VERSION (1U << 0)   /* return the highest ABI */
#define LANDLOCK_CREATE_RULESET_ERRATA  (1U << 1)   /* return the errata mask */

/* landlock_restrict_self() flags */
#define LANDLOCK_RESTRICT_SELF_LOG_SAME_EXEC_OFF  (1U << 0)
#define LANDLOCK_RESTRICT_SELF_LOG_NEW_EXEC_ON    (1U << 1)
#define LANDLOCK_RESTRICT_SELF_LOG_SUBDOMAINS_OFF (1U << 2)
#define LANDLOCK_RESTRICT_SELF_TSYNC              (1U << 3)

enum landlock_rule_type {
  LANDLOCK_RULE_PATH_BENEATH = 1,
  LANDLOCK_RULE_NET_PORT
};

/* packed in the ABI: 12 bytes, the fd straight after the access mask */
struct landlock_path_beneath_attr {
  __u64 allowed_access;
  __s32 parent_fd;
} __attribute__((packed));

struct landlock_net_port_attr {
  __u64 allowed_access;
  __u64 port;
};

/* filesystem rights; the ABI version that added each is in the comment */
#define LANDLOCK_ACCESS_FS_EXECUTE     (1ULL << 0)    /* 1 */
#define LANDLOCK_ACCESS_FS_WRITE_FILE  (1ULL << 1)    /* 1 */
#define LANDLOCK_ACCESS_FS_READ_FILE   (1ULL << 2)    /* 1 */
#define LANDLOCK_ACCESS_FS_READ_DIR    (1ULL << 3)    /* 1 */
#define LANDLOCK_ACCESS_FS_REMOVE_DIR  (1ULL << 4)    /* 1 */
#define LANDLOCK_ACCESS_FS_REMOVE_FILE (1ULL << 5)    /* 1 */
#define LANDLOCK_ACCESS_FS_MAKE_CHAR   (1ULL << 6)    /* 1 */
#define LANDLOCK_ACCESS_FS_MAKE_DIR    (1ULL << 7)    /* 1 */
#define LANDLOCK_ACCESS_FS_MAKE_REG    (1ULL << 8)    /* 1 */
#define LANDLOCK_ACCESS_FS_MAKE_SOCK   (1ULL << 9)    /* 1 */
#define LANDLOCK_ACCESS_FS_MAKE_FIFO   (1ULL << 10)   /* 1 */
#define LANDLOCK_ACCESS_FS_MAKE_BLOCK  (1ULL << 11)   /* 1 */
#define LANDLOCK_ACCESS_FS_MAKE_SYM    (1ULL << 12)   /* 1 */
#define LANDLOCK_ACCESS_FS_REFER       (1ULL << 13)   /* 2 */
#define LANDLOCK_ACCESS_FS_TRUNCATE    (1ULL << 14)   /* 3 */
#define LANDLOCK_ACCESS_FS_IOCTL_DEV   (1ULL << 15)   /* 5 */

/* network rights (ABI 4) */
#define LANDLOCK_ACCESS_NET_BIND_TCP    (1ULL << 0)
#define LANDLOCK_ACCESS_NET_CONNECT_TCP (1ULL << 1)

/* IPC scopes (ABI 6) */
#define LANDLOCK_SCOPE_ABSTRACT_UNIX_SOCKET (1ULL << 0)
#define LANDLOCK_SCOPE_SIGNAL               (1ULL << 1)

#endif
