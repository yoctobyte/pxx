---
title: "Nodisx dhcpcd: build and run with privilege separation"
status: backlog
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
