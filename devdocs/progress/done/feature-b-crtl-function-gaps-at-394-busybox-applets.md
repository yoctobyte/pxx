---
slug: feature-b-crtl-function-gaps-at-394-busybox-applets
title: "crtl is missing nine POSIX/GNU functions plus the loff_t typedef that busybox calls at 394 applets"
track: B
prio: 55
type: feature
status: done
created: 2026-09-02
found-by: frankD
summary: "**THE CRTL SURFACE IS LANDED AND DIFFED AGAINST GLIBC (2026-09-04, franks-ab). THIRTEEN FUNCTIONS, NOT NINE.** loff_t landed earlier in 0e439aaf5. The nine the checklist named -- acct, mlock, scandir, ether_hostton, IN_MULTICAST, pause, nice, sched_getscheduler, sigisemptyset -- plus FOUR SIBLINGS the same TUs call within fifty lines: munlock (hdparm.c:1559, fifty-two lines after the mlock at :1507), alphasort (tree.c:43 passes it AS scandir's comparator), sched_getparam and sched_setscheduler (chrt.c:175 and :199, either side of the getscheduler at :154). **The count of nine was a count of FILES, not of functions** -- a refusal stops a TU at its FIRST undeclared identifier, so shipping the nine would have moved each refusal a few lines down its own file and produced nine more refusals. All thirteen are in `test/c_crtl_busybox_394_gaps.c`, eleven rows byte-identical to `gcc -D_GNU_SOURCE`, relations wherever root/RLIMIT_MEMLOCK//etc/ethers would change a literal. `make lib-test` green against stable v403; crtl-reachability and the regenerated crtl_names.inc both pass. **DONE 2026-09-04, CORPUS-CONFIRMED ON BOTH TARGETS BY TWO INSTRUMENTS THAT FAIL DIFFERENTLY.** frankC ran 394 applets `--separate` at binary `89a8cbcae23f3dcc` / HEAD `41a2d59a8`: ZERO refusals name any of the nine or `loff_t`, x86-64 or i386; x86-64 went 14 -> 3 refusals (all three `__BEGIN_DECLS`) and i386 has 16 (12 headers, 4 inline-asm, NO function gaps), so the two targets no longer share a failure population. That list is FIRST-REFUSAL-PER-UNIT and therefore a lower bound -- a gap inside any of the sixteen still-refusing i386 TUs could not appear in it -- so franks-ab added a header-clean TU touching all fourteen entries that CANNOT refuse on a header, under the PIN `c31d03b202da` rather than frankC's binary: x86-64 compiles, links and runs; the i386 object DEFINES all fourteen at real addresses rather than importing them; and the positive control (one absent name) refuses with exit 1 and writes no object. Two findings came out of the work: ether_line REJECTS a leading blank in glibc (measured across eleven line shapes, crtl now matches byte for byte), and crtl's signal/sigaction are link-only stubs that return 0 and install nothing (bug-b-crtl-signal-and-sigaction-report-success-and-install-nothing), which is why the pause() row tests blocking rather than a handler."
owner: franks-ab
---

# The list, with the file that wants each

Measured 2026-09-02, busybox 1.36.1, 394 applets, 521 TUs, binary sha256
`32a2ce1d9806`. The gcc oracle links all 521 and agrees with the reference
busybox over 893 cases, so the oracle is sound at this width.

| function | header it belongs in | busybox TU |
| --- | --- | --- |
| `acct` | `unistd.h` | `init/bootchartd.c:230` |
| `mlock` | `sys/mman.h` | `miscutils/hdparm.c:1507` |
| `scandir` | `dirent.h` | `miscutils/tree.c:43` |
| `ether_hostton` | `netinet/ether.h` | `networking/ether-wake.c:134` |
| `IN_MULTICAST` | `netinet/in.h` (a macro) | `networking/libiproute/iptunnel.c:349` |
| `pause` | `unistd.h` | `procps/mpstat.c:726` |
| `nice` | `unistd.h` | `runit/chpst.c:469` |
| `sched_getscheduler` | `sched.h` | `util-linux/chrt.c:154` |
| `sigisemptyset` | `signal.h` (GNU) | `shell/hush.c:2126` |
| ~~an MTD ioctl constant~~ **WRONG — see below** | — | `miscutils/nandwrite.c:106` |

`nandwrite.c` is the one worth reading before starting, and **the reason is now
the opposite of what this paragraph used to say.** It read:

> the diagnostic is *"undeclared identifier passed as argument 3 of
> `bb_xioctl`, where a pointer is expected"*, i.e. an undeclared identifier
> silently became 0 and the frontend caught it at the call. That guard is doing
> exactly its job; the missing thing is the constant, not the check.

The first half is right and the conclusion is wrong. **`MEMGETBADBLOCK` is
already defined** — `lib/crtl/include/mtd/mtd-abi.h:152` — and it is argument
**2**. The message said argument **3**, which is `&offs`, and `offs` is
undeclared because its declaration one line up is `loff_t offs;` and `loff_t`
does not exist. Same cause as flash_eraseall.c; see the eleventh item.

Worth keeping as a worked example rather than just deleting: nothing here
errored and nothing was sloppy. The diagnostic was PRECISE — it named the
argument index — and the reading substituted the argument a human eye lands on,
the shouty ioctl constant, for the one the compiler actually named. An
identifier standing in for the thing it names, believed because the sentence
around it was true.

`IN_MULTICAST` is a macro rather than a function and is reported as a call
because that is what an undeclared identifier followed by `(` looks like.
Do not go looking for a symbol to link.

## Scope note

This is the crtl **surface**, not its semantics. Each entry needs a declaration,
an implementation, and a row in a differential test against glibc — the pattern
`lib/crtl/src/regex.c` and `test/c_crtl_regex.c` established. `hush.c` is the
one whose applet is worth the most on its own (`hush` is a shell), and
`sigisemptyset` is its only blocker at this scope.


## ELEVENTH ITEM — the `loff_t` typedef (frankC, 2026-09-04)

**This one closes TWO of the fourteen refusals, and neither was filed as a
typedef.** One was filed as a C-frontend lowering gap
(`bug-c-ir-unsupported-ast-node-kind-1-in-flash-eraseall`) and is not one; the
other was filed in the table above as a missing MTD constant and is not one.
**All fourteen refusals at 394 applets are crtl surface, and nine of them are
what this ticket's checklist actually has left.**

One missing typedef, two TUs, and **three message shapes that share no
vocabulary** — which is the whole reason it was filed twice under two wrong
causes:

| TU | what the run printed |
| --- | --- |
| `flash_eraseall.c:156` | `IR_UNSUPPORTED: frontend could not lower AST node (kind 1) — a frontend gap, would miscompile` |
| `nandwrite.c:106` | `undeclared identifier passed as argument 3 of 'bb_xioctl', where a pointer is expected` |
| both | `warning: undeclared identifier 'loff_t' used as value (treated as 0)` |

The warning is the only one that names the cause, and it is a warning, sitting
above an error that blames the frontend. **Nobody was careless here: the loudest
line accused the compiler and the quiet line was right.**

crtl declares `__kernel_loff_t` (`lib/crtl/include/linux/types.h:39`) but not
`loff_t`, which glibc provides from `<sys/types.h>` as a GNU extension. So
`miscutils/flash_eraseall.c:156`

```c
loff_t offset = erase.start;
ret = ioctl(fd, MEMGETBADBLOCK, &offset);
```

is not parsed as a declaration at all. `loff_t` becomes an undeclared identifier
`treated as 0`, `offset` likewise, and `&offset` is then the address of an
integer literal — which the IR cannot lower, correctly.

**The fix, and it is proven rather than proposed:**

```c
typedef long long loff_t;      /* alongside the existing __kernel_loff_t */
```

Prepending exactly that to the busybox wrapper — nothing else changed — turns
the refusal into a **502192-byte object, rc=0, zero IR_UNSUPPORTED**.

**Re-run 2026-09-04 at binary `9c38c57228f289e2`, both TUs, with controls**, so
this is not a one-file result and not one that expired with the binary that
produced it:

| wrap | control (unmodified) | probe (typedef prepended) |
| --- | --- | --- |
| `miscutils_flash_eraseall.c` | refuses, `IR_UNSUPPORTED` at :156, **no object written** | `ok`, 496704 B |
| `miscutils_nandwrite.c` | refuses, argument-3 error at :106, **no object written** | `ok`, 500160 B |

The control column is the point: it is drawn from the same population, it
refuses for the *same* message the 394-applet run recorded, and it leaves no
object behind — so the probe's `ok` cannot be a stale artifact of an earlier
build. The two object sizes also differ from each other and from the 502192 B
above, which is what a real compile of three different inputs looks like.

**Width note, because this is the class that is invisible on x86-64:**
`__kernel_loff_t` is `long long` on *every* architecture, deliberately — see
`lib/crtl/include/mtd/mtd-abi.h:14`, *"MEMGETBADBLOCK TAKES A __kernel_loff_t —
64 bits on EVERY architecture"*. So `loff_t` must be `long long`, **not** `long`
or `off_t`: on i386 the latter two are 32 bits and the ioctl would read half an
argument. Whoever takes this should put it where `__kernel_loff_t` already is,
or define it in terms of it, rather than picking a width at the new site.

Not fixed here: `lib/crtl` is B's lane and this was found from C. Filed rather
than fixed on frankuser's explicit routing.

## LANDED 2026-09-04: the loff_t item, with its per-target rows (frankD, `0e439aaf5`)

`typedef long long loff_t;` in `lib/crtl/include/sys/types.h`. Measured on the
real busybox TUs at binary sha256 `08f25ff41d20`, not on the reduction:

| target | `flash_eraseall.c` | `nandwrite.c` |
| --- | --- | --- |
| x86-64 | **compiles** (30 objects linked, no refusals) | **compiles** |
| i386 | still refuses — `linux/jffs2.h` not found | **compiles** |

**This is the (TU, target) claim measured rather than predicted.** One typedef
clears two TUs on x86-64 and one on i386, and `flash_eraseall` on i386 has a
second, independent blocker that belongs to
`bug-b-crtl-host-header-fallback-leaks-BEGIN-DECLS`. Closing this item on the
x86-64 row alone would have closed it green with that blocker untouched.

`long long`, never `long` or `off_t`: MEMGETBADBLOCK carries the width in its
ioctl NUMBER via `_IOW`, so a narrower spelling compiles everywhere and issues
a different request on every ILP32 target. Asserted as a RELATION in row 16 of
`test/c_crtl_mtd_timex_kd_caps.c` (`sizeof(loff_t) == sizeof(long long)`), so it
carries no per-target constant; all 16 rows are byte-identical to
`gcc -D_GNU_SOURCE`.

One oracle note for whoever diffs this next: **glibc gates `loff_t` behind
`__USE_MISC`**, so a plain `gcc` build cannot see it and the row needs
`-D_GNU_SOURCE`. crtl defines it unconditionally — the accept-more direction,
and unobservable to a program that does not use the type.


## LANDED 2026-09-04: the crtl surface, thirteen functions (franks-ab)

**Nine became thirteen before a line was written, and the reason is the ticket's
own method rather than a mistake in it.** The list was built from compiler
refusals, and a refusal stops a translation unit at its FIRST undeclared
identifier. Nine refusals across nine TUs therefore counted nine FILES. Reading
what those files actually call:

| shipped | sibling the SAME TU calls | distance |
| --- | --- | --- |
| `mlock` (hdparm.c:1507) | `munlock` (hdparm.c:1559) | 52 lines |
| `scandir` (tree.c:43) | `alphasort` — passed AS its comparator | same line |
| `sched_getscheduler` (chrt.c:154) | `sched_getparam` :175, `sched_setscheduler` :199 | same function |

Shipping the nine would have cleared nine refusals and produced nine more, one
per file, and the ticket would have looked half-done twice.

### Where each body went, and why it is checkable

crtl auto-pulls `lib/crtl/src/<name>.c` when `<name>.h` resolves, so a body in
the wrong file links against **glibc's** symbol instead — right name, not
necessarily the same ABI. `tools/crtl_reachability.py` asserts the rule and is
the first thing `make lib-test` runs; it passes (125 headers, 60 modules).
`compiler/crtl_names.inc` is generated and was regenerated (558 functions).

- `unistd.h`/`src/unistd.c` — `acct`, `pause`, `nice`
- `sched.h`/`src/sched.c` — `sched_getscheduler`, `sched_setscheduler`, `sched_getparam`
- `sys/mman.h`/`src/sys/mman.c` — `mlock`, `munlock`
- `dirent.h`/`src/dirent.c` — `scandir`, `alphasort`
- `netinet/ether.h`/`src/netinet/ether.c` — `ether_line`, `ether_hostton`, `ether_ntohost`
- `netinet/in.h` — `IN_MULTICAST` (macro, via `IN_CLASSD`)
- `signal.h`/`src/signal.c` — `sigisemptyset`

### Three decisions that are not obvious, recorded so they are not re-litigated

**`pause` on aarch64 and riscv is `ppoll`, not `ENOSYS`.** Those targets have no
`SYS_pause` — the kernel dropped it from the generic table — so the
`#ifdef SYS_x / #else ENOSYS` idiom this repo uses everywhere else would have
refused on two live targets. glibc's answer is `ppoll(NULL,0,NULL,NULL)` and
both have `SYS_ppoll`. The real syscall is still preferred where it exists, so
an x86-64 strace says `pause`.

**`nice` re-reads and DIVERGES FROM GLIBC deliberately.** glibc returns
`old + inc` without looking, so `nice(100)` reports 119 while the process sits
at 19 — the kernel clamped and glibc did not check. POSIX says nice() returns
the new nice value; this re-reads it. They agree for every increment that does
not hit a clamp, which is every call in the corpus, and disagree only where
glibc's answer is untrue. `EACCES` is remapped to `EPERM` per nice(2).

**`ether_line` REJECTS a leading blank, and that is measured, not assumed.**
Eleven line shapes probed against glibc: leading whitespace `-1`, comment-only
`-1`, address-with-no-host `-1` **but with the address still written through**,
double separators / tabs / trailing blanks / trailing newline / trailing
comment all accepted, short hex components accepted. crtl now matches glibc on
all eleven, byte for byte. The first implementation skipped leading blanks —
the tolerant direction — and that was wrong here: an indented line resolving to
a MAC address under pxx and nothing under every other libc is the wrong
divergence for a lookup whose whole job is to agree with the rest of the system.

### The test, and the one thing it cannot assert yet

`test/c_crtl_busybox_394_gaps.c`, eleven rows, byte-identical to
`gcc -D_GNU_SOURCE`. Rows are RELATIONS wherever root, `RLIMIT_MEMLOCK` or the
presence of `/etc/ethers` would change a literal, and constants where they can
be. Row 5 asserts scandir's ORDER as well as its count, so returning readdir
order fails it; row 6 asserts the caller's sentinel SURVIVES a failed scandir.

**Row 10 is weaker than it should be and the reason is filed.** `pause` has no
success return, so the natural test is a handler plus `alarm(1)` — which passes
under gcc and, under pxx, kills the process with `Alarm clock`. crtl's
`signal`/`sigaction` are link-only stubs that return 0 and install nothing:
[[bug-b-crtl-signal-and-sigaction-report-success-and-install-nothing]]. The row
therefore asserts that `pause()` BLOCKS (fork, confirm the child is alive, kill
it). **Strengthen it when that lands** rather than leaving it weak because
nobody remembers why.

### Independently differentialled, and one half is NOT covered

frankD ran their own glibc oracle over `ether_line` after throwing away a draft
of the same three functions (a topic collision neither of us could see; this
landed first). **11/11 rows byte-identical**, including the two a reasonable
implementation gets wrong: the leading-blank refusal, and the partial-octet
write on the refusal path. Their draft would have differed on the second —
it stored each octet before checking the separator, which leaves different
bytes in a struct the caller may inspect after -1.

That is now **row 12**, and it is there because a comment would not have held:
`ether_aton_r`'s store sits after its separator check, which reads as tidiness
and is observable. Positive control run rather than asserted — hoisting the
store changes row 12 and leaves **every accepting row in row 3 unchanged**, so
before row 12 existed the "tidy-up" would have shipped silently. Restore
verified byte-identical with `cmp`.

**The FILE half is not covered and the ticket should not imply it is.**
`/etc/ethers` does not exist on either machine and creating it needs root, so
both libcs answer -1 for every input and row 4 would pass against a lookup that
never opened the file. The parser is fully covered; the scan is fifteen lines
of fopen/fgets/compare on top of it, and it is **unverified, not
verified-by-omission**. Closing that needs a root-created `/etc/ethers` or a
container. frankD hit the same wall independently, so this is a property of the
environment rather than of either measurement.

### Not closed, and deliberately

The acceptance here is the nine busybox TUs COMPILING, per target. That needs a
394-applet run on x86-64 **and** i386 — the ticket's own note says the
host-header fallback is native-only, so i386 refuses more — and that run is
frankc-af's, not mine. Closing on "the surface is landed and the unit test is
green" would be closing on my own half.

## ACCEPTANCE — measured by frankC, 2026-09-04. The function gaps PASS.

Binary `89a8cbcae23f3dcc`, HEAD `41a2d59a8`, 394 applets, `--separate`, both
targets. **This measures 41a2d59a8 and NOT current HEAD**: frankD landed two
miscompile fixes and seven UAPI headers after the run's compiler snapshot was
taken, so the refusal sets below have already moved.

**Every one of the nine function refusals is cleared, on BOTH targets**, and so
are the two `loff_t` TUs. Checked against refusal lines only — a plain grep for
`nice` matches the applet name in the run's own `applets=` line and reports it
as still refusing:

```
acct  mlock  scandir  ether_hostton  IN_MULTICAST  pause  nice
sched_getscheduler  sigisemptyset  loff_t            -- 0 refusals, x86-64 and i386
```

| target | refusals | what is left |
| --- | --- | --- |
| x86-64 | **14 -> 3** | all three are `__BEGIN_DECLS` (`bug-b-crtl-host-header-fallback-leaks-BEGIN-DECLS`) |
| i386 | **16** | 12 missing headers, 4 inline-asm; **no function gaps at all** |

518 of 522 TUs on x86-64, 506 on i386.

**The two targets no longer share a failure population**, which is the useful
half. x86-64's remaining three are one cause; i386's sixteen are headers the
native fallback used to hide, plus the inline-asm ticket. Nothing on either
list is a missing function, so this ticket's own subject is finished and the
residue belongs to the two header tickets.

**Two counting notes, because both cost me a wrong number first.**

`521` is the **gcc oracle's** object count and `522` is the **pxx TU list**;
mixing them makes every arithmetic check off by one. Reconciled: 522 - 16 = 506
on i386, exactly.

x86-64 shows 518 + 3 = 521, one short of 522, and that one is **correct**:
`libbb/bb_bswap_64.c` is `#if !(ULONG_MAX > 0xffffffff)`, so on a 64-bit target
it is an EMPTY translation unit — no object and no error is the right outcome,
not a silently dropped TU. On i386 it builds and defines the symbol.

**One anomaly I could not explain, handed to frankD rather than guessed at:**
on i386 the link reports 6 `undefined reference to bb_bswap_64` while
`obj/libbb_bb_bswap_64.o` exists, is `ELF32 80386`, and defines `T
bb_bswap_64` — and the link is a plain glob over `obj/*.o`. I checked and
discarded the obvious explanation (a mixed-architecture object set left over
from the x86-64 pass: every object in the directory is ELF32). The i386 link
cannot succeed anyway while 16 TUs refuse, but this would still be there after
they are fixed.


## CONFIRMED INDEPENDENTLY, AND THE SECOND READING WAS NOT REDUNDANT — franks-ab, 2026-09-04

frankC's acceptance above is a **first-refusal-per-unit** list, which this
ticket's own body spends a section explaining is a **lower bound on every
axis**. That property does not stop applying because the news is good. Sixteen
i386 TUs still refuse on headers, and **a function gap inside any of those
sixteen is structurally invisible to a refusal list** — the TU stopped at its
header and never reached the call. "Zero refusals mention the nine" is
therefore a true statement about the TUs that got far enough to mention them.

So the second reading was chosen to **fail differently**: one header-clean TU,
`scratchpad/thirteen.c`, that touches all fourteen entries (the thirteen plus
`alphasort`) and **cannot refuse on a header**, so it can only refuse on a
function. Pinned v403 `c31d03b202da`, both targets, at HEAD `733b32712`:

| target | result |
| --- | --- |
| x86-64 | compiles, LINKS and RUNS — `THIRTEEN-LINKED 1` |
| i386 | `--emit-obj` writes an `ELF 32-bit LSB relocatable, Intel 80386` |

**And the i386 object DEFINES all fourteen rather than importing them** —
`nm` gives a `W` at a real address for every one (`acct` `0006ef9e`, `pause`
`0006f0fa`, `nice` `0006f1e2`, `sched_getscheduler` `00070ab8`,
`sched_getparam` `00070e55`, `sched_setscheduler` `00070c13`, `mlock`
`000717e0`, `munlock` `000719b0`, `alphasort` `00072861`, `scandir`
`00072f7e`, `sigisemptyset` `0007ee9b`, `ether_line` `00088d2c`,
`ether_hostton` `00089f16`, `ether_ntohost` `0008a06d`). That distinction is
the point of looking: `--emit-obj` tolerates undefined symbols, so "the i386
object was written" would have been satisfied by declarations alone. Weak is
expected — the crtl runtime is exported `W` by design (`243137302`).

**Positive control**, because a guard that cannot fail prints PASS: the same
compiler, same target, same flags, on a TU calling one name crtl does not have
answers `error: call to undeclared function: pxx_no_such_crtl_entry_zzz`,
exits **1**, and writes **no object**. The probe is able to refuse.

**Note the compiler differs from frankC's on purpose.** Theirs was built at
`41a2d59a8`; mine is the pin, `c31d03b202da`, which predates every line of this
work — so the two readings share no binary, no target selection path and no
instrument. The pin resolving these functions is itself the fact that matters:
they are lib/crtl SOURCE the compiler reads at compile time, not a table baked
into it, which is why an older compiler can consume them at all.

**RESOLVED.** Every entry in the table at the top of this ticket is landed,
diffed against glibc, and now confirmed to compile on both targets by two
instruments that fail differently.

**What is NOT closed by this, and belongs elsewhere:** x86-64's three
`__BEGIN_DECLS` refusals and i386's twelve headers plus four inline-asm are the
two header tickets' residue. frankC's `bb_bswap_64` anomaly on the i386 link is
frankD's, by frankC's own routing. And row 4's `/etc/ethers` FILE SCAN remains
unverified in both directions — the file needs root to create, so both libcs
answer -1 and the row would pass a lookup that never opened it. That is
recorded in the test and the Makefile as an uncovered path, not as coverage.
