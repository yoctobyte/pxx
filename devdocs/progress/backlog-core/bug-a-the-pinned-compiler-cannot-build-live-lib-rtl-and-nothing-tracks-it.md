---
slug: bug-a-the-pinned-compiler-cannot-build-live-lib-rtl-and-nothing-tracks-it
title: "`gate.sh quick`'s `pinned builds live lib/rtl` row has been RED for hours with no ticket behind it, and only a pin clears it"
track: A
type: bug
prio: 60
status: backlog
found: 2026-09-06
found-by: frank-coordinator (announced the red to the fleet), frankD (confirmed no artefact existed, and that its own diff is not the cause)
summary: "The PINNED compiler cannot compile `lib/rtl/mimic_string` or `mimic_urllib_request`: `undefined variable (pyvar_is_objtag)` / `(pyvar_is_inttag)`. A commit added a builtin and used it from `lib/rtl` without a pin, which is the documented shape. A compiler built from HEAD compiles all 54 units cleanly, so nothing in the tree is broken — the pin is behind the source it has to build. Every `$(PXX_STABLE)` consumer carries it, so Track B and E build against a compiler that cannot build the RTL they depend on. NOT DISPATCHABLE as coded work: `make pin` is owner-only and no agent may run it. This ticket exists so the red has an artefact and a date rather than living in whichever session last ran the gate."
---

## The measurement

`tools/gate.sh quick`, 2026-09-06, on a tree at `bb28cd97c` and again after the
rebase, reported by frankD while landing an unrelated Track P fix:

```
gate: RED — 16 rows pass, 1 FAIL
FAIL  pinned builds live lib/rtl
      lib/rtl/mimic_string.pas          undefined variable (pyvar_is_objtag)
      lib/rtl/mimic_urllib_request.pas  undefined variable (pyvar_is_inttag)
```

**The same canary reports that a compiler built from THIS TREE compiles all 54
units cleanly.** So the tree is fine and the pin is behind it.

## Why it is nobody's fix but the owner's

`pyvar_is_objtag` / `pyvar_is_inttag` are builtins that landed in `compiler/**`
and were then used from `lib/rtl`. The pinned binary predates them, so it cannot
see them. **`lib/rtl` is a compiler build input**, which is why this row exists
at all.

The canary's own remedy is a pin. **`make pin` is owner-only** (CLAUDE.md, *Asking
the owner is the expensive path* — irreversible or outward-facing acts). No agent
may run it, no agent may ask a peer to run it, and there is no code change that
clears the row.

**This is NOT DISPATCHABLE — do not claim it.** There is nothing to implement.
What it needs is the owner, and what this ticket provides is the record.

## What it costs while it stands

- **Every `$(PXX_STABLE)` consumer.** Tracks B and E build with the pinned
  compiler by rule and never rebuild one, so they are building against a compiler
  that cannot compile the RTL their programs link.
- **Every `gate.sh quick` run in every lane is RED**, for a reason that has
  nothing to do with the diff under test. A standing red that everyone learns to
  step over is a red that will hide the next real one — and the correct reading
  (*"not mine, the canary says so"*) has to be re-derived by every session that
  sees it.
- CLAUDE.md's precedent: **a red is a reason to pin SOONER, not later.** The last
  time reds were treated as a reason to withhold a pin it held for 19 days, and
  v398 shipped a compiler that could not build C for i386 or arm32.

## What it is NOT

Not frankD's `bb7b59911` — zero `lib/` files in that diff, the pinned binary
predates the edits, and the FPC seed canary passed on the same run. Any session
seeing this row should check its own diff for `lib/` and then stop looking.

**Resolve this by recording the pin that cleared it**, not by a code change. If a
later pin lands for other reasons and the row goes green, close it and say which
pin did it — the interesting fact is the interval, not the fix.
