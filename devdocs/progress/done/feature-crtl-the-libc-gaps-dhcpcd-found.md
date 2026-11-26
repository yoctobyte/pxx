---
slug: feature-crtl-the-libc-gaps-dhcpcd-found
track: B
prio: 60
type: feature
status: done
owner: pxx2
created: 2026-11-26
closed: 2026-11-26
found-by: pxx2 (Nodisx dhcpcd recipe, compiled with -nostdinc -I lib/crtl/include)
tags: [crtl, network, posix]
summary: "What dhcpcd 10.5.2 needed from crtl, found by compiling every unit against crtl's headers only (no host fallback): memset_explicit; AF_MAX/PF_MAX; struct nlattr and NLA_* in linux/netlink.h; new <stdalign.h>, <netinet/ip6.h>, <netinet/icmp6.h> (ICMPv6, its Linux-sense filter, neighbour discovery), <linux/icmpv6.h> (router preferences), <linux/genetlink.h>, a partial <linux/nl80211.h>, and <spawn.h> with src/spawn.c (posix_spawn/posix_spawnp on fork, exec errors returned through a CLOEXEC pipe); initstate/setstate on random_r; fpos_t, fgetpos, fsetpos; closefrom (close_range, else a loop to RLIMIT_NOFILE). Every new constant, struct size and offset compared by value with glibc + the kernel headers (105 values identical). Test c_pspawn26 against gcc."
---

# The libc gaps dhcpcd found

Found by compiling all 34 dhcpcd units with `-nostdinc -I lib/crtl/include`:
a plain pxx build falls back to the host's /usr/include and hid most of them.

All headers are written from the RFCs (4443, 4861, 3542, 8200), POSIX and
the kernel's ABI numbers, not copied; checked by a program that prints every
constant and struct size/offset, built once against glibc + kernel headers
and once against crtl (identical, 105 lines).

Notes worth keeping:

* `ICMP6_FILTER_*`: Linux's sense, a SET bit blocks the type (BSD's is the
  reverse). The macros hide it.
* `ND_NA_FLAG_*` sit in a network-order 32-bit word: given in little-endian
  form, as all crtl targets are.
* The RFC 4191/8106 options (route information, RDNSS, DNSSL) are left out,
  as glibc leaves them out; dhcpcd defines its own when they are absent.
* `<linux/nl80211.h>` is PARTIAL on purpose: the names dhcpcd reads the SSID
  with. A program wanting more fails to compile rather than getting a wrong
  number.
* posix_spawn uses fork, not vfork (the child runs C code: file actions,
  signal set-up), blocks all signals across the fork, and returns exec's
  errno as POSIX asks.
* initstate/setstate move random() onto random_r's tables at the first call;
  a program that never calls them keeps rand()'s sequence.
