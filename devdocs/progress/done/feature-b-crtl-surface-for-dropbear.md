---
track: B
tags: [c, crtl, dropbear]
prio: 50
type: feature
blocked-by: []
summary: "The crtl headers and functions dropbear 2026.94 needed: <utmp.h>/<utmpx.h>/<lastlog.h> (types), <shadow.h>+getspnam, <pty.h>+openpty/forkpty/login_tty, <crypt.h>+SHA-crypt, <netinet/in_systm.h>, <linux/pkt_sched.h> (TC_PRIO only), strlcpy/strlcat/explicit_bzero, getusershell family, daemon, getpass, fexecve, the BSD u_* and suseconds_t types, sockaddr_storage, SOL_TCP, PF_UNIX, IPPORT_RESERVED, SA_NOCLDSTOP and friends, the timeval macros. Each is checked against glibc."
status: done
owner: claude
---

# crtl surface for dropbear

Found building dropbear 2026.94 with pxx ([[feature-c-dropbear-builds-with-pxx]]),
TU by TU. Before this, the missing headers fell back to /usr/include. glibc's
bits/utmp.h then stopped on `__uint32_t`, and 81 TUs failed on that one header
chain.

Added, by header:

- `<utmp.h>`, `<utmpx.h>`, `<lastlog.h>`: the record TYPES only, in glibc's
  layout (a file format shared with other programs; x86-64 sizes measured: 384
  and 292). No functions: dropbear is configured with utmp/wtmp/lastlog and
  `--disable-loginfunc`, so nothing calls them, and a caller that does gets a
  compile error rather than an empty stub. The non-x86 layout follows glibc's
  source and is not measured (no aarch64 glibc on plexus).
- `<shadow.h>` + src/shadow.c: getspnam/getspent/setspent/endspent/sgetspent/
  getspnam_r, shaped like pwd.c. dropbear calls getspnam on every login.
  Like pwd.c it reads the file only, with no NSS.
- `<pty.h>` + src/pty.c: openpty, forkpty, login_tty on top of the existing
  posix_openpt family. dropbear's sshpty.c calls openpty for every
  interactive session.
- `<crypt.h>` + src/crypt.c: SHA-crypt `$5$`/`$6$` (own SHA-256/512).
  Unsupported schemes answer NULL/EINVAL; see
  [[feature-b-crtl-crypt-has-no-yescrypt]].
- `<netinet/in_systm.h>` (n_short/n_long/n_time), and `<linux/pkt_sched.h>`
  with the TC_PRIO_* classes only.
- `<string.h>`: strlcpy, strlcat, explicit_bzero.
- `<unistd.h>`: getusershell/setusershell/endusershell, daemon, getpass,
  fexecve (execveat, falling back to /proc/self/fd), plus the id calls in
  [[bug-b-crtl-setuid-setgid-seteuid-setegid-were-enosys-stubs]].
- `<sys/types.h>`: suseconds_t, useconds_t, u_char/u_short/u_int/u_long,
  ushort/uint/ulong, u_int8_t..u_int64_t (glibc's defaults).
- `<sys/socket.h>`: struct sockaddr_storage (128 bytes, long-aligned),
  PF_UNIX, PF_LOCAL. `<netinet/in.h>`: IPPORT_RESERVED.
  `<netinet/tcp.h>`: SOL_TCP.
- `<signal.h>`: SA_NOCLDSTOP, SA_NOCLDWAIT, SA_NODEFER, SA_RESETHAND (kernel
  values). As before, sigaction accepts flags other than SA_SIGINFO without
  acting on them.
- `<sys/time.h>`: timerisset, timerclear, timercmp, timeradd, timersub.

Tests: test/c_crtl_dropbear_surface.c (expected = glibc's output) and
test/c_crypt_sha.c (expected = libxcrypt's output; the first row is the spec's
published vector).
