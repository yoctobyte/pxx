---
slug: bug-c-an-undeclared-identifier-used-as-a-value-is-a-warning-not-an-error
track: C
type: bug
prio: 45
status: open
found: 2026-09-02
found-by: frankD
blocked-by: []
summary: "pxx's C frontend treats an undeclared identifier used as a VALUE as 0 with a warning, while an undeclared identifier used as a CALL is a hard error. gcc rejects both under -std=gnu99, which is what our own busybox oracle uses. The consequence is not cosmetic: crtl's <sys/syscall.h> defends itself with `naming any SYS_* here is a compile error, which is the point', and that sentence is false under this compiler — an arm32 build of src/sys/statfs.c compiled cleanly and called syscall number 0. Fixing it also requires filling the crtl gaps it is currently papering over (locale.h has no LC_COLLATE/LC_CTYPE/LC_MONETARY/LC_TIME, which the lua build hits today)."
---

# An undeclared identifier is a warning as a value and an error as a call

Two spellings of the same mistake, two different verdicts:

```
pascal26:383: warning: undeclared identifier 'LC_COLLATE' used as value (treated as 0)
pascal26:491: error:   call to undeclared function: getnameinfo
```

gcc rejects both at `-std=gnu99`, and `-std=gnu99` is what
`tools/busybox_diff.sh` passes to the oracle it compares us against — so the
two builds are not compiling the same language on this point.

## Why it is worth more than a diagnostic argument

`lib/crtl/include/sys/syscall.h` deliberately supplies NO numbers for arm32 and
xtensa, and says so in its own words:

> ARM32 AND XTENSA GET NOTHING, DELIBERATELY. ... a guessed number is worse than
> a missing one: a program naming SYS_ioprio_get on arm32 gets a compile error
> saying so, which is the honest answer, rather than a call to whatever number
> 30 happens to mean there.

**That protection does not exist.** Measured 2026-09-02 while adding
`statfs`/`fstatfs`: `lib/crtl/src/sys/statfs.c`, written the obvious way as
`syscall(SYS_statfs, ...)`, compiled for arm32 without an error, because
`SYS_statfs` became 0. The binary called syscall number 0 and reported errno 38
from `statfs("/")` — which reads exactly like a missing syscall and is really a
call to a different one. A guard that cannot fail printed PASS.

The workaround in that file is `#ifdef SYS_statfs`, a preprocessor test, which
is the one question that cannot be answered with a silent zero. That is a
correct local fix and it does not generalise: every other consumer of this
header is still written the obvious way.

## What has to land with the fix, not after it

Promoting the warning to an error is a one-line change and would immediately
break builds that pass today — which is the finding, not an objection:

- `lib/crtl/include/locale.h` has no `LC_COLLATE`, `LC_CTYPE`, `LC_MONETARY` or
  `LC_TIME`. `test-lua` and `test-lua-cross` compile lua's `loslib.c`/`lstrlib.c`
  through those four warnings on every target, today, and pass. They pass
  because lua only passes the category to `setlocale`, and crtl's `setlocale`
  ignores it — so 0 and LC_COLLATE happen to be the same program. That is luck
  with a warning printed over it.
- Whatever else a full-tier run turns up. The census is the first task: build
  the corpus and collect every `used as value` line before changing the verdict,
  because the count is the size of the job and nobody currently knows it.

## Not to be confused with

`ON PAR WITH THE LANGUAGE, NOT WITH FPC` cuts the other way here. This is not us
being stricter than a peer compiler on code someone meant to write; it is us
being LOOSER, on code that is a straightforward mistake, and silently
substituting a value the author never wrote. The source MEANT to name something
that exists.

# THE BUSYBOX CENSUS, 2026-09-04 (franks-ab, Track B)

**Eighteen constants across eleven translation units were 0 in a busybox build
that passed 621 differential cases.** Taken from the 258-applet separate
build's own log at pin v403, warning mapped to the object it precedes:

| TU | zeroed |
| --- | --- |
| `udhcp/arpping.c`, `udhcp/dhcpc.c`, `udhcp/packet.c`, `arping.c` | `ETH_P_IP`, `ETH_P_ARP` |
| `udhcp/packet.c` | `IPDEFTTL` |
| `traceroute.c` | `ICMP_TIMXCEED`, `ICMP_UNREACH`, four codes, `IP_MULTICAST_IF` |
| `arping.c` | `ARPHRD_ETHER`, `ARPHRD_FDDI`, `ARPOP_REQUEST`, `ARPOP_REPLY` |
| `unzip.c`, `chattr.c`, `lsattr.c` | `O_NOFOLLOW` |
| `telnetd.c` | `XTABS` |
| `tls_aesgcm.c` | `LONG_BIT` |
| `sv.c` | `O_NDELAY` |
| `udhcp/arpping.c` | `SOCK_PACKET` |

**None of these is a compile error and none is a run-time error either.** A
packet socket asking for protocol 0 binds to nothing and waits forever. An IP
header with `ttl` 0 is dropped by the first router — invisible on the local
wire, fatal one hop out. `O_NOFOLLOW` at 0 is a security guard silently
switched off in three applets that open attacker-named paths. `LONG_BIT` at 0
makes `tt << (LONG_BIT-1)` a **negative shift count** in the TLS GHASH.

This is the same class as the `SYS_statfs` case already written up above, at
corpus scale, and it is the argument for the priority: the ticket's own
example was one syscall on one cross target, and the real exposure is a
networking userland that compiles green and misbehaves on the wire.

## The prerequisite this ticket names is now DONE

The summary says the fix "also requires filling the crtl gaps it is currently
papering over". The busybox-sized instance of that landed 2026-09-04 in
`bb0c9c1ff`: `linux/if_ether.h` is new, the `<netinet/ether.h>` chain is the
one glibc has, and the IP/ICMP/termios/limits/socket gaps are filled, with two
tests — one diffing 248 constants against gcc, one asserting open-flag effects
on five targets. **All 39 warnings across all 11 TUs are gone and all 11 still
compile**, so promoting the warning to an error no longer breaks the busybox
corpus on x86-64 for these names.

That is not the same as "nothing else warns". The census above is what ONE
config of ONE corpus reached; `locale.h`'s `LC_COLLATE` and friends, named in
this ticket's summary, are untouched by it. **Before flipping the switch, run
the census rather than the ticket list** — `grep -c "undeclared identifier"`
over a full corpus build log is the whole instrument, and it costs one run.

# 2026-09-04 (frankC, Track C): it also blinds the TESTS THAT VERIFY crtl HEADERS

The two instances above are both a *program* naming something crtl lacks. This
one is the layer that is supposed to catch that, and it is a worse shape.

`lib/crtl/include/linux/wireless.h` was written by extracting the host header
with a script, and the extractor dropped 24 macros: `WIRELESS_EXT`, the eleven
`IWEV*` event codes, `IW_EV_POINT_LEN`, and the `IW_EVENT_CAPA_*` / `IW_IS_*`
helpers. The test written to verify that header — `test/c_crtl_uapi_wireless.c`,
which prints every macro and diffs the whole file against gcc — **named twelve
of the missing ones and compiled cleanly**, printing 0 for each. Exit code 0.

So the mechanism does not merely let a wrong program through; it lets a wrong
*header* through the instrument built to check headers. A crtl header is exactly
the population where "the identifier does not exist" is the defect under test,
and it is the one population where this compiler cannot say so.

**And 0 is a plausible value for most of these names.** `IW_IS_SET(cmd)` at 0,
`WIRELESS_EXT` at 0, an `IWEV*` event code at 0 — none is out of range, none
would look wrong in a printout, and `IWEVTXDROP` is genuinely `0x8C00` which is
also `IWEVFIRST`, so a reader checking two rows against each other finds them
consistent. Only an oracle that produces the real numbers separates them.

**What caught it, and what nearly did not.** The gcc diff caught it. Nothing
else could: the compile step was written as

    ./$(COMPILER) test/...c $(TESTTMP)/out >/dev/null

copying the pattern every other `c_crtl_uapi_*` row in the Makefile uses, and
that redirect throws away the one warning the compiler *did* print. The author
then read `ok:` as evidence the compile was clean. The diagnostic exists and is
correct; the harness around it discards it by convention.

**The cheap mitigation, landed 2026-09-04 in `0161a0be1`, and it is not a fix
for this ticket.** That row now greps its own compile output for `undeclared
identifier` and fails there. It is one row. Every other `c_crtl_uapi_*` row, and
every C test in the Makefile, still redirects the compile to `/dev/null`.

**THE SECOND CENSUS IS MEASURED, NOT PROPOSED.** It is a different question from
the census this ticket already asks for — that one counts warnings in a corpus
build; this one counts *rows of our own test suite whose compile output is
discarded*, i.e. how much of the C test surface cannot report this class at all.
Measured at `0161a0be1`:

    grep -c 'COMPILER).*>/dev/null' Makefile   ->  161
    grep -o 'COMPILER) test/[a-z0-9_]*\.c' Makefile | wc -l  ->  414

161 rows send a pxx compile to `/dev/null`. That is not 161 blind C rows — the
count spans every frontend and some of those compiles are Pascal — but it is the
right order of magnitude for "how many places would have swallowed this", and it
is 161 more than the one that now greps. Re-run both numbers before quoting
them; they are a property of the Makefile on the day.

Raising the warning to an error makes both censuses moot, which is the argument
for doing it rather than for adding greps. Until then, the ordering claim in
this ticket's summary — fill the crtl gaps first — has a corollary worth
stating: **the gaps are filled by writing headers, and the verification of those
headers is itself subject to the bug.** Every crtl header landed while this is
open needs a value-level oracle, not a compiles-cleanly check.
