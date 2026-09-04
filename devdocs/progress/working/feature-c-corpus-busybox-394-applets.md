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

## Why this stopped here

The owner paused all tracks: frankb-a9 holds the prio-100 shortstring overhaul,
*"that big flip should be _last_ ... this affects our self-compile capability"*.
The flip retypes every string in the compiler and is judged against the tree it
lands on, so a moving tree makes its verdict meaningless rather than merely
noisy.

Recording one thing learned from that, because it outlives this ticket: **a
session negotiating its own exemption is how a pause becomes a suggestion.** A
narrow, well-reasoned carve-out ("docs and `lib/crtl` only — `lib/rtl` IS a
compiler build input, `lib/crtl` is not") was still the wrong move, because the
value of a pause is that it is total and every agent's carve-out is individually
defensible. A carve-out is the owner's to grant, and asking for one is not the
same as taking one.
