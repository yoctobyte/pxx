---
track: B
prio: 45
type: bug
owner: unassigned
blocked-by: []
summary: "`test/lib_dns_async.pas` holds six hardcoded ports (28766-28771), assigns the return of every `PalBindIpv4` to `rc` and never reads it, and ignores `TcpListen(TPORT)` — then `WaitReadable`/`TcpAccept` on the unbound socket, which parks the coroutine forever. Same class as the lib_tls hang; the last file in lib-test still carrying it, and the easiest to convert because its ports are already function ARGUMENTS, not URL strings."
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
