---
track: B
prio: 45
type: bug
owner: frankonpiler-etree
blocked-by: []
summary: "`test/lib_dns_async.pas` holds six hardcoded ports (28766-28771), assigns the return of every `PalBindIpv4` to `rc` and never reads it, and ignores `TcpListen(TPORT)` — then `WaitReadable`/`TcpAccept` on the unbound socket, which parks the coroutine forever. Same class as the lib_tls hang; the last file in lib-test still carrying it, and the easiest to convert because its ports are already function ARGUMENTS, not URL strings."
status: done
---

# `lib_dns_async` ignores six bind returns and can park forever

- **Type:** bug — Track B (libraries/tests)
- **Opened:** 2026-08-19
- **Filed by:** Track B while fixing
  [[bug-b-lib-tls-hangs-forever-when-its-hardcoded-port-is-unavailable]] and
  sweeping its siblings. Eleven files were converted in that pass and verified;
  this one is filed rather than converted because it has **six** fixtures rather
  than one and a UDP/PAL shape the other ten do not share, so it deserves its own
  gated change instead of riding along unverified on theirs.
- **Measured on:** pinned v353, 2026-08-19.

## The same class, confirmed by reading the same three lines

```pascal
  PORT  = 28766;   CPORT = 28767;   DPORT = 28768;
  SPORT = 28769;   KPORT = 28770;   TPORT = 28771;
...
  rc := PalBindIpv4(sock, PAL_NET_IP_LOOPBACK, PORT);   { rc assigned, never read }
  rc := PalSetSocketNonBlocking(sock, 1);               { rc overwritten }
  WaitReadable(sock);                                   { parks forever }
```
(sites: lines 44, 92, 163, 179, and the `KPORT` server; plus)
```pascal
  lfd := TcpListen(TPORT);        { line 317 — return ignored }
  cfd := TcpAccept(lfd);          { line 318 — parks forever }
```

`rc :=` followed by an immediate overwrite is worse than no assignment: it reads
as "checked" to a skim. A lost bind then leaves the socket unbound, nothing ever
arrives, and `WaitReadable` / `TcpAccept` park the coroutine with no deadline —
the harness kills the job and reports a TIMEOUT under a clean compile line, which
is exactly the symptom that got triaged three times as a TLS regression before
the lib_tls ticket pinned it down.

## Why this one is EASIER than the ten already converted, not harder

The ten HTTP tests baked their port into a URL **string literal**
(`'http://127.0.0.1:28822/'`), so each needed the port threaded into string
construction. Here the port is already a plain **argument**:

```pascal
  gTimeoutRc := DnsQueryAAsyncEx(PAL_NET_IP_LOOPBACK, DPORT, 'dead.x', ...);
```

So the conversion is: bind port 0, read the assigned port back
(`PalGetSockNameIpv4`, or `TcpLocalPort` for the TCP one — added to
`lib/rtl/asyncnet.pas` in the lib_tls fix), publish it in a global, and pass that
global where the constant used to go. No string surgery at all. Six times.

## What to do

1. Every `rc :=` on a bind/listen gets **read**, and a failure prints a named
   line and exits the coroutine — a test that cannot build its fixture must say
   so, not wait.
2. Ports become 0 + read-back. Port 0 makes the collision *unrepresentable*;
   `SO_REUSEADDR` alone would only make it rarer, which is the distinction the
   lib_tls ticket turns on.
3. Consider a deadline on the parks, as the lib_tls fix put on `fpAccept`
   (`fpSelect` with a 5s timeout). With returns checked and port 0 there should be
   nothing left to wait for, but a blocking wait with no deadline is a hang
   waiting for its next cause.

## Already clean — do NOT "fix" these

Checked in the same pass, listed so nobody re-audits them:

| file | ports | verdict |
| --- | --- | --- |
| `test/lib_ipv6.pas` | 28846 | checks bind AND listen, `Halt(1)` on either — loud |
| `test/lib_asyncnet6.pas` | 28860 | checks `TcpListen6`, reports SKIP — loud |
| `test/lib_platform_net.pas` | 48691 | checks bind, prints `tcp=bind-fail` — loud |
| `test/lib_platform_net_udp.pas` | 48733 | same shape as above |
| `test/lib_http.pas` | — | pure URL parsing, opens no socket |
| `test/lib_net.pas`, `lib_netconnect.pas`, `lib_net_timeout.pas`, `lib_net_v6only.pas` | 0 | **already** listen on port 0 — this is where the idiom came from |

One wart worth a line rather than a ticket: `test/lib_net6.pas:47-50` calls
`NetTcpAccept(srv, p)` *before* testing `srv < 0`. It does not hang — accept on an
invalid descriptor errors immediately and the check below catches it — but the
check belongs above the accept.

## Gate

Track B: build with `$(PXX_STABLE)` (never rebuild the compiler), `make lib-test`
green, and the concurrency check that proves the class is gone rather than the
instance — four copies of the binary at once, none wedged. The lib_tls pass used
eleven binaries × four copies simultaneously; two copies of the OLD lib_tls were
enough to wedge one, so the check has teeth.

---

## Resolved 2026-08-19 — and the UDP failure is NOT the same failure

Built and measured on pinned **v354** (`1fffc8cf5c3e`). The coordinator's warning
was the right one and it paid off immediately: **do not assume a UDP/PAL fixture
wedges the way the TCP one did.** Two concurrent copies of the pre-fix binary
(`git show HEAD:test/lib_dns_async.pas`, same compiler) gave **two different
failure modes at once**:

| copy | exit | `=ok` | `FAIL` |
| --- | --- | --- | --- |
| 1 | **0** | 17 | **4** — `chase-rcode`, `chase-count`, `chase-ip`, `cache-1query` |
| 2 | **124** (killed at 25s) | 0 | 0 — no output at all |

Copy 2 is the hang the ticket predicted. **Copy 1 is worse and was not
predicted:** it did not hang, it *answered its neighbour's queries*. Two processes
bound the same UDP ports, so one server replied to the other's client, and the
assertions that broke were `chase-*` and `cache-1query` — i.e. it reads as **a
regression in CNAME chasing and in the DNS cache**, in a file whose whole subject
is CNAME chasing and the DNS cache. Nothing in that output points at a port.

That is the same trap as the original lib_tls ticket, one turn worse: there, a
port collision looked like a TLS timeout; here it looks like a DNS *logic* bug
with a specific, plausible, completely wrong diagnosis attached. A UDP socket does
not refuse a second binder the way a TCP listener does — it just splits the
traffic — so "does it wedge?" was the wrong question to verify against.

Solo, the old binary passes. It passed for Track T too, which is why it survived.

### The fix — one helper, not six patches

The file had **six** bind sites, every one of them `rc := PalBindIpv4(…)` followed
by an immediate overwrite of `rc`. That spelling is worse than no assignment: it
skims as *checked*. Six sites is six chances to fix five of them, so the returns
are now read in exactly one place:

```pascal
function BindEphemeralUdp(var port: Integer; const who: string): Integer;
```

It binds loopback UDP port 0, reads the assigned port back with
`PalGetSockNameIpv4`, sets non-blocking, and on any failure prints
`fixture-fail <who> <what>=<rc>` and returns <0. Every server coroutine is now two
lines: call it, `Exit` if it failed. The read-back is not optional — the bind
*succeeds* on port 0, so skipping it leaves the client querying port 0, which is
the exact shape of `fpListen`'s implicit bind in the lib_tls original.

`WaitOrGiveUp(sock, who)` wraps `WaitReadableTimeout(sock, 5000)` and names the
give-up. Applied to every previously-unbounded `WaitReadable`, including the
EAGAIN retry loops in the chase and AAAA servers, and to the TCP listener before
`TcpAccept`. `CacheServerCo` already had a deadline and keeps it — there, "no
second query arrived" is the *assertion* (a cache hit), not a failure, which is
why it was the one site written correctly.

### The truncation pair is the one that could not just take port 0

`TcUdpServerCo` and `TcTcpServerCo` must be on the **same port number**: the
resolver falls back from UDP to TCP on the port it queried. UDP and TCP are
separate port spaces, so binding both to 0 independently yields two *different*
numbers and the fallback dials nothing — a green-looking change that silently
removes the coverage this pair exists for. So the UDP half binds 0 and
**publishes** the number, and the TCP half takes that same number in its own
space (nearly always free; if not, it says so instead of parking on the accept).

`TimeoutClientCo`'s deaf socket keeps its own port, local to the coroutine. Its
bind is load-bearing for the *meaning* of the test, not just hygiene: bound and
silent makes the datagram be accepted and dropped, so the query times out, while
an unbound port answers ICMP port-unreachable and the assertion would read a
different error. That is now written down at the site.

21 `=ok` → **22** (`ephemeral-ports`), named apart from the per-fixture checks
because every one of those can fail for a protocol reason and this is the one that
says the fixtures came up.

### Verification — concurrency, at four widths

- 2 concurrent copies: clean (the width that broke the old one **both** ways).
- 6 concurrent: clean.
- 10 concurrent: clean.
- 4 concurrent, repeated 3×, to catch a narrow window: clean each time.

Every copy 22/22, exit 0, zero `fixture-fail`.

### `lib_net6.pas` — the wart, moved, and a correction to this ticket

`NetTcpAccept` is no longer called before `srv < 0` is tested; the listen, connect
and accept each get their own named check above the next use.

Correcting what this ticket said when it was filed: lib_net6 is **loud on
collision, not silent**, and that distinction matters for Track T. Every
`NetTcpListen` / `NetUdpBind` in it is checked and `Halt(1)`s with a named FAIL,
so two concurrent copies produce a failure, not a timeout. It still holds six
hardcoded ports (28850-28857) and they are still a shared global — but converting
them is not the small job it looks like, because the test *asserts the sender's
port* (`if src.Port <> 28853`), so port 0 there needs the read-back threaded
through the assertions too. Left as it is, deliberately, and recorded here so the
next auditor does not mistake "hardcoded" for "hangs".

### Gate

`make lib-test` green (Track B) against stable **v354**, built with
`$(PXX_STABLE)`; the compiler was not rebuilt. Plus the concurrency matrix above,
which is the part that constrains the fix — and the pre-fix two-copy run, which is
the part that proves the matrix is testing something.

## Log
- 2026-08-19 — resolved, commit PENDING-COMMIT.
