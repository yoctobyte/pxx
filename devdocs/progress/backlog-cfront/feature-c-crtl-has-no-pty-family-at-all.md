---
track: C
prio: 45
type: feature
status: open
found: 2026-09-02
found-by: frankD
owner:
summary: "crtl has NO pty support: posix_openpt, grantpt, unlockpt, ptsname and ptsname_r are all absent from include/ and src/ (grep -rn over both returns nothing). busybox's libbb/getpty.c calls ptsname_r directly and busybox ASSUMES it exists -- include/platform.h:410 `#define HAVE_PTSNAME_R 1` is the default and nothing undefines it for a glibc-shaped libc, so there is no fallback path to take. Not blocking the current 141-applet busybox set (getpty.c is not in that TU list; measured against the harness's tulist), which is why this is filed rather than fixed: it blocks telnetd, script, microcom and the login-ish applets whenever the config grows to include them. Filed as a GROUP because the five calls are one mechanism -- open /dev/ptmx, TIOCSPTLCK to unlock, TIOCGPTN to get the number, format /dev/pts/N -- and implementing any one alone is not usable."
---

# crtl has no pty family at all

Found attempting busybox rung 2 (`feature-c-corpus-busybox-multi-applet`) while
auditing crtl against busybox's `HAVE_*` default table (`include/platform.h`
:403-433) — the table is a list of things busybox will call WITHOUT a guard,
so every entry crtl lacks is a compile error waiting for the config that
reaches it.

## What is missing

`posix_openpt`, `grantpt`, `unlockpt`, `ptsname`, `ptsname_r`. Nothing in
`lib/crtl/include/**` or `lib/crtl/src/**` mentions any of them.

## Why it is one ticket and not five

On Linux the whole family is three ioctls on `/dev/ptmx` plus string
formatting:

- `posix_openpt(flags)` — `open("/dev/ptmx", flags)`.
- `grantpt(fd)` — a no-op on any kernel with devpts mounted (the modern
  `gid`/`mode` mount options do what the old setuid helper did). Returning 0
  is correct here, but it must SAY so, because "returns 0" and "did the
  permissions work" are different claims.
- `unlockpt(fd)` — `ioctl(fd, TIOCSPTLCK, &zero)`. `TIOCSPTLCK` is
  `_IOW('T', 0x31, int)`; the numeric form belongs in `<sys/ioctl.h>` beside
  the tty block landed 2026-09-02, which deliberately skipped the `_IO*`-shaped
  entries.
- `ptsname_r(fd, buf, len)` — `ioctl(fd, TIOCGPTN, &n)` then
  `snprintf(buf, len, "/dev/pts/%d", n)`, with **ERANGE rather than
  truncation** when it does not fit; `ptsname` is that with a static buffer.

Implementing one without the others gives a caller a master fd it cannot use.

## The trap to avoid

`grantpt` returning 0 unconditionally is the right implementation and the
wrong comment. A "succeeded" that never checked anything is the shape this
codebase spends its time on — the body should note that devpts makes the
grant a mount-time property, so that a future reader does not read the 0 as
evidence about the slave's ownership.

## Not blocking today

The 141-applet busybox configuration does not compile `libbb/getpty.c`
(checked against the harness's generated `tulist.txt`, which is read off
`busybox_unstripped.map`). This is latent, not live.
