---
track: B
prio: 55
type: bug
blocked-by: []
summary: "`test/lib_tls.pas` binds a hardcoded port 28755 and ignores the return of every socket call, so a failed `fpBind` leaves `fpListen` on an implicit ephemeral port and `fpAccept` blocks FOREVER. Reproduced on demand: two concurrent copies, one completes 14 `=ok`, the other hangs after 7 and has to be SIGKILLed. This is the `lib-test#src:test/lib_tls.pas` timeout Track T keeps reporting — twice now, and never a code regression."
status: done
owner: frankonpiler-etree
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

---

## Resolved 2026-08-19 — the class, not the instance

Reproduced first, on pinned **v353**, exactly as filed: two copies of the old
binary, one exits 0 with 14 `=ok`, the other wedges after **7** and has to be
killed. Confirmed before changing anything, because a fix for a bug you have not
seen is a guess.

### `test/lib_tls.pas`

Port 0 + `fpGetSockName`, every return checked, and a deadline on the accept:

- `fpBind(srv, …)` on **port 0** — the kernel hands out a port nobody holds. This
  is the fix rather than `SO_REUSEADDR` for the reason T gave: REUSEADDR makes the
  collision *rarer*, port 0 makes it *unrepresentable*. REUSEADDR is set anyway,
  as hygiene against a listener in TIME_WAIT.
- `fpGetSockName` reads back which port. Skipping it would not be a clean error
  either — `fpListen` binds implicitly, so `a` would still hold port 0 and the
  connect would go somewhere else. That is step 2 of the original chain.
- every `fpSocket`/`fpBind`/`fpListen`/`fpGetSockName`/`fpConnect` return is now
  read, reported as `fixture-listen` / `fixture-connect`, and a failure `Halt`s
  with a named line instead of continuing into the seam with bad descriptors.
- `fpAccept` is gated by `fpSelect(…, 5000)`. Five seconds is thousands of times
  the ~1s the whole test takes, so it can only fire on a broken fixture.

14 `=ok` → **16** (`fixture-listen`, `fixture-connect` are new); Makefile count
updated with a comment saying why it moved.

### The sibling audit — ELEVEN files, one pattern, all verified

T's note said the pattern was worth one pass while it was in hand. It was: nine
more files carried the identical `lfd := TcpListen(PORT)` with the return ignored
and `TcpAccept(lfd)` on the next line.

| file | was | now |
| --- | --- | --- |
| `lib_tls.pas` | 28755 | 0 + `fpGetSockName` |
| `lib_http_async.pas` | **28755 — the same number as lib_tls**, same recipe | 0 + `TcpLocalPort` |
| `lib_https_mock.pas` | 28760 | 0 |
| `lib_http_keepalive.pas` | 28788 | 0 |
| `lib_http_pool.pas` | 28799 | 0 |
| `lib_http_redirect.pas` | 28777 | 0 |
| `lib_http_pool_concurrent.pas` | 28811 | 0 |
| `lib_http_gzip.pas` | 28822 | 0 |
| `lib_http_cookie.pas` | 28833 | 0 |
| `lib_http_serve.pas` | 28855 | 0 |
| `lib_httpjson.pas` | 28866 | 0 |
| `lib_mimic_urllib_request_server.pas` | 28901 (default + argv) | default 0, reports the real one |

`lib_tls` and `lib_http_async` both held **28755**, in the same `lib-test` recipe
block. That is not a near miss to file away — it is the one pair that could
collide inside a single run, and neither side knew.

`lib_http.pas`, which T also flagged: **pure URL parsing, opens no socket.** Clean,
and worth saying so in writing so nobody audits it again.

### One library addition: `TcpLocalPort`

`lib/rtl/asyncnet.pas` gained `TcpLocalPort(fd)` (over `PalGetSockNameIpv4`).
`TcpListen` already set REUSEADDR and already returned `rc < 0` on a failed bind —
it was correct; the tests just ignored it. What was missing was any way to *learn*
which port port-0 got, so the async family could not use port 0 at all. The two
belong together, which is why this is an API addition rather than ten copies of a
`PalGetSockNameIpv4` call in test files.

`lib_mimic_urllib_request_server.pas` was already the well-behaved one — it checks
the listen and announces `ready <port>` on stdout so the harness waits for a line
instead of sleeping a guess. So it only needed to announce the port it *actually*
got, and the Makefile recipe now reads the port off that line
(`uport=$$(sed -n 's/^ready //p' …)`) and passes it to both the pxx client and the
CPython oracle. The recipe was already grepping for `^ready `, so this cost nothing.

### The verification is a CONCURRENCY check, because that is what the bug was

A green single run proves nothing here — the old test passed solo five times in a
row on the same box. So:

- **8 concurrent copies of the new `lib_tls`**: all 8 exit 0 with 16/16. The old
  one wedged with **2**.
- **11 binaries × 4 copies, all at once** (every converted test simultaneously):
  every run exits 0, zero `FAIL`, nothing wedged.

### What is left, and it is filed rather than half-done

[[bug-b-lib-dns-async-ignores-six-bind-returns-and-can-park-forever]].
`test/lib_dns_async.pas` is the last file in `lib-test` still in this class: six
hardcoded ports (28766-28771), `rc :=` on every `PalBindIpv4` and never read — which
skims as "checked", so it is worse than not assigning — then `WaitReadable` on the
unbound socket. Filed instead of converted because it has six fixtures and a
UDP/PAL shape the other ten do not share; it deserves its own gate rather than
riding along unverified. Its ports are already function *arguments* rather than URL
strings, so it is the easier conversion, not the harder one.

The ticket also names the files that are **already clean** — `lib_ipv6`,
`lib_asyncnet6`, `lib_platform_net`, `lib_platform_net_udp` all check their binds
and fail loudly; `lib_net`, `lib_netconnect`, `lib_net_timeout`, `lib_net_v6only`
already listen on port 0, which is where this idiom came from — so nobody re-audits
them.

### Gate

`make lib-test` green (Track B), built with `$(PXX_STABLE)`; the compiler was not
rebuilt. Plus the 11×4 concurrency check above, which is the part that actually
constrains the fix.

## Log
- 2026-08-19 — resolved, commit PENDING-COMMIT.
