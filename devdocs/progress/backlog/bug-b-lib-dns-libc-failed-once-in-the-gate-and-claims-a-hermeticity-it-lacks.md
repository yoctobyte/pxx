---
track: B
prio: 30
type: bug
blocked-by: []
summary: "lib_dns_libc's default build failed one `make lib-test` run on 2026-08-28 and did not reproduce in a full gate re-run or 15 direct runs of the same binary — cause undiagnosed, recorded so the next false red is not rediscovered from scratch. Separately and verifiably: the test's header claims `NO NETWORK: every lookup is localhost`, which is false in the PXX_DNS_LIBC build — it resolves `nonexistent-zzz-qqq.invalid`, which goes to the resolver."
---

# `lib_dns_libc`: one unreproduced gate failure, and a hermeticity claim that is not true

Filed 2026-08-28 by frankB (Track B) while gating an unrelated change. **Two
findings of very different strength — kept apart on purpose.**

## 1. The intermittent — observed, NOT diagnosed

`make lib-test` stopped here:

```
test "$(/tmp/lib_dns_libc_default | tail -1)" = "DNSLIBC OK"
make: *** [Makefile:14633: lib-test] Error 1
```

Evidence, in full, because one failure is not a diagnosis:

| run | result |
| --- | --- |
| gate run 1 (before the day's changes) | pass |
| gate run 2 | pass |
| **gate run 3** | **fail, here** |
| gate run 4 (re-run, no change to this test or its deps) | pass |
| the same binary, run 15× directly afterwards | 15 pass |

Box load was 12–15 throughout, with Track T holding a tier.

**I could not reproduce it and I am not guessing at a cause.** The binary that
failed is the one that then passed fifteen times, so the failure was not in the
built code. The failing build is the **default** one — `PXX_DNS_LIBC` is not
defined — so the `.invalid` lookup in finding 2 below is *not* reachable in it
and is not the explanation, however tempting the adjacency.

Recorded rather than dropped because an unrecorded intermittent in a lane's own
gate is the expensive kind: the next person to hit it spends the same hour, and
in the meantime a red gate means less than it should. Same family as
`bug-t-a-skipped-job-is-passlike-so-it-becomes-a-false-last-good` — a gate
result that does not mean what it appears to.

## 2. The header's hermeticity claim is false in one build — verifiable, not a guess

`test/lib_dns_libc.pas`'s header says:

> NO NETWORK: every lookup is `localhost`.

Inside `{$ifdef PXX_DNS_LIBC}`:

```pascal
rc := DnsLibcResolveHost('nonexistent-zzz-qqq.invalid', ips2, n2);
ChkI('libc_nxdomain_rcode', rc, 3);
```

That is a **negative** lookup, and glibc's `getaddrinfo` answers it by consulting
`nsswitch.conf` — which normally means sending a query to the configured
resolver and waiting for NXDOMAIN. `.invalid` is reserved and *should* be
refused quickly, but "should be refused quickly by whatever resolver this box
happens to point at" is not the same as "no network", and the assertion is on an
exact rcode of 3: a resolver answering SERVFAIL, or not answering, gives a
different number.

The assertion is worth keeping — mapping `EAI_NONAME` onto rcode 3 is the
contract that lets the facade treat a libc failure like a wire failure. What is
wrong is the **claim**, which tells a reader this file cannot be affected by the
network. Either correct the header, or make the negative case hermetic.

## Scope

Track B (`test/lib_dns_libc.pas`). Finding 2 is a doc fix or a small test change
and is the actionable half. Finding 1 has no fix until it reproduces — if it
recurs, add the observation here rather than opening a second ticket, and
capture the binary's actual output (the `test` form discards it, which is why
this report cannot say what the last line WAS).

**That last point is the reusable one:** `test "$(prog | tail -1)" = "SENTINEL"`
throws away the output on failure, so an intermittent leaves no evidence at all.
A gate line that captured stdout on mismatch would have turned this ticket into
a diagnosis.

## 2026-08-28 — hermeticity FIXED (and this overturned the flake analysis)

The false claim was the certain half and is fixed. It did not stay contained:
measuring it properly overturned the reason this ticket had excluded the
network, and surfaced a real resolver defect underneath.

### The first correction was wrong, and how that was caught

Straced glibc's `getaddrinfo` and got a clean result — `localhost` 0 contacts to
port 53, `nonexistent-zzz-qqq.invalid` 9 — then wrote a header correction saying
the default build was hermetic and only the libc build was not.

**That measured a proxy, not the system.** The default build does not use glibc
at all; it uses our own wire resolver. The numbers were plausible, so nothing
about the result flagged it; what flagged it was re-reading *what had been
measured*. On the actual binaries:

| build | contacts to port 53 |
| --- | --- |
| default | **6** |
| libc | **12** |

**Neither was hermetic**, including the build that went red.

### Cause, fully explained

`/etc/hosts` here has `127.0.0.1 localhost` but spells the v6 loopback
`ip6-localhost` — the Debian/Ubuntu convention — so there is no `::1 localhost`
line. Therefore:

- line 72 `DnsResolveHost('localhost')` — files hit, no network.
- line 75 `DnsResolveHost6('localhost')` — files MISS, falls through to the
  wire, queries `localhost.home`, `localhost.<search>`, `localhost.` against
  127.0.0.53.

And line 76 asserted `rc = 0`. **The row passed only because the network
answered**, and a transient failure there produces exactly a one-off
`DNSLIBC FAILED` in the default build.

### Retraction

This ticket said the network was ruled out because the `.invalid` row sits
behind `{$ifdef PXX_DNS_LIBC}` while the failing build was the default. That is
sound for the `.invalid` **row** and false for the **build**. The exclusion is
withdrawn. This still does not diagnose the flake — one failure is not a cause —
but there is now a mechanism with evidence and a named assertion that would go
red, which is a better starting point than fifteen non-reproductions.

### What changed

- **v6 row made hermetic.** It now resolves the literal `::1`, which
  short-circuits without network. Measured after: default build **0** contacts
  to port 53 (was 6), libc build **6** (was 12), the remaining six being the
  deliberate `.invalid` row, which is guarded behind `PXX_DNS_LIBC` and is
  testing that EAI_NONAME maps onto rcode 3.
- **Header rewritten** against those numbers, with the proxy mistake recorded in
  the file so the next reader does not repeat it.
- **Diagnostic preserved.** Both assertions were
  `test "$(prog | tail -1)" = "DNSLIBC OK"`, which is why the single red left no
  record: that shape discards stdout on mismatch. They now capture the output
  and print it on failure. The assertion is unchanged — same command, same
  expected last line. Negative-controlled with a stub printing a failing `chk`
  row: the rule prints the whole output and make aborts; the passing case stays
  silent.

### Filed separately

[[bug-b-resolver-sends-localhost-to-the-wire]] — the resolver has no `localhost`
special-case at all, so the name goes to the wire and whatever comes back is
used. RFC 6761 section 6.3 says resolvers SHOULD always return loopback for
localhost names; glibc complies, we do not. Filed as a bug rather than a
`decide-` because a hostile or misconfigured server can answer `localhost` with
a non-loopback address, which a correct program can observe.

Recorded there and worth repeating: `.invalid` has a DIFFERENT prescription
(section 6.4, immediate negative responses), so glibc's willingness to query
`.invalid` says nothing about `localhost`. That inference was made here and was
wrong.

### Still open

The intermittent itself. One failure, not reproduced in a full re-run or fifteen
direct runs. What has changed is that the leading candidate mechanism is now
identified and removed, so if it recurs, it recurs against a hermetic default
build — and with the diagnostic preserved.
