---
prio: 70
track: B
type: bug
summary: "csocket_loopback_b88.c includes \"socket.c\", which 8d7c47f8f moved to sys/socket.c — the test has not compiled since"
status: done
---

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/csocket_loopback_b88.c red at 330f62af78d0 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host xeon). Untriaged.
- **Found:** 2026-08-04T23:06:27Z
- **Test source:** test/csocket_loopback_b88.c

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/csocket_loopback_b88.c'` at 330f62af78d0971ee8c39d5aa9bf6dc294aeaab7

## Range
bad `330f62af78d0`, last good `7d8929633721`, 58 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:1: error: C include file not found: "socket.c" (searched: test/, lib/crtl/include/, lib/crtl/src/, /tmp/testmgr-scratch-989299/../lib/crtl/include/, /tmp/testmgr-scratch-989299/../../lib/crtl/include/, lib/crtl/include/, <host system dirs>)
(tail)
pascal26:1: error: C include file not found: "socket.c" (searched: test/, lib/crtl/include/, lib/crtl/src/, /tmp/testmgr-scratch-989299/../lib/crtl/include/, /tmp/testmgr-scratch-989299/../../lib/crtl/include/, lib/crtl/include/, <host system dirs>)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Triage (Track T, 2026-08-05) — attributed, and NOT the blamed sha

**Cause: `8d7c47f8f` — "fix(crtl): the socket veneer was never pulled, so calls
fell back to glibc"**, which MOVED the file:

```
D  lib/crtl/src/socket.c
A  lib/crtl/src/sys/socket.c
```

`test/csocket_loopback_b88.c` line 1 still says `#include "socket.c"`, so it no
longer resolves:

```
pascal26:1: error: C include file not found: "socket.c"
  (searched: test/, lib/crtl/include/, <host system dirs>)
```

Reproduced at HEAD on this box. It is a compile failure, not a socket or
networking problem — the loopback behaviour the test exists to check has not
been exercised since the move.

**The blamed sha is innocent.** The stub names `330f62af7`, which is
`tickets(B): record 0758d456e on the printf/strtod ticket` — a docs-only commit
that cannot break code. It was simply the sha the watcher happened to be
testing; the real cause is earlier in the range. Same shape as
[[bug-t-empty-range-regression-cannot-be-bisected]], which is why that ticket
matters.

**Lane: B** (`lib/crtl/**` is Track B's ground, and the fix is in the test's
include path — one line, either `#include "sys/socket.c"` or an include-path
adjustment). T files, never fixes.


---

## Resolved 2026-08-05

Fixed by `110949bfe` before this ticket was noticed — the watcher auto-filed it
against `330f62af78d0` while the fix was already in flight, so it sat at the
head of Track B's ranked queue (prio 70) pointing at work that was done.

Root cause was as the summary said: `8d7c47f8f` moved `lib/crtl/src/socket.c`
to `src/netinet/in.c` (the path a header actually maps to, so the impl gets
pulled), and the test reached in with `#include "socket.c"` through the
Makefile's `-Ilib/crtl/src`. That include was itself a workaround for the very
bug `8d7c47f8f` fixed — the veneer was never pulled, so the test compiled the
impl itself. With the pull working, the ordinary headers suffice.

Verified at HEAD:

```
tools/testmgr.py --tier native --job 'test-core#src:test/csocket_loopback_b88.c'
  PASS  test-core#459  test/csocket_loopback_b88.c
testmgr: GREEN
```

**Process note:** a watcher-filed regression outlives its fix unless someone
closes it. This one had 58 commits in its bisect range and ranked above every
real Track B item.
- 2026-08-05 — resolved, commit b56956102.
