---
track: B
prio: 55
type: bug
blocked-by: []
summary: "`test/lib_tls.pas` binds a hardcoded port 28755 and ignores the return of every socket call, so a failed `fpBind` leaves `fpListen` on an implicit ephemeral port and `fpAccept` blocks FOREVER. Reproduced on demand: two concurrent copies, one completes 14 `=ok`, the other hangs after 7 and has to be SIGKILLed. This is the `lib-test#src:test/lib_tls.pas` timeout Track T keeps reporting — twice now, and never a code regression."
---

# `lib_tls` hangs forever when its hardcoded port is unavailable

Filed 2026-08-19 by Track T (plexus-T), settling the routing fork the
coordinator raised on the `6070883b46e7` NEW-RED. **Filed, not fixed: T owns the
harness rule and the audit, the owning lane owns the test** — and `lib_tls.pas`
is lib/rtl TLS ground.

## It is not a regression, and that part is decidable

`lib-test#src:test/lib_tls.pas` is `pin_built`. Across the whole 31-commit range
`185575980d53..6070883b46e7`, nothing it reads changed:

```
devdocs 32 | test 3 | tools 2 | compiler 1 | Makefile 1 | CLAUDE.md 1
```

The three `test/` files are a new nilpy test plus `UNWIRED.txt`; the one Makefile
hunk adds steps to **`test-nilpy` and `test-core`**, not `lib-test`. No `lib/**`,
no `test/lib_tls.pas`, no `stable_linux_amd64/**`. Same sources, same pinned
compiler, both ends of the range — the bytes did not move, so no commit in it can
be causal. The watcher's own `pin_immune()` reached the same verdict and refused
the bisect.

## The defect

`test/lib_tls.pas:69` — `const PORT = 28755;` — and then, lines 96-107:

```pascal
fpBind(srv, @a, SizeOf(TInetSockAddr));    { return IGNORED }
fpListen(srv, 4);
cli := fpSocket(AF_INET, SOCK_STREAM, 0);
fpConnect(cli, @a, SizeOf(TInetSockAddr)); { return IGNORED }
conn := fpAccept(srv, @a, @alen);          { BLOCKS, no timeout }
```

No `SO_REUSEADDR`, no return checked, no timeout anywhere. So when the port is
not bindable at that instant, the failure is not a clean error — it is a
**permanent hang**, by this chain:

1. `fpBind` fails. Nobody looks.
2. `fpListen` on an unbound TCP socket **implicitly binds an ephemeral port**, so
   `srv` is now listening on a random port instead of 28755.
3. `fpConnect` dials 28755 — a different socket, or nothing. Nobody looks.
4. `fpAccept(srv)` waits for a connection to that ephemeral port. Nothing will
   ever connect to it. It blocks until the harness kills the job.

The one visible symptom is a testmgr TIMEOUT with a clean `ok:` compile line
above it, which is what has now been triaged three times as a possible TLS
regression.

## Repro — on demand, on any box, in eight seconds

```sh
stable_linux_amd64/default/pinned -Fulib/rtl/platform/posix test/lib_tls.pas /tmp/lib_tls
/tmp/lib_tls & /tmp/lib_tls & sleep 8; jobs
```

Measured 2026-08-19 on plexus, three trials:

| trial | A | B |
| --- | --- | --- |
| 1 | exit 0, 14 `=ok` | **still alive**, 7 `=ok` — SIGKILLed |
| 2 | exit 0, 14 `=ok` | **still alive**, 7 `=ok` — SIGKILLed |
| 3 | exit 0, 14 `=ok` | exit 0, 14 `=ok` (missed the window) |

**Seven `=ok` lines is exactly the boundary**: `avail-none`, `active-nil`,
`handshake-noback`, `read-noback`, `write-noback`, `avail-reg`, `name-mock` — the
whole no-backend and registration section passes, and it stops dead at the first
line of the loopback pair. The TLS seam under test is never reached. Nothing is
wrong with the code this test exists to check.

## Why plexus and not a dev box

Solo the job takes **1.0s** — five consecutive re-runs today, all green, 14
`=ok`. What makes plexus different is that it is the box where **two clones run
testmgr by design** (the watcher's dedicated clone plus a dev checkout), which is
the documented co-tenancy in `devdocs/dev/track-t.md`. A fixed port is a shared
global; two runs is all it takes.

The learned metrics say it has been happening for a long time and nobody read
them: EWMA **45.4s over n=46** on the watcher clone, against **2.4s over n=16**
in the dev clone. A test that takes one second does not average forty-five
seconds by being slow.

## Shape of the fix (B's call, not T's)

The minimum that removes the class, rather than this instance:

- **check the returns.** A failed `fpBind`/`fpConnect` must abort with a named
  failure. A test that cannot set up its fixture must say so, not wait.
- **port 0, not 28755.** Bind ephemeral, read the assigned port back with
  `fpGetSockName`, and dial that. Two copies then cannot collide at all, which
  is strictly better than making the collision loud.
- **`SO_REUSEADDR`** on the listener, and a timeout on `fpAccept` (or a
  non-blocking accept with a deadline) so a broken fixture fails in seconds.

Port 0 is the one that matters; the rest is hygiene.

## Sibling audit — the same hazard, unexamined

`lib-test` has more hardcoded ports in the same recipe block, all in
lib/rtl-owned tests, and none of them audited:

```
test/lib_tls.pas                          28755
test/lib_mimic_urllib_request_server.pas  28901 (passed on the command line)
```

`lib_http` / `lib_http_async` are neighbours in the same recipe and want the same
read. Worth doing in one pass while the pattern is in hand.

## Track T's side, filed separately

The reason this had to be re-derived from scratch instead of read off the
previous instance is that no stub was filed for the recurrence —
[[bug-t-a-resolved-ticket-permanently-suppresses-that-jobs-next-stub]].
Prior instance, closed without ever answering this question:
[[regression-lib-test-lib-tls]].
