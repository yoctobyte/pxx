/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <linux/netlink.h> -- the netlink socket family.
 *
 * A PARTIAL SHADOW of a kernel UAPI header, for the reason <linux/fs.h> gives:
 * a cross target has no host tree, so "the kernel's to ship" becomes
 * "nobody's". This one covers the BASE protocol -- the address, the message
 * header, the alignment macros and the flags. the RTM_ types, rtattr and ifinfomsg live in
 * <linux/rtnetlink.h> and are deliberately not here: they are a second,
 * larger protocol layered on this one, and folding them in would make one file
 * that is wrong about two things at once.
 *
 * THE MACROS ARE THE POINT, NOT THE STRUCT. Every netlink walk is
 * NLMSG_OK/NLMSG_NEXT over a buffer, and those are arithmetic on
 * NLMSG_ALIGNTO=4: an NLMSG_HDRLEN that is 16 on one side and, say, sizeof
 * without the align on the other does not fail to compile, it walks the reply
 * off by a few bytes and reads a plausible wrong message. So every macro here
 * is EVALUATED and diffed against the host's own header rather than read
 * across -- see test/c_crtl_netlink.c.
 *
 * Found attempting busybox on i386: libbb/xconnect.c and util-linux/uevent.c
 * need this file; networking/ip.c and libiproute need it plus rtnetlink.
 * feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_LINUX_NETLINK_H
#define _CRTL_LINUX_NETLINK_H

#include <linux/types.h>
#include <sys/socket.h>

/* Protocols carried over AF_NETLINK. */
#define NETLINK_ROUTE           0
#define NETLINK_UNUSED          1
#define NETLINK_USERSOCK        2
#define NETLINK_FIREWALL        3
#define NETLINK_SOCK_DIAG       4
#define NETLINK_NFLOG           5
#define NETLINK_XFRM            6
#define NETLINK_SELINUX         7
#define NETLINK_ISCSI           8
#define NETLINK_AUDIT           9
#define NETLINK_FIB_LOOKUP     10
#define NETLINK_CONNECTOR      11
#define NETLINK_NETFILTER      12
#define NETLINK_IP6_FW         13
#define NETLINK_DNRTMSG        14
#define NETLINK_KOBJECT_UEVENT 15
#define NETLINK_GENERIC        16
#define NETLINK_SCSITRANSPORT  18
#define NETLINK_ECRYPTFS       19
#define NETLINK_RDMA           20
#define NETLINK_CRYPTO         21

struct sockaddr_nl {
  unsigned short nl_family;   /* AF_NETLINK */
  unsigned short nl_pad;      /* zero */
  __u32          nl_pid;      /* port ID; 0 means the kernel */
  __u32          nl_groups;   /* multicast group mask */
};

struct nlmsghdr {
  __u32 nlmsg_len;    /* length INCLUDING this header */
  __u16 nlmsg_type;
  __u16 nlmsg_flags;
  __u32 nlmsg_seq;
  __u32 nlmsg_pid;
};

/* Flags: the first block is universal, then the GET-request set and the
   NEW-request set, which REUSE the same bits with different meanings. */
#define NLM_F_REQUEST       0x01
#define NLM_F_MULTI         0x02
#define NLM_F_ACK           0x04
#define NLM_F_ECHO          0x08
#define NLM_F_DUMP_INTR     0x10
#define NLM_F_DUMP_FILTERED 0x20

#define NLM_F_ROOT      0x100
#define NLM_F_MATCH     0x200
#define NLM_F_ATOMIC    0x400
#define NLM_F_DUMP      (NLM_F_ROOT | NLM_F_MATCH)

#define NLM_F_REPLACE   0x100
#define NLM_F_EXCL      0x200
#define NLM_F_CREATE    0x400
#define NLM_F_APPEND    0x800

#define NLMSG_ALIGNTO   4U
#define NLMSG_ALIGN(len) (((len) + NLMSG_ALIGNTO - 1) & ~(NLMSG_ALIGNTO - 1))
#define NLMSG_HDRLEN    ((int) NLMSG_ALIGN(sizeof(struct nlmsghdr)))
#define NLMSG_LENGTH(len) ((len) + NLMSG_HDRLEN)
#define NLMSG_SPACE(len)  NLMSG_ALIGN(NLMSG_LENGTH(len))
#define NLMSG_DATA(nlh)   ((void *)(((char *)nlh) + NLMSG_HDRLEN))
#define NLMSG_NEXT(nlh, len) \
  ((len) -= NLMSG_ALIGN((nlh)->nlmsg_len), \
   (struct nlmsghdr *)(((char *)(nlh)) + NLMSG_ALIGN((nlh)->nlmsg_len)))
#define NLMSG_OK(nlh, len) \
  ((len) >= (int)sizeof(struct nlmsghdr) && \
   (nlh)->nlmsg_len >= sizeof(struct nlmsghdr) && \
   (int)(nlh)->nlmsg_len <= (len))
#define NLMSG_PAYLOAD(nlh, len) \
  ((nlh)->nlmsg_len - NLMSG_SPACE((len)))

/* Standard message types; anything below NLMSG_MIN_TYPE is reserved. */
#define NLMSG_NOOP      0x1
#define NLMSG_ERROR     0x2
#define NLMSG_DONE      0x3
#define NLMSG_OVERRUN   0x4
#define NLMSG_MIN_TYPE  0x10

struct nlmsgerr {
  int error;                /* negative errno, or 0 for an ACK */
  struct nlmsghdr msg;      /* the header of the message that failed */
};

/* Socket options at SOL_NETLINK. */
#define NETLINK_ADD_MEMBERSHIP   1
#define NETLINK_DROP_MEMBERSHIP  2
#define NETLINK_PKTINFO          3
#define NETLINK_BROADCAST_ERROR  4
#define NETLINK_NO_ENOBUFS       5
#define NETLINK_LISTEN_ALL_NSID  8
#define NETLINK_CAP_ACK         10

#endif
