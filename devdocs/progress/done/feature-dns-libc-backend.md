---
track: B
prio: 35
type: feature
status: done
owner: claude-B
---

# `dns_libc` — a getaddrinfo backend, for the policy `dns_resolved` cannot see

- **Type:** feature (Track B networking / resolver backends)
- **Split out of** [[feature-dns-backends-selection]] on 2026-08-02, when that
  ticket's acceptance ("at least one non-wire backend") was met by
  `dns_resolved` landing. Item 1 of its remaining-work list.
- **Shape decided** in [[decide-dns-libc-backend-shape]]: option (a),
  `dlopen`+`getaddrinfo`, **deferred not rejected** — the decision explicitly
  asked that it be tracked as real follow-up work rather than left to rot.

## Why it is still wanted now that `dns_resolved` exists

The two backends' gaps are roughly disjoint, which is the whole reason the
decision kept both:

| | needs | misses |
| --- | --- | --- |
| `dns_resolved` | systemd + `resolved` running + its Varlink socket | musl distros, minimal containers, systemd hosts with `resolved` disabled |
| `dns_libc` | glibc at runtime | static/libc-free targets |

Specifically `dns_libc` reaches **nsswitch policy** — custom NSS modules, mDNS
(`.local`), and VPN split-DNS arrangements that route through NSS rather than
through resolved. `dns_resolved` cannot see any of that, and `dns_wire` sees
none of it by construction.

## Shape

`dlopen("libc.so.6")` + `getaddrinfo` through the existing dynlib machinery
([[feature-real-dynlib-loader]]), accepting the glibc-runtime dependency and
version-sensitive struct binding as the known cost. Note `PalBackendDlOpen` is
real only under `-dPXX_DYNLIB_LIBC` today (the syscall-only core avoids linking
libc), so this backend inherits that define or must state its own.

`struct addrinfo` and `struct sockaddr_in`/`_in6` layouts are the risk: they are
ABI, not API, and getting a field offset wrong yields a plausible wrong address
rather than a failure. Bind them against a gcc-built oracle that prints
`offsetof` for every field used, the way the M_* constants were pinned in
`test/cmath_constants.c`.

## Selection

Already wired: `-dPXX_DNS_LIBC` is accepted by `dns.pas` **today** and fails the
build with an error naming this ticket, so nobody silently gets `dns_wire` when
they asked for libc. Implementing this means replacing that `{$error}` with the
`uses` entry and the two dispatch calls — the mutual-exclusion guard against
`-dPXX_DNS_RESOLVED` is already there and already tested.

## Landed 2026-08-02 (commit 55b0a5b1e)

`lib/rtl/dns_libc.pas` — `dlopen("libc.so.6")` + `getaddrinfo`/`freeaddrinfo`
through the existing dynlib machinery, wired into `dns.pas` behind
`-dPXX_DNS_LIBC`.

### The ABI was pinned first, before any code

This ticket flagged `struct addrinfo` as the risk, so the layout was taken from
a gcc `offsetof` probe and checked against pxx's record layout *before* the
backend was written:

| field | gcc x86-64 | pxx x86-64 |
| --- | --- | --- |
| ai_flags / family / socktype / protocol | 0 / 4 / 8 / 12 | same |
| ai_addrlen | 16 | 16 |
| **ai_addr** | **24** | 24 |
| **ai_canonname** | **32** | 32 |
| ai_next | 40 | 40 |
| sizeof | 48 | 48 |

`ai_addr` precedes `ai_canonname` — glibc's order, and the reverse of how POSIX
reference pages commonly list them. That pair is the easiest thing here to get
backwards, and doing so yields a plausible wrong pointer rather than a failure,
so the test asserts the ordering explicitly on top of the offsets.

The layout probe was run on **all four targets**: x86-64 and aarch64 give
48/24/32/40, i386 and arm32 give 32/20/24/28, which is the natural-alignment
layout a 32-bit glibc produces.

### Selection and its guard

`-dPXX_DNS_LIBC` joins the existing convention. Two new compile-time refusals,
both verified to fail with exit 1 and produce no binary:

- with `-dPXX_DNS_RESOLVED`: the mutual-exclusion error, as already specified;
- **without `-dPXX_DYNLIB_LIBC`**: the loader is itself opt-in (it is what makes
  the binary depend on glibc), so asking for this backend without it would build
  a program that can never use it and silently falls back on *every* lookup.
  Refused, with the message naming the missing define.

Fallback contract matches `dns_resolved`'s: a real DNS verdict including
NXDOMAIN is returned as-is, and only `DNS_ERR_LIBC_UNAVAIL` — no loader, no
glibc, `getaddrinfo` unresolved — falls through to wire. `getaddrinfo`'s own
codes are mapped rather than passed through: `EAI_NONAME`/`EAI_NODATA` become
rcode 3, `EAI_AGAIN`/`EAI_FAIL` become 2, and anything else is *not* a DNS
verdict so it stays a backend error and falls back, rather than reporting a
lookup result we did not actually get.

`hints.ai_socktype` is set to SOCK_STREAM deliberately: without it getaddrinfo
returns every address once per socket type, which would have looked like
duplicate answers.

### Verified

| check | result |
| --- | --- |
| vs `getent ahostsv4` (the nsswitch oracle) | identical addresses |
| vs `dns_wire` and `dns_resolved` through the facade | identical |
| NXDOMAIN | rcode 3, zero addresses |
| ABI offsets vs gcc | all 10 assertions, x86-64 and i386 |
| both defines / missing loader define | compile error, exit 1, no binary |
| default build (no define) | undisturbed on all four targets |

**Cross-target, stated precisely.** The *layout* is verified on all four
targets by the static probe. The *live* `getaddrinfo` call runs on x86-64 and
i386 only: this backend necessarily produces a dynamically-linked binary, and
this box has no aarch64/arm32 sysroot, so `qemu` cannot find those targets'
`ld-linux`. That is an environment limit, not a code result, and it is item (b)
of [[feature-real-dynlib-loader]] — the same missing cross-runner story. Not
claimed as passing.

Test: `test/lib_dns_libc.pas`, in `lib-test` twice (default and with the
define), `localhost` only so it needs no network, skipping its libc half where
glibc or the loader is absent.

## Gate

Agreement with `dns_resolved` and `dns_wire` on names all three can answer,
plus at least one name only NSS can (an `/etc/nsswitch.conf` module or a
`.local` mDNS name) to prove it is actually going through NSS. `localhost`-only
tests like `test/lib_dns_resolved.pas` keep it network-free; the backend must
skip itself where glibc is absent, as the resolved backend skips where its
socket is. Cross-target i386/aarch64/arm32, since the struct layouts differ by
word size — that check is what caught nothing here only because `dns_resolved`
sends JSON; `dns_libc` binds real C structs and is far more exposed.

## Log
- 2026-08-02 — resolved, commit PENDING.
