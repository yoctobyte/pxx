/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <net/if.h> -- interface names, flags, and struct ifreq.
 *
 * THIS HEADER IS AN ABI, NOT A CONVENIENCE. Everything below is passed to the
 * kernel by ioctl, so a field at the wrong offset does not fail: SIOCGIFADDR
 * fills a different part of the struct and the caller prints a plausible wrong
 * address. busybox's networking/ifconfig.c goes further and indexes into
 * `struct ifreq' with its own offsetof table, so the layout has to match the
 * kernel's uapi/linux/if.h exactly rather than merely holding the same fields.
 * It does: the two unions and the `ifr_ifrn'/`ifr_ifru' spelling are the
 * kernel's, and the ifr_* macros are glibc's names for the same members.
 *
 * `ifr_ifru' is a union of a sockaddr (16 bytes), a short, an int, a pointer,
 * a char[IFNAMSIZ] and a struct ifmap, so its size follows the widest of those
 * on each target -- which is why nothing here hard-codes a byte count.
 *
 * Found attempting busybox rung 2: libbb/xconnect.c (bindtodevice, reached by
 * every networking applet), networking/ifconfig.c, ping.c.
 */
#ifndef _CRTL_NET_IF_H
#define _CRTL_NET_IF_H

#include <sys/socket.h>
#include <sys/types.h>

#define IF_NAMESIZE 16
#define IFNAMSIZ    IF_NAMESIZE
#define IFHWADDRLEN 6

/* Interface flags, uapi/linux/if.h. */
#define IFF_UP          0x1
#define IFF_BROADCAST   0x2
#define IFF_DEBUG       0x4
#define IFF_LOOPBACK    0x8
#define IFF_POINTOPOINT 0x10
#define IFF_NOTRAILERS  0x20
#define IFF_RUNNING     0x40
#define IFF_NOARP       0x80
#define IFF_PROMISC     0x100
#define IFF_ALLMULTI    0x200
#define IFF_MASTER      0x400
#define IFF_SLAVE       0x800
#define IFF_MULTICAST   0x1000
#define IFF_PORTSEL     0x2000
#define IFF_AUTOMEDIA   0x4000
#define IFF_DYNAMIC     0x8000
#define IFF_LOWER_UP    0x10000
#define IFF_DORMANT     0x20000
#define IFF_ECHO        0x40000

/* Device mapping, as SIOCGIFMAP reports it. */
struct ifmap {
  unsigned long int mem_start;
  unsigned long int mem_end;
  unsigned short int base_addr;
  unsigned char irq;
  unsigned char dma;
  unsigned char port;
};

struct ifreq {
  union {
    char ifrn_name[IFNAMSIZ];       /* interface name, NUL-padded */
  } ifr_ifrn;
  union {
    struct sockaddr ifru_addr;
    struct sockaddr ifru_dstaddr;
    struct sockaddr ifru_broadaddr;
    struct sockaddr ifru_netmask;
    struct sockaddr ifru_hwaddr;
    short int ifru_flags;
    int ifru_ivalue;
    int ifru_mtu;
    struct ifmap ifru_map;
    char ifru_slave[IFNAMSIZ];
    char ifru_newname[IFNAMSIZ];
    char *ifru_data;
  } ifr_ifru;
};

/* glibc's names for the members above. Several alias ifru_ivalue -- that is
   the kernel's doing, not a shortcut here: metric, ifindex, bandwidth and qlen
   all travel in the same int. */
#define ifr_name      ifr_ifrn.ifrn_name
#define ifr_hwaddr    ifr_ifru.ifru_hwaddr
#define ifr_addr      ifr_ifru.ifru_addr
#define ifr_dstaddr   ifr_ifru.ifru_dstaddr
#define ifr_broadaddr ifr_ifru.ifru_broadaddr
#define ifr_netmask   ifr_ifru.ifru_netmask
#define ifr_flags     ifr_ifru.ifru_flags
#define ifr_metric    ifr_ifru.ifru_ivalue
#define ifr_mtu       ifr_ifru.ifru_mtu
#define ifr_map       ifr_ifru.ifru_map
#define ifr_slave     ifr_ifru.ifru_slave
#define ifr_data      ifr_ifru.ifru_data
#define ifr_ifindex   ifr_ifru.ifru_ivalue
#define ifr_bandwidth ifr_ifru.ifru_ivalue
#define ifr_qlen      ifr_ifru.ifru_ivalue
#define ifr_newname   ifr_ifru.ifru_newname

/* SIOCGIFCONF's buffer descriptor. */
struct ifconf {
  int ifc_len;                      /* size of the buffer, in bytes */
  union {
    char *ifcu_buf;
    struct ifreq *ifcu_req;
  } ifc_ifcu;
};

#define ifc_buf ifc_ifcu.ifcu_buf
#define ifc_req ifc_ifcu.ifcu_req

/* if_nameindex(3)'s array; the last element has index 0 and name NULL. */
struct if_nameindex {
  unsigned int if_index;
  char *if_name;
};

/* 0 on failure with errno set -- index 0 is never a real interface, which is
   what makes a plain zero test correct here. */
unsigned int if_nametoindex(const char *ifname);
/* Writes at least IF_NAMESIZE bytes into ifname; returns ifname or NULL. */
char *if_indextoname(unsigned int ifindex, char *ifname);

struct if_nameindex *if_nameindex(void);
void if_freenameindex(struct if_nameindex *ptr);

#endif
