---
slug: feature-c-corpus-busybox-394-applets
title: "Rung 6: busybox at 394 applets — 521 of 521 TUs on BOTH architectures, linked, 938 cases each"
track: C
prio: 60
type: feature
status: done
created: 2026-09-02
found-by: frankD
blocked-by: [feature-b-crtl-function-gaps-at-394-busybox-applets, bug-b-crtl-host-header-fallback-leaks-BEGIN-DECLS]
summary: "**GREEN ON BOTH ARCHITECTURES 2026-09-04: 521 of 521 translation units become objects, they LINK, and each linked binary is byte-identical to a gcc oracle OF ITS OWN WIDTH over 938 differential cases.** x86-64 against `gcc`, i386 against `gcc -m32` (plus `libbb/bb_bswap_64.c`, which the 64-bit map omits because platform.h shadows it with a macro there). Binary sha256 `d65d31543bf1`, HEAD `d5b23e1cd`, one exclusive run, scope `tools/busybox-applets-394.txt`. The previous state on this ticket was 507 of 521 with fourteen refusals, all crtl surface. The second oracle is what makes the i386 half a claim rather than a coincidence: the harness had been diffing 32-bit subjects against a NATIVE gcc build, so `expr 2147483647 + 1` reported a FAIL that read exactly like a 64-bit-arithmetic defect and was `sizeof(long)` (`502f273d1`, `d5b23e1cd`). **The two oracles agree with upstream busybox`s own separately-linked binary**, so neither is a unity build agreeing with itself. What this does NOT claim: 938 cases is the harness`s transcript set and not the applet set working, and `--separate` links with gcc as the driver, so these are pxx OBJECTS in a gcc link. Per-target detail on `feature-c-corpus-busybox-i386-the-second-architecture`."
owner: frankC
---

# What the widening bought

The point of going from 141 applets to 394 was to find the next wall by
attempting the target rather than by triaging the backlog. It produced fourteen
named blockers and, unexpectedly, **three defects in the harness itself** —
each of which had to be cleared before the compiler got a turn at all.

## The harness fixes, because they gate everything above

- `44e7ea61f` — the applet-set check piped `sort` into `comm` under
  `en_US.UTF-8`, where punctuation is ignored at the primary level. `comm`
  warned to stderr and **kept merging out of step**. It reported `run-init` and
  `run-parts` as both missing and extra in one sentence; the self-contradiction
  is the only reason it was visible. This check is a GATE, so a wrong answer
  refuses a legitimate applet set and never reaches the compiler.
- `1b2c0b5dc` — every `die` cites a path under `$WORK` and the EXIT trap
  deleted `$WORK`. The one diagnostic the run produced pointed at nothing.
- `c238993b9` — the TU list was built with `\.a\([a-z_0-9]+\.o\)`, which has no
  hyphen, so `add-remove-shell.o` and `ether-wake.o` had been **silently absent
  from every run this harness has ever done**. The existing completeness guard
  could not fire because both its sides ran through that same pattern. Written
  up in `debugging-playbook.md` (`d73102d45`) as its own class.

## The fourteen — all crtl, in two tickets, not three

Re-measured 2026-09-04 (frankC), binary `75c874f301fb77c2`, HEAD `a8b606a3e`,
private tree `library_candidates/busybox-frankC`: **507 of 521, the same
fourteen files, the same fourteen messages.** Two days and a self-host
fixedpoint later, nothing drifted.

| cause | TUs | ticket |
| --- | --- | --- |
| nine missing functions/macros | 9 | `feature-b-crtl-function-gaps-at-394-busybox-applets` |
| host-header fallback leaking `__BEGIN_DECLS` | 3 | `bug-b-crtl-host-header-fallback-leaks-BEGIN-DECLS` |
| the `loff_t` typedef | 2 | same B ticket, eleventh item |

**This ticket used to say thirteen-of-fourteen with the fourteenth in the
compiler. That was wrong, and so was the split.** `flash_eraseall.c` was filed
as an unlowerable AST node and `nandwrite.c` as a missing MTD constant; both are
the missing `loff_t` typedef, proven by prepending one line and getting objects
(controls refuse, no object written). `bug-c-ir-unsupported-...` is resolved and
is dropped from `blocked-by` here.

So the corrected sentence, and it is mine and measured rather than inherited:
**all fourteen refusals at 394 applets are crtl surface; there is no compiler
defect blocking this link.**

**Do not read fourteen-of-fourteen as "the compiler is fine at this width"** —
it is the SAME caveat the thirteen-of-fourteen version carried, and clearing the
last one makes it easier to forget, not less true. It means the compiler is fine
on the 507 TUs it was *allowed to reach*. Nothing here has run yet: the link
needs all fourteen cleared, and the 893 differential cases are proved against
the gcc oracle, not against a pxx-built binary. That is the next rung's claim.

## 507 is the FLATTERED number, and the honest one is smaller

frankD's finding, verified independently on this tree because it changes the
conclusion above:

```
sys/xattr.h     x86-64  resolves from /usr/include (warning) -> dies at __BEGIN_DECLS
                i386    C include file not found
linux/jffs2.h   x86-64  resolves from /usr/include (warning)
                i386    C include file not found
```

The host-header fallback is **native-only**. Measured here: **37 distinct
headers, 59 fallback events** across this run — every one of them a TU compiled
against *glibc's* headers, carrying the host ABI, announced in a warning next to
an object file that looks exactly like success. The `__BEGIN_DECLS` group is
only the 3 where those particular glibc copies happen to spell the macro without
pulling `<sys/cdefs.h>`; the symptom **undercounts its own cause more than ten
to one**.

Two consequences worth stating plainly:

- **A refusal is a property of a (TU, target) pair, not of a TU.** `fixed on
  x86-64` is not `fixed`, and a per-target row is what closes an item. This
  count and frankD's i386 count will legitimately disagree; the disagreement is
  the finding, not an error in either.
- `flash_eraseall.c` on i386 stops at **line 1**, not line 156 — `linux/jffs2.h`
  is missing from crtl. The `loff_t` fix is correct and it is not sufficient
  there. A ticket that closed on the x86-64 row alone would close green with a
  second blocker untouched behind it.

CLAUDE.md warns that width-dependent defects hide on the 64-bit host. This is
the sharper version: here the **blind target is the default one**, so the
blindness sits inside the number everyone quotes.

## Why this stopped here — SPENT, kept because it explains the gap in the dates

**This condition no longer holds and nothing below it should be acted on.** The
shortstring overhaul it names is in `done/`
(`feature-p-implement-the-real-tyshortstring-byte-prefix-layout`), and work
resumed across tracks on 2026-09-04 — including the 374-applet run recorded
further down, which is this ticket's own. Left in place rather than deleted
because it is why this rung sat still, which the commit dates otherwise make
look like neglect.

Stated precisely, because the distinction matters and I do not have the other
half: what I can verify is that the ticket the pause was expressed in terms of
has closed and that every lane is landing again. **Whether the owner considers
the pause formally lifted is the owner's to say, not mine to infer** — which is
exactly the reasoning in the paragraph below, applied to myself.

Marked spent 2026-09-04 (frankC) after franks-ab found the same shape in rung
1's write-up: a body paragraph is OPERATIVE if a reader would act on it, and
"all tracks are paused" is the most operative sentence a ticket can carry. A
session arriving to take this rung would have stood down on a stale sentence
two screens under a summary that contradicts it.

The original, unedited:

> The owner paused all tracks: frankb-a9 holds the prio-100 shortstring overhaul,
> *"that big flip should be _last_ ... this affects our self-compile
> capability"*. The flip retypes every string in the compiler and is judged
> against the tree it lands on, so a moving tree makes its verdict meaningless
> rather than merely noisy.

The lesson under it is NOT spent and is the reason the section stays at all.

Recording one thing learned from that, because it outlives this ticket: **a
session negotiating its own exemption is how a pause becomes a suggestion.** A
narrow, well-reasoned carve-out ("docs and `lib/crtl` only — `lib/rtl` IS a
compiler build input, `lib/crtl` is not") was still the wrong move, because the
value of a pause is that it is total and every agent's carve-out is individually
defensible. A carve-out is the owner's to grant, and asking for one is not the
same as taking one.

## A pxx-built busybox LINKS and RUNS — 374 applets, 506 objects, 853 cases GREEN

Measured 2026-09-04 (frankC), binary `08f25ff41d20c98f`, HEAD `223705957`.
The fourteen refusals are all crtl and all Track B, so they are not mine to
land — but the LINK and the differential are not blocked on them. Dropping the
20 applets those fourteen TUs serve leaves 374 applets / 506 TUs:

```
ORACLE  gcc separate build, 506 objects (853 cases)
ORACLE  busybox agrees with the gcc build
PASS    x86_64  byte-identical to the gcc oracle over 853 cases
busybox-diff: GREEN
```

That is the first time this rung's claim has been proved against a **pxx-built
binary** rather than against the gcc oracle alone. The TU→applet mapping is not
1:1 and the arithmetic matters: `chpst.c` carries five applets, `hush.c` three,
`nandwrite.c` two.

## AND THAT GREEN IS THE MOST IMPORTANT NEGATIVE RESULT ON THIS TICKET

**On the very binary that produced it, `uname -a` printed `Linux` eight
times.**

```
uname --help   byte-identical to gcc   -> counted as one of the 853 PASSes
uname -a       Linux Linux Linux Linux Linux Linux Linux Linux
uname -s       Linux                   -> CORRECT, and correct for the wrong reason
```

Cause was `bug-c-offsetof-in-a-static-array-initializer-folds-to-zero-silently`
(fixed, `62463923f`): busybox walks `struct utsname` through a static
`offsetof` table, the table was truncated to one element, and every field read
offset 0 — which IS `sysname`. So the broken value and the true value coincide
on exactly the field a probe reaches for first.

**The corpus was green because of what it runs, not despite the bug.** 516 of
its 621 cases were `applet --help`, twice per applet, and `--help` prints a
string literal. franks-ab raised this as a structural concern from a 258-applet
boot; this run is the measurement behind it, and it is the stronger
demonstration because it is **wider, greener, and equally blind**. Going 141 →
258 → 374 applets moves along an axis this entire defect class is invisible
from.

**So the ranking is settled and it is not a matter of taste: "more applets" and
"applets with real arguments" are not comparable in value.** 506 objects and
853 green cases did not see a miscompiled core utility; one invocation with a
real argument found it. frankD has since landed a real-argument case group
(`d0104ec8e`) which reds on exactly this — the right response, and the reason
the count of green cases is not the number to optimise.

Rung 3's write-up should cite THIS measurement rather than the 258-applet one.


## Real ARGUMENTS found two silent miscompiles that 516 `--help` cases could not

frankD, 2026-09-04. `tools/busybox_diff.sh` grew `run_realargs_cases()` — the
applets run against real fixtures rather than asked to print their usage. Two
divergences on x86-64, both silent, both now fixed:

**`uname -p` printed `uu` and `-i` printed `u`** (`67708bbe8`). uname.c declares
`char processor[sizeof(((struct utsname*)NULL)->machine)]` twice; `sizeof` of an
array field reached through a *parenthesised* base answered the ELEMENT size, so
the info struct came out 402 bytes instead of 530 with three fields at
consecutive offsets and each `strcpy` wrote through its neighbours. `sizeof(x.m)`
was right and `sizeof((p)->m)` was wrong — **a parenthesis decided the answer**.

**`sed 's/dogs/cats/'` SIGSEGV'd on any line that actually substituted**
(`f9cd0039c`). `f(s.arr)` on an array-of-struct field passed the address of a
one-element temp copy instead of decaying, so sed's `regexec(..., G.regmatch, 0)`
filled a temp nobody read; the match offsets came back 0/0 for a match at 14..18.
crtl's `regexec` is byte-identical to glibc in isolation on 9/9 rows, and every
`sizeof` and offset in the program is correct — the argument was simply a
different object. Latent because the temp path only fires for a record element
over 8 bytes, so `char[]`, `int[]`, `double[]` and `int[][]` fields were all fine.

**Both are wrong-VALUE bugs with no diagnostic, and neither is reachable by
asking a program to print its usage.** The applet-listing and `--help` cases
exercise argument parsing and little else; the first fixture with a digit in it
found one and the first substitution found the other. That is an argument about
coverage shape rather than coverage size — the 894th `--help` case would not
have found either.

## 2026-09-04 — the fourteen cleared, and the run went green

Binary `b425f312fffff6bc1ce243c7074f945f75e0ae9ff91608cb830a273b64741b36`,
HEAD `e71eaf4e8`, `tools/busybox_diff.sh --separate --applets "$(cat
tools/busybox-applets-394.txt)"`:

```
ORACLE  gcc separate build, 521 objects
ORACLE  busybox agrees with the gcc build
PASS    x86_64   521 objects linked separately
PASS    x86_64   byte-identical to the gcc oracle over 938 cases
```

**The link is the part that had never run.** The fourteen refusals were not
fourteen independent failures to be counted down — busybox's applet table
references every `*_main` by name, so the link could not be attempted at all
until the last one cleared. The 938 cases are therefore the first evidence on
this ticket about a **pxx-built binary** rather than about the oracle: every
earlier number here (893 cases at 507 TUs) was gcc agreeing with upstream, which
is a statement about the harness being sound and not about the compiler.

**What this row does NOT say.** It does not say the compiler is correct at 394
applets in general: 938 cases is what the harness's transcript set covers, and
byte-identical output on those cases is a much narrower claim than the applet
set working. And it says nothing at all about any target but this one — see the
next section, which was written before this run and is unchanged by it.

## 2026-09-04, later — the i386 half, and the caveat this ticket has carried since it opened

The section above closed the x86-64 row and repeated the standing warning that
**521 is the flattered number**, because the host-header fallback is
native-only. That caveat is now discharged rather than merely restated:

```
PASS    x86_64   byte-identical to the gcc oracle over 938 cases
PASS    i386     byte-identical to the gcc -m32 oracle over 938 cases
```

One run, binary `d65d31543bf1`, HEAD `d5b23e1cd`. Every TU that x86-64 was
allowed to reach by borrowing a host header, i386 now reaches by having the
header. **A refusal is a property of a (TU, target) pair and both members of
every pair are now green at this scope.**

It also cost the harness a defect. The i386 leg's first fully-built run
reported 937 of 938 and the one difference was `expr 2147483647 + 1`, which is
`sizeof(long)` and not a compiler bug — the oracle was built natively. A rung
whose last blocker is its own measuring device is worth recording as such,
because that FAIL is indistinguishable from the most alarming thing it could
have been.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
