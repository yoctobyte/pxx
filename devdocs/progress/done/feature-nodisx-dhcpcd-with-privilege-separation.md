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
