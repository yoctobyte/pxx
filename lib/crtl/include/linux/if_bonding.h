/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <linux/if_bonding.h> -- the bonding driver's ioctl interface.
 *
 * THE SIX `_OLD' IOCTLS ARE THE ONES BUSYBOX USES, and they are not numbers
 * of their own: each is SIOCDEVPRIVATE plus an index. That is why this header
 * takes <sys/ioctl.h>'s spelling through <linux/sockios.h> rather than
 * carrying 0x89F0 again -- a second copy of a private-ioctl base does not fail
 * to compile, it enslaves the wrong interface.
 *
 * ifslave IS AN OUT PARAMETER whose layout the kernel writes. slave_name is
 * IFNAMSIZ, so the size claim is inherited from <linux/if.h> and changing
 * either one silently moves `link', `state' and link_failure_count.
 *
 * ad_info's partner_system is ETH_ALEN, which the kernel's copy gets from
 * <linux/if_ether.h>. crtl has no such header and <net/ethernet.h> already
 * defines ETH_ALEN under an #ifndef, so that is the one definition site here.
 *
 * Found attempting busybox on i386: networking/ifenslave.c stops at this
 * include -- and only AFTER <linux/if.h> landed, because a TU reports one
 * missing include at a time.
 * feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_LINUX_IF_BONDING_H
#define _CRTL_LINUX_IF_BONDING_H

#include <linux/if.h>
#include <linux/types.h>
#include <linux/sockios.h>
#include <net/ethernet.h>

/* Deprecated in the kernel since 2.5 and still the only spelling busybox's
   ifenslave knows; the SIOC*** replacements sit in <linux/sockios.h>. */
#define BOND_ENSLAVE_OLD           (SIOCDEVPRIVATE)
#define BOND_RELEASE_OLD           (SIOCDEVPRIVATE + 1)
#define BOND_SETHWADDR_OLD         (SIOCDEVPRIVATE + 2)
#define BOND_SLAVE_INFO_QUERY_OLD  (SIOCDEVPRIVATE + 11)
#define BOND_INFO_QUERY_OLD        (SIOCDEVPRIVATE + 12)
#define BOND_CHANGE_ACTIVE_OLD     (SIOCDEVPRIVATE + 13)

#define BOND_CHECK_MII_STATUS      (SIOCGMIIPHY)

#define BOND_ABI_VERSION 2

#define BOND_MODE_ROUNDROBIN    0
#define BOND_MODE_ACTIVEBACKUP  1
#define BOND_MODE_XOR           2
#define BOND_MODE_BROADCAST     3
#define BOND_MODE_8023AD        4
#define BOND_MODE_TLB           5
#define BOND_MODE_ALB           6   /* TLB + RLB (receive load balancing) */

/* each slave's link has 4 states */
#define BOND_LINK_UP    0           /* link is up and running */
#define BOND_LINK_FAIL  1           /* link has just gone down */
#define BOND_LINK_DOWN  2           /* link has been down for too long time */
#define BOND_LINK_BACK  3           /* link is going back */

#define BOND_STATE_ACTIVE       0   /* link is active */
#define BOND_STATE_BACKUP       1   /* link is backup */

#define BOND_DEFAULT_MAX_BONDS  1   /* Default maximum number of devices to support */
#define BOND_DEFAULT_TX_QUEUES  16  /* Default number of tx queues per device */
#define BOND_DEFAULT_RESEND_IGMP 1  /* Default number of IGMP membership reports */

#define BOND_XMIT_POLICY_LAYER2    0  /* layer 2 (MAC only), default */
#define BOND_XMIT_POLICY_LAYER34   1  /* layer 3+4 (IP ^ (TCP || UDP)) */
#define BOND_XMIT_POLICY_LAYER23   2  /* layer 2+3 (IP ^ MAC) */
#define BOND_XMIT_POLICY_ENCAP23   3  /* encapsulated layer 2+3 */
#define BOND_XMIT_POLICY_ENCAP34   4  /* encapsulated layer 3+4 */
#define BOND_XMIT_POLICY_VLAN_SRCMAC 5 /* vlan + source MAC */

/* 802.3ad actor/partner state bits, as they go on the wire. */
#define LACP_STATE_LACP_ACTIVITY   0x1
#define LACP_STATE_LACP_TIMEOUT    0x2
#define LACP_STATE_AGGREGATION     0x4
#define LACP_STATE_SYNCHRONIZATION 0x8
#define LACP_STATE_COLLECTING      0x10
#define LACP_STATE_DISTRIBUTING    0x20
#define LACP_STATE_DEFAULTED       0x40
#define LACP_STATE_EXPIRED         0x80

typedef struct ifbond {
	__s32 bond_mode;
	__s32 num_slaves;
	__s32 miimon;
} ifbond;

typedef struct ifslave {
	__s32 slave_id; /* IN param to the BOND_SLAVE_INFO_QUERY ioctl */
	char  slave_name[IFNAMSIZ];
	__s8  link;
	__s8  state;
	__u32 link_failure_count;
} ifslave;

struct ad_info {
	__u16 aggregator_id;
	__u16 ports;
	__u16 actor_key;
	__u16 partner_key;
	__u8  partner_system[ETH_ALEN];
};

#endif
