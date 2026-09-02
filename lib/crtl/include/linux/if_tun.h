/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <linux/if_tun.h>.
 *
 * IFF_TUN AND IFF_TAP ARE NOT <net/if.h>'s IFF_* AND SHARE ITS PREFIX ANYWAY.
 * They go in `struct ifreq.ifr_flags' for the TUNSETIFF ioctl and nowhere else;
 * IFF_UP and friends go in the same field for SIOCSIFFLAGS. Same struct, same
 * field, two disjoint vocabularies, and the kernel headers do not separate
 * them either -- so a value taken from the wrong one is a legal flag that
 * configures something else. IFF_NO_PI (0x1000) and net/if.h's IFF_MULTICAST
 * (0x1000) are literally the same bit.
 *
 * Found attempting busybox on i386: networking/tunctl.c.
 * feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_LINUX_IF_TUN_H
#define _CRTL_LINUX_IF_TUN_H

#include <linux/types.h>
#include <linux/filter.h>
#include <sys/ioctl.h>

/* Read queue size */
#define TUN_READQ_SIZE  500

/* TUN device type flags: deprecated. Use IFF_TUN/IFF_TAP instead. */
#define TUN_TUN_DEV    IFF_TUN
#define TUN_TAP_DEV    IFF_TAP
#define TUN_TYPE_MASK  0x000f

/* Ioctl defines */
#define TUNSETNOCSUM        _IOW('T', 200, int)
#define TUNSETDEBUG         _IOW('T', 201, int)
#define TUNSETIFF           _IOW('T', 202, int)
#define TUNSETPERSIST       _IOW('T', 203, int)
#define TUNSETOWNER         _IOW('T', 204, int)
#define TUNSETLINK          _IOW('T', 205, int)
#define TUNSETGROUP         _IOW('T', 206, int)
#define TUNGETFEATURES      _IOR('T', 207, unsigned int)
#define TUNSETOFFLOAD       _IOW('T', 208, unsigned int)
#define TUNSETTXFILTER      _IOW('T', 209, unsigned int)
#define TUNGETIFF           _IOR('T', 210, unsigned int)
#define TUNGETSNDBUF        _IOR('T', 211, int)
#define TUNSETSNDBUF        _IOW('T', 212, int)
#define TUNATTACHFILTER     _IOW('T', 213, struct sock_fprog)
#define TUNDETACHFILTER     _IOW('T', 214, struct sock_fprog)
#define TUNGETVNETHDRSZ     _IOR('T', 215, int)
#define TUNSETVNETHDRSZ     _IOW('T', 216, int)
#define TUNSETQUEUE         _IOW('T', 217, int)
#define TUNSETIFINDEX       _IOW('T', 218, unsigned int)
#define TUNGETFILTER        _IOR('T', 219, struct sock_fprog)
#define TUNSETVNETLE        _IOW('T', 220, int)
#define TUNGETVNETLE        _IOR('T', 221, int)
#define TUNSETVNETBE        _IOW('T', 222, int)
#define TUNGETVNETBE        _IOR('T', 223, int)
#define TUNSETSTEERINGEBPF  _IOR('T', 224, int)
#define TUNSETFILTEREBPF    _IOR('T', 225, int)
#define TUNSETCARRIER       _IOW('T', 226, int)
#define TUNGETDEVNETNS      _IO('T', 227)

/* TUNSETIFF ifr flags -- see the note above about the IFF_ prefix. */
#define IFF_TUN           0x0001
#define IFF_TAP           0x0002
#define IFF_NAPI          0x0010
#define IFF_NAPI_FRAGS    0x0020
#define IFF_NO_CARRIER    0x0040
#define IFF_NO_PI         0x1000
#define IFF_ONE_QUEUE     0x2000   /* obsolete */
#define IFF_VNET_HDR      0x4000
#define IFF_TUN_EXCL      0x8000
#define IFF_MULTI_QUEUE   0x0100
#define IFF_ATTACH_QUEUE  0x0200
#define IFF_DETACH_QUEUE  0x0400
#define IFF_PERSIST       0x0800   /* read-only */
#define IFF_NOFILTER      0x1000   /* read-only */

/* Socket options */
#define TUN_TX_TIMESTAMP 1

/* Features for GSO (TUNSETOFFLOAD). */
#define TUN_F_CSUM      0x01   /* You can hand me unchecksummed packets. */
#define TUN_F_TSO4      0x02   /* I can handle TSO for IPv4 packets */
#define TUN_F_TSO6      0x04   /* I can handle TSO for IPv6 packets */
#define TUN_F_TSO_ECN   0x08   /* I can handle TSO with ECN bits. */
#define TUN_F_UFO       0x10   /* I can handle UFO packets */
#define TUN_F_USO4      0x20   /* I can handle USO for IPv4 packets */
#define TUN_F_USO6      0x40   /* I can handle USO for IPv6 packets */

#endif
