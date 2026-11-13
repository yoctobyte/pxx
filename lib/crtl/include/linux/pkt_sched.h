/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <linux/pkt_sched.h> -- ONLY the TC_PRIO_* socket priority
 * classes, the values SO_PRIORITY takes (see tc-prio(8)).
 *
 * dropbear's netio.c sets SO_PRIORITY to TC_PRIO_INTERACTIVE for interactive
 * sessions. The kernel's header also defines the whole qdisc/class
 * configuration interface (struct tc_prio_qopt, tc_cbq_*, ...). That interface
 * is not here: a program that needs it gets a compile error rather than a
 * half-copied struct. busybox's networking/tc.c is such a program, and
 * busybox's own configuration never builds it.
 *
 * The numbers are the kernel's ABI (include/uapi/linux/pkt_sched.h).
 */
#ifndef _CRTL_LINUX_PKT_SCHED_H
#define _CRTL_LINUX_PKT_SCHED_H

#define TC_PRIO_BESTEFFORT        0
#define TC_PRIO_FILLER            1
#define TC_PRIO_BULK              2
#define TC_PRIO_INTERACTIVE_BULK  4
#define TC_PRIO_INTERACTIVE       6
#define TC_PRIO_CONTROL           7

#define TC_PRIO_MAX               15

#endif
