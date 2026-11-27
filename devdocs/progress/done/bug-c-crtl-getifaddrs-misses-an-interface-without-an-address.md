---
title: "crtl getifaddrs missed an interface with no IPv4 address yet"
status: done
owner: claude-dupwt
prio: 70
area: crtl
---

crtl's getifaddrs was SIOCGIFCONF, which lists only interfaces that have an
IPv4 address. A DHCP client looks for the fresh, unaddressed eth0 it is
about to configure, so dhcpcd on Rainyday said "eth0: interface not found"
(feature-nodisx-dhcpcd-with-privilege-separation). It also gave no
AF_PACKET (link) entries and no IPv6 addresses.

lib/crtl/src/ifaddrs.c now does what glibc and musl do. An RTM_GETLINK dump
gives one AF_PACKET entry per interface (sockaddr_ll with the hardware
address, flags, broadcast, rtnl_link_stats in ifa_data; no ifa_addr for a
link without one, like a tun). An RTM_GETADDR dump gives the AF_INET/AF_INET6
entries: IFA_LOCAL or IFA_ADDRESS, a peer as dstaddr, broadcast, netmask
from the prefix length, the IPv4 label as the name, and a scope id for
link-local IPv6. SIOCGIFCONF remains the fallback when no netlink socket
opens. On plexus the output equals glibc's for all 15 entries. Test row
c_ifamem26 checks lo's link entry and 127.0.0.1/255.0.0.0.
