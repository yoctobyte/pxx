---
track: C
prio: 45
type: feature
status: done
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

## Done 2026-09-06 (frankC)

Implemented as one unit, which is how it was filed. `posix_openpt` (open
`/dev/ptmx`), `grantpt`, `unlockpt` (`TIOCSPTLCK`), `ptsname_r`, `ptsname`.

**`grantpt` returns 0 without checking anything and the comment says why.**
devpts makes the grant a mount-time property (`gid`/`mode` on the mount do what
the old setuid helper did), so the 0 is correct — *and it is not evidence about
the slave's ownership.* Those are different claims and this function can only
make the first. The ticket asked for exactly that and it is in the body.

**Declared in `<stdlib.h>`, not a `<pty.h>`**, because that is where glibc puts
them and where callers include them from. busybox's `getpty.c` calls
`ptsname_r` with `<stdlib.h>` in scope and no guard; a `<pty.h>` would have
compiled and never been found.

**The two ioctls are SPELLED, not transcribed.** `sys/ioctl.h`'s tty block says
the `_IOR`/`_IOW`-shaped entries are deliberately absent because *"transcribing
their expansion would bake in this box's `_IOC` layout"*. Writing them as
`_IOR('T', 0x30, unsigned int)` / `_IOW('T', 0x31, int)` against the `_IOC`
machinery already in that file is that rule's **remedy**, not an exception to
it: a target with a different layout produces a different and correct number.
Verified they expand to `0x80045430` / `0x40045431`, which is what
`<asm/ioctls.h>` gives here — a real check, because a wrong layout yields a
number rather than an error.

**`ptsname_r` returns the ERROR NUMBER, not −1**, and sets `errno` as well.
Measured against glibc rather than recalled: `rc=34` for a small buffer,
`rc=25` for a non-pty fd, `errno` matching each time. Both conventions look
right at a call site that only tests for zero, which is why this was measured.

**ERANGE rather than truncation**, with the length computed in full before a
byte is copied. A truncated `/dev/pts/1` for slave 17 is a path that EXISTS and
belongs to another session, so silently shortening hands the caller someone
else's terminal.

### The test, and the ablation that says which row is load-bearing

`test/c_pty_family.c`, 11 rows, diffed whole against gcc — byte-identical, so
no expected value is transcribed and a row added later needs none re-derived.

**Row 8 is the one that matters and I proved it rather than asserting it.**
With `ptsname_r` ablated to always answer `/dev/pts/0` — a well-shaped WRONG
name, which is this family's actual failure mode — row 5's `strncmp` prefix
check **still passes**. Only row 8 (open the slave the name actually names and
round-trip a byte) and row 9 (a second pair must get a different name) drop to
0. A shape assertion alone would have certified the bug.

**Row 8 is non-blocking by construction, after the first version HUNG.** A pty
slave starts in canonical mode, so `read` returns only on a complete line and a
bare `"Z"` waits forever. Both fixes are kept — the newline, and `O_NONBLOCK`
with a bounded retry — because a test that can hang has no verdict and stops
the run instead of reporting one.

### Not done here

`openpty` and `forkpty` are `<pty.h>` functions and are not implemented. They
are a layer above this one (allocate, then `open` the slave, then optionally
`fork` and `login_tty`), and nothing measured needs them yet.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit d4303a1ac.
