---
slug: bug-c-an-undeclared-identifier-used-as-a-value-is-a-warning-not-an-error
track: C
type: bug
prio: 45
status: open
found: 2026-09-02
found-by: frankD
blocked-by: []
summary: "pxx's C frontend treats an undeclared identifier used as a VALUE as 0 with a warning, while an undeclared identifier used as a CALL is a hard error. gcc rejects both under -std=gnu99, which is what our own busybox oracle uses. The consequence is not cosmetic: crtl's <sys/syscall.h> defends itself with `naming any SYS_* here is a compile error, which is the point', and that sentence is false under this compiler. THE CENSUS THIS TICKET ASKED FOR IS DONE (2026-09-05, compiler 9048792b2dc3): 10 warnings total across conformance 220, lua, the sqlite amalgamation and 625 test/*.c, and ALL TEN are deliberate test fixtures — ZERO real gaps. THE PREREQUISITE NAMED HERE IS ALSO DONE: locale.h now defines all six LC_* categories and the lua build is clean. So the remaining work is not the corpus, it is about five fixtures that exist to exercise the leniency, plus preserving the deliberate `__`-prefix carve-out. NOT re-measured at HEAD: busybox — five attempts recorded below, each failing differently."
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

# THE CENSUS THIS TICKET ASKS FOR, RUN 2026-09-05 (frankC), compiler `9048792b2dc3`

The ticket says twice, correctly, that the census is the first task and that
nobody knows the size of the job. It is now measured for everything except
busybox, which a peer had already censused (see below).

**Total `used as value` warnings: 10. Real gaps found: ZERO.**

Instrument: every compile below keeps stderr, which is the whole point — the
ticket's second census is about the 161 Makefile rows that discard it. Script
kept at the session scratchpad; it is six `pascal26` invocations and a
`grep -o | sort | uniq -c`.

| corpus | compiles | `used as value` |
| --- | --- | --- |
| c-testsuite conformance | 220 programs, 220 pass | 0 |
| lua 5.4 core (`test/lua/runner.c`) | builds | **0** |
| sqlite amalgamation (one 9MB TU) | builds | 0 |
| `test/c_crtl_uapi_*.c` | 4 | 0 |
| every other `test/*.c` | 621 | 10 |

559 `ok:` lines in the captured log, so the instrument compiled what it claims
to have compiled rather than failing quietly.

## All ten are deliberate fixtures, named

```
      2 offset
      1 undeclared_cmp
      1 pxx_no_such_type_t
      1 UNMODELLED_MACRO_D
      1 UNMODELLED_MACRO_C
      1 UNMODELLED_MACRO_B
      1 UNMODELLED_MACRO_A
      1 SELF_REF_MACRO
      1 FORCED_BY_MINUS_INCLUDE
```

`pxx_no_such_type_t` and both `offset` lines are ONE fixture:
`test/c_ir_unsupported_reports_the_real_line.c` writes
`pxx_no_such_type_t offset = 0;`, so the undeclared TYPE makes `offset`
undeclared too. That file's header says it chose a name "crtl will never grow"
precisely because its previous fixture (`loff_t`) got fixed underneath it.

`SELF_REF_MACRO` is `test/macro_soup_lib.c`'s `#define SELF_REF_MACRO
SELF_REF_MACRO + 1`, whose stated purpose is "should not cause compiler
crash/infinite loop" — about not hanging, not about accepting.

## THE PREREQUISITE THIS TICKET NAMES IS DONE, AND NOT BY ME

The summary says the fix "also requires filling the crtl gaps it is currently
papering over (locale.h has no LC_COLLATE/LC_CTYPE/LC_MONETARY/LC_TIME, which
the lua build hits today)". **`lib/crtl/include/locale.h` now defines all six
categories** with glibc's numbers, and its own header comment documents exactly
this ticket's complaint as the reason. The lua runner builds with **zero**
`used as value` warnings. That blocker is retired.

## What this census does NOT cover, stated so nobody reads it as total

- **busybox. I TRIED TO RE-MEASURE IT AT HEAD AND FAILED; the number below is
  still franks-ab's, taken at pin v403 with a different compiler.** Their census
  found 18 constants across 11 TUs and the gaps were filled in `bb0c9c1ff`,
  which reports all 39 warnings gone. That claim is NOT re-verified at
  `9048792b2dc3`. Five attempts, each failing differently, recorded so the next
  person does not repeat them:
    1. unity build, 10 applets — gcc oracle refused: `sv.c:520: lvalue required
       as unary '&' operand`. The script builds the ORACLE first and exits, so
       pxx never ran.
    2. unity build without `sv` — gcc refused again, and this one is a genuine
       unity hazard rather than a bad applet: `traceroute.c`'s
       `#define port (G.port)` collides with a `port` PARAMETER in
       `udhcp/socket.c`. Those two applets cannot share a translation unit.
    3. `--separate`, 10 applets — GREEN, 67 objects, byte-identical to the gcc
       oracle over 45 cases. A real run. But the summary log is ten lines and
       holds no compiler output, so grepping it for `used as value` counted a
       file that never contained any.
    4. `--separate --keep` (per-TU logs land in `$WORK/tu/*.log` and survive
       only with `--keep`) — killed by the OOM killer.
    5. the same, narrowed to `arping traceroute cat` — killed again. 42 GB were
       free when measured a minute earlier, so this is transient contention
       from peers building, not a standing shortage. Stopped there rather than
       keep hammering a shared box.
  **The instrument for attempt 6 is `--separate --keep`, then
  `grep -c 'used as value' "$WORK/build_x86_64.log"` with
  `grep -c 'ok:'` beside it** — and pick an applet set that does not put
  traceroute and udhcp in one TU.
- cjson, quickjs, zlib, duktape, fgl, uforth, chess-perft: **not present** in
  `library_candidates/` on this box, so they were not compiled and not counted.
- **Cross targets.** Every number above is native x86-64. The census counts
  DIAGNOSTICS, which are emitted by the frontend before any backend runs, so a
  cross target cannot produce a warning this run did not — but that is an
  argument, not a measurement, and it is written here as one.

## What this means for the fix

The blast radius is now known and it is small: promoting the warning to an error
breaks roughly five test fixtures that exist to exercise the leniency, and
nothing else in the corpora available here.

**And gcc agrees on the fixtures.** Measured:

```c
#define SELF_REF_MACRO SELF_REF_MACRO + 1
int main(void) { int d = SELF_REF_MACRO; return d; }
```
```
gcc -std=gnu99: error: 'SELF_REF_MACRO' undeclared (first use in this function)
```

So the leniency's own stated justification in `cparser.inc` — "a best-effort
leniency for tokens a self-referential / unmodelled macro leaves behind" — is
not a behaviour gcc supports for the non-reserved case. The `__`-prefixed
carve-out beside it is a different matter and must survive any flip: that one
covers predefined-but-unmodelled `__LINE__`/`__FILE__`/`__func__`-family names
and is deliberately silent.

**The remaining work is therefore the fixtures, not the corpus** — each of the
five needs to say what it is really testing (that the compiler does not hang;
that IR_UNSUPPORTED names the right line) in a way that survives the identifier
becoming an error.

## THE BUSYBOX RE-MEASUREMENT REPORTED ZERO BEFORE IT RAN, AND THAT IS THE LESSON

The first busybox census run printed `used as value: 0` across what looked like
68 translation units. It had compiled **nothing**. `busybox_diff.sh` builds the
gcc ORACLE first and exits if that fails, and gcc refused the unity build:

```
./runit/sv.c:520:35: error: lvalue required as unary '&' operand
busybox-diff: gcc could NOT build the unity -- no oracle, so no result
```

The script said so plainly, in its own log, and the grep for `used as value`
still answered `0` — a true statement about a file containing no pxx output at
all. The discriminator was counting `ok:` lines, pxx's own per-object success
marker: **0**.

This is "a broken instrument almost always reports the NULL result" landing on
the census whose entire purpose is to count a null result. The applet list was
the fault (`sv` in a unity build), not the compiler, and the re-run drops it.

**Any future run of this census must assert that the subject compiled before
trusting a zero** — `grep -c 'ok:'` beside `grep -c 'used as value'`, and the
first number is the precondition for the second meaning anything.
