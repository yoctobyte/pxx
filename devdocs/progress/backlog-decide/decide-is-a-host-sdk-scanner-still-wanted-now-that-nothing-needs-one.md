---
slug: decide-is-a-host-sdk-scanner-still-wanted-now-that-nothing-needs-one
title: "Is `tools/pxx-scan` still wanted, now that all three of its jobs are done by something else?"
track: U
prio: 25
type: decide
status: new
blocked-by: []
owner: user
summary: "feature-dynamic-include-paths-config is the oldest open ticket (2026-06-14) and its big half landed in four slices. Its three remaining bullets were parked on 2026-08-31 as lacking a named consumer. Re-measured 2026-09-01 rather than re-asserted: none has one, and two are near-zero value as specified — the soname fallback table is UNREACHABLE on a normal Linux host, and an xtensa build needs no generated config. What is left is intent only: does the owner still want a scanner tool, or should the bullets be cut so the oldest ticket in the tree can close?"
---

# Is a host/SDK scanner still wanted?

Raised by frankH, 2026-09-01, working the oldest open ticket.

## Why this is a fork and not a measurement

Everything measurable here has been measured; what remains is whether a tool
nobody currently needs is still on the roadmap. Only the owner has that.

`feature-dynamic-include-paths-config` (opened 2026-06-14, prio 25, owner
frankS) landed four slices: `-I`/`-Fu` search roots, `pxx.cfg` tier 3, the
`/usr/include` fallback as a discovered table, and per-directory `pxxlib.cfg`
manifests. Its own 2026-08-31 note demoted 55 -> 25 and said each remaining
bullet **"lacks a named consumer"** and to *"raise it back if a consumer
appears, and say which."* That was an assertion. Below it is a measurement.

## The three bullets, measured today at `fe54f86f7` / `feb2e703acba`

**1. `tools/pxx-scan` — no job left.** Its host half was called redundant on
2026-08-31; re-verified on today's binary rather than inherited, because the
claim's whole point is that hardcoded versions expire. `pxx --where` prints
`/usr/lib/gcc/x86_64-linux-gnu/15/include/` and
`/usr/lib/llvm-21/lib/clang/21/include/` — **discovered**, on a box where the
formerly hardcoded `13` and `18` are both long gone. A generated `pxx.cfg`
would restate what the compiler already finds.

Its ESP half has no job either: `--esp-profile=bare --target=xtensa` builds
`test/test_esp_bare.pas` green with **no generated config at all**, `IDF_PATH`
unset. And nothing in the tree references `pxx-scan` — zero hits outside this
ticket family.

**2. Soname table into config — the table does not execute here.**
`CSonameForStem` (`pasparser_proc.inc:2997`) asks `/etc/ld.so.cache` FIRST and
only falls through to its nine hardcoded entries when the cache is absent,
unreadable, foreign, or cross-compiling. All nine stems resolve from the cache
on this box:

| c | m | pthread | gtk-3 | gtk-x11-2.0 | dl | rt | z | sqlite3 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| all nine resolve to exactly the soname the table would have guessed |

So moving the table into config would relocate a fallback that only runs when
the host is already degraded — and would give it a new way to be absent.

**3. `incpath`/`unitpath` in a manifest — one manifest exists, and it is a
fixture.** `find . -name pxxlib.cfg` returns exactly
`test/libmanifest/pxxlib.cfg`. There is no `external/` tree and no
`lib/synapse/`. Nothing requests the directive, so nothing would consume it.

## The fork

- **(a) Cut all three bullets and close the ticket.** The stated goal — "get
  host paths out of the compiler and into config" — is met and inspectable via
  `pxx --where`. Its one unmet acceptance row is the scanner, and that row was
  written in June against a compiler that hardcoded paths it now discovers.
- **(b) Keep the scanner as a real goal** and say what it is for, so it can be
  ranked on that instead of sitting at 25 forever. A plausible answer nobody
  here can supply: a machine that is NOT this one — a fresh box, a distro whose
  headers sit elsewhere, or an IDF checkout a user has and we do not.
- **(c) Split** — close the ticket, keep only the scanner as its own low-prio
  item with (b)'s justification attached.

**Recommendation: (c).** (a) discards a tool whose value was always about
machines we do not have, and this box cannot see that. (b) leaves the oldest
ticket in the tree open on its smallest bullet, which is the stale-metadata
shape the 2026-08-31 demotion was already trying to fix.

**Nothing is blocked either way** — no work waits on this. It is only that the
oldest open ticket cannot honestly close while one acceptance row is unmet and
unjustified.
