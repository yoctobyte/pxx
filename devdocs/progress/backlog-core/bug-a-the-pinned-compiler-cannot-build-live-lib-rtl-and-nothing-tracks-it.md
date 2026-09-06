---
slug: bug-a-the-pinned-compiler-cannot-build-live-lib-rtl-and-nothing-tracks-it
title: "`gate.sh quick`'s `pinned builds live lib/rtl` row has been RED for hours with no ticket behind it, and only a pin clears it"
track: A
type: bug
prio: 60
status: backlog
found: 2026-09-06
found-by: frank-coordinator (announced the red to the fleet), frankD (confirmed no artefact existed, and that its own diff is not the cause)
summary: "The PINNED compiler cannot compile `lib/rtl/mimic_string` or `mimic_urllib_request`: `undefined variable (pyvar_is_objtag)` / `(pyvar_is_inttag)`. A commit added a builtin and used it from `lib/rtl` without a pin, which is the documented shape. A compiler built from HEAD compiles all 54 units cleanly, so nothing in the tree is broken — the pin is behind the source it has to build. Every `$(PXX_STABLE)` consumer carries it, so Track B and E build against a compiler that cannot build the RTL they depend on. NOT DISPATCHABLE as coded work: `make pin` is owner-only and no agent may run it. This ticket exists so the red has an artefact and a date rather than living in whichever session last ran the gate. IT IS NOT ONLY `gate.sh quick`: Track T's newest FULL tier at `b77ac29` (2026-09-06T04:08:52Z) is RED with `lib-test#src:tools/crtl_reachability.py` failing on those same two identifiers, so the fleet's headline verdict carries it too. The non-ancestry is measured, not inferred: the fix is frankZ's `8374118ec` (2026-09-05 23:15) and pin v404 is `8844c8c42` (2026-09-05 20:17), three hours EARLIER -- `git merge-base --is-ancestor 8374118ec 8844c8c42` is false, so no pin carries it and no amount of rebuilding at HEAD will change that."
---

## 2026-09-06 04:20Z (frank-coordinator) — measured, and the blast radius is wider than the gate

Re-measured rather than re-quoted, because the seat that filed this is a reader and a reader has no
staleness signal:

    git merge-base --is-ancestor 8374118ec 8844c8c42   ->  false

`8374118ec` (frankZ, 2026-09-05 23:15, *"export pyvar_is_inttag/pyvar_is_objtag — two lib/rtl units
call them and could not compile"*) is **not an ancestor of pin v404** (`8844c8c42`, 2026-09-05
20:17). The fix postdates the pin by three hours. Nothing at HEAD is broken and nothing built from
HEAD reproduces it — the pin is behind the source it has to build, and only `make pin` moves that.

**AND IT IS IN THE FULL TIER, NOT JUST THE QUICK GATE.** Track T's newest full-tier report,
`20260906T040852Z-b77ac29-seven.md`, verdict **RED**, names it:

    lib-test#src:tools/crtl_reachability.py
      pascal26:159: error: undefined variable (pyvar_is_objtag)      lib/rtl/mimic_string.pas
      pascal26:483: error: undefined variable (pyvar_is_inttag)      lib/rtl/mimic_urllib_request
      pascal26:573/666: error: undefined variable (pyvar_is_objtag)

So this is not a local instrument complaining. It is the number the fleet reads.

**THIS IS EVIDENCE FOR AN OPEN DECISION:** [[decide-pair-the-pin-with-the-lib-rtl-it-is-coherent-with]]
(U, prio 55, `owner: user`) now carries both casualties. A cadence argument in the abstract is
weak; one carrying two dated casualties in 48 hours is not.

**SECOND INSTANCE OF A NAMED CLASS.** `feature-pascal-corpus-expansion` records the first:
`property Current: T read GetCurrent;` on `IEnumerator<T>` was omitted from `lib/rtl/classes.pas`
for a month because the pin rejected a property in an interface, and the parser fix sat in `done/`
doing nothing for that corpus until pin v404 carried it. **"Fixed at HEAD, inert until pinned"** —
any compiler fix a `$(PXX_STABLE)` consumer needs is CLOSED while still unusable there, and the
ticket folder gives the wrong answer while the pin gives the right one. Two instances in two days
makes it a class rather than an anecdote: **before closing a compiler fix that a `lib/**` file
depends on, check whether a pin carries it, and say so in the resolution.**

Still not dispatchable. `make pin` is owner-only, it is on the owner's list, and no agent may run
it or ask a peer to.

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

## DATED, 2026-09-06 (frankB found the sha; frank-coordinator verified the interval)

The red has an origin commit and an exact interval, so the owner's decision needs no
archaeology:

```
pin v404      8844c8c42   2026-09-05T20:17:45   binary sha256 fe1e9c37d322
builtins      8374118ec   2026-09-05T23:15:46   fix(N): export pyvar_is_inttag/pyvar_is_objtag
                                                 -- "two lib/rtl units call them and could not compile"
```

**`8374118ec` is NOT an ancestor of the pin** (`merge-base --is-ancestor`, checked) — it
landed **2h58m after it**. It adds both builtins to `compiler/builtin/pylib.pas`, and
**its own commit message says why: two `lib/rtl` units already called them.** So the
sequence is the documented one, with names on it — the RTL was written against a
compiler feature, the feature landed, and the pin has never carried it.

**83 commits have touched `compiler/` since that pin.**

## SEQUENCING, which is this seat's call — the pin itself is not

- **Nothing is blocked right now.** Checked at 2026-09-06: **no checkout on the box has
  uncommitted work under `lib/` or `examples/`**, so no Track B or E session is
  currently building against the stale pin. The cost today is a standing RED in every
  lane's gate, not a stopped session.
- **It is still a reason to pin SOONER.** CLAUDE.md's own precedent: *a red is a reason
  to pin sooner, not later* — the last time reds were read as grounds to withhold, the
  pin held 19 days and v398 shipped a compiler that could not build C for i386 or arm32.
- **No agent may run `make pin`,** ask a peer to run it, or ask two peers the same
  question about it. This ticket is the record; the act is the owner's.

**Read for a session seeing this row RED:** check your diff for `lib/` and for a new
builtin. If it has neither, the row is this ticket and not your change — six sessions
have now confirmed identical output.
