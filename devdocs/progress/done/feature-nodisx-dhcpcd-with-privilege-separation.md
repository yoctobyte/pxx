---
title: "Nodisx dhcpcd: build and run with privilege separation"
status: done
owner: claude-dupwt
prio: 65
area: nodisx
created: 2026-11-27
found-by: owner 2026-11-27 ("not to run sensitive code as root")
---

tools/nodisx/dhcpcd is recorded with --disable-privsep, so the whole
daemon, including its DHCP and RA packet parsers, runs as root. With
privsep, dhcpcd forks a root process that does only the privileged work
(routes, addresses, raw sockets) and runs the network-facing parsing as an
unprivileged user in a chroot, passing descriptors over socketpairs
(SCM_RIGHTS). On Linux it also installs seccomp filters
(privsep-linux.c; --disable-seccomp exists).

Needs:
- record with --enable-privsep --privsepuser=_dhcpcd; seccomp stays on if
  the Rainyday kernel implements it, otherwise --disable-seccomp (state
  which);
- the installer creates the user and its chroot (/var/lib/dhcpcd, with
  /tmp, per configure's warning);
- crtl: getpwnam, setgroups/setgid/setuid, chroot, SCM_RIGHTS send/recv;
- Rainyday: the same syscalls, plus prctl(PR_SET_NO_NEW_PRIVS) and,
  optionally, seccomp;
- test: a real lease (DISCOVER..ACK) with privsep on, in a Rainyday guest
  with QEMU's user-mode DHCP, and ps showing the parser processes are not
  uid 0.

## Done 2026-11-27 (claude-dupwt)

The recipe now records with --enable-privsep --privsepuser=_dhcpcd, and
seccomp stays ON: Rainyday implements seccomp-bpf, prctl NO_NEW_PRIVS,
SCM_RIGHTS, setres*id and chroot.
tools/nodisx/dhcpcd/test-privsep-rainyday.sh: PASS. In the guest, dhcpcd
leased 10.0.2.15, added the route and default route, its hooks wrote
resolv.conf, ping and fetch worked, and `dhcpcd -4 -x` stopped it.
/proc showed 4 dhcpcd processes at uid 150 with Seccomp 2 and 1 root
process (the privileged helper, by design).

What it needed, found in order by the live run:
- crtl <linux/audit.h>, <linux/seccomp.h>, <linux/net.h> (kernel values)
- Rainyday NETLINK_GENERIC (179dfaa, rainyday session). Without privsep
  too, dhcpcd had never got past start-up on Rainyday.
- crtl getifaddrs from netlink: bug-c-crtl-getifaddrs-misses-an-interface-without-an-address
- crtl open_memstream position: bug-c-crtl-open-memstream-has-no-position
dhcpcd's own test.sh with PXX_NO_HOST_INCLUDE=1: PASS.

## Reconciled 2026-11-27 (pxx session; the same item was done twice in parallel)

The test added the _dhcpcd user inside the guest by hand, so it passed while
an install from the recipe had no user and would have run every dhcpcd
process as root. Now:
- onsite.sh's install adds _dhcpcd to etc/passwd and etc/group (and
  etc/shadow if present) unless it is there, at the lowest id in 100..999
  neither file uses, with the empty home /var/lib/dhcpcd as the chroot.
- test-privsep-rainyday.sh takes the account from DHCPCD_DESTDIR (it fails
  without one) and fails on any dhcpcd process that is neither _dhcpcd under
  seccomp nor the one root "[privileged proxy]". Rainyday's cmdline now shows
  dhcpcd's process titles. It also fails on a "No such file or directory" or
  "Permission denied" in dhcpcd's log, which caught /var/db/dhcpcd missing
  from the image (no lease file). PASS: 5 processes, 4 at uid 100 with
  Seccomp 2, the privileged proxy root.
- crtl getifaddrs: the request goes out with send() and replies come in
  through recv() at 32 bits, because crtl's i386 sendto takes AF_INET
  addresses only. At 64 bits recvmsg checks the sender (nl_pid 0) and
  MSG_TRUNC. Equal to glibc's list at both widths (c_crtl_getifaddrs). The
  SIOCGIFCONF list stays for systems with no netlink (EAFNOSUPPORT).
- crtl open_memstream follows glibc: SEEK_END counts from the position, a
  seek past the end reads back zeros, a negative one is EINVAL, fileno is
  -1 with EBADF (c_crtl_memstream_seek, both widths).
- <linux/seccomp.h> gains the notification structures and ioctls, plus
  <linux/elf-em.h>. c_crtl_seccomp_uapi installs a live filter.
  <netinet/in.h> gains IN6_IS_ADDR_MC_*.
