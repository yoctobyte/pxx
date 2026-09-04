---
slug: feature-c-corpus-busybox-394-applets
title: "Rung 6: busybox at 394 applets — 507 of 521 TUs, and the fourteen that refuse"
track: C
prio: 60
type: feature
status: working
created: 2026-09-02
found-by: frankD
blocked-by: [feature-b-crtl-function-gaps-at-394-busybox-applets, bug-b-crtl-host-header-fallback-leaks-BEGIN-DECLS, bug-c-ir-unsupported-ast-node-kind-1-in-flash-eraseall]
summary: "**507 OF 521 TRANSLATION UNITS BECOME x86-64 OBJECTS AT 394 APPLETS**, up from 265 of 265 at 141. The gcc oracle links all 521 and agrees with the reference busybox over 893 differential cases (was 387), so the oracle is sound at this width and the remaining work is named. Fourteen refusals, and THIRTEEN OF THEM ARE crtl SURFACE GAPS, not compiler defects: ten missing functions, three files hitting one missing-header cause. The fourteenth is the only compiler finding -- an unlowerable AST node in flash_eraseall.c. The binary does not link yet, and it cannot until the fourteen are cleared, because busybox's applet table references every applet_main by name. Binary sha256 32a2ce1d9806."
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

## The fourteen

Thirteen are crtl and are ticketed as two groups —
`feature-b-crtl-function-gaps-at-394-busybox-applets` (ten missing functions)
and `bug-b-crtl-host-header-fallback-leaks-BEGIN-DECLS` (three TUs, one cause).
The fourteenth is `bug-c-ir-unsupported-ast-node-kind-1-in-flash-eraseall`.

**Do not read thirteen-of-fourteen as "the compiler is fine at this width."**
It means the compiler is fine on the 507 TUs it was *allowed to reach*. Nothing
here has run yet: the link needs all fourteen cleared, and the 893 differential
cases have only been proved against the gcc oracle, not against a pxx-built
binary. That is the next rung's claim, not this one's.

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
