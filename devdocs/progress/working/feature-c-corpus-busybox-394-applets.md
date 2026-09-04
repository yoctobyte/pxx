---
slug: feature-c-corpus-busybox-394-applets
title: "Rung 6: busybox at 394 applets — 507 of 521 TUs, and the fourteen that refuse"
track: C
prio: 60
type: feature
status: working
created: 2026-09-02
found-by: frankD
blocked-by: [feature-b-crtl-function-gaps-at-394-busybox-applets, bug-b-crtl-host-header-fallback-leaks-BEGIN-DECLS]
summary: "**507 OF 521 TRANSLATION UNITS BECOME x86-64 OBJECTS AT 394 APPLETS**, up from 265 of 265 at 141, and RE-MEASURED 2026-09-04 at binary 75c874f301fb77c2 / HEAD a8b606a3e: same 507, same fourteen, so the set is stable across two days of commits. The gcc oracle links all 521 and agrees with the reference busybox over 893 differential cases, so the oracle is sound at this width. **ALL FOURTEEN REFUSALS ARE crtl SURFACE AND NONE IS A COMPILER DEFECT** -- corrected from `thirteen of fourteen`: the flash_eraseall IR_UNSUPPORTED was root-caused to the missing `loff_t` typedef, and so was nandwrite`s `argument 3` error, so nine missing functions + three __BEGIN_DECLS TUs + two loff_t TUs = fourteen. The binary does not link yet and cannot until all fourteen clear, because busybox`s applet table references every applet_main by name; the link RED is that same fourteen counted once more, not an independent failure. **507 IS THE FLATTERED NUMBER**: 37 distinct headers resolve from the HOST system on x86-64 and would be `not found` on i386, so this row closes PER-TARGET and `fixed on x86-64` is not `fixed`."
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

