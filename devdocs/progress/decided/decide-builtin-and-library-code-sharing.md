---
track: U
prio: 30
type: decide
summary: "A builtin unit and lib/rtl cannot share code today: moving the shared part down breaks library READABILITY (you must be able to step into sysutils and read it straight through), and letting a builtin use the library collides in NilPy's flat unit scope. The float core is being copied because of it. Review when the next clash lands — not a blocker for anything now."
---

# How should a builtin unit and `lib/rtl` share code?

- **Type:** decision, deferred on purpose — **Track U**
- **Filed:** 2026-08-03, out of
  [[decide-nilpy-where-the-exact-decimal-float-core-lives]]. **Nothing is
  blocked on this.** It is recorded so the next clash is recognised as the
  second instance of a pattern rather than solved from scratch again.

## The squeeze

Two constraints that are each individually right and together leave no clean
option:

1. **A builtin unit may not `uses` a `lib/rtl` unit.** Builtins sit below the
   Track B libraries, and for NilPy specifically the reason is sharper than
   layering: unit scope is flat, so pulling `sysutils` into `pylib` would put
   every sysutils name where NilPy code can collide with it. That is the whole
   reason NilPy does not include sysutils.
2. **Library source must stay readable and STEPPABLE as a file.** One day you
   are in a debugger stepping through `sysutils` and tracing straight through
   it. Moving a chunk down into a builtin unit — or out into an `.inc` — means
   stepping into `FloatToStr` walks you out of the file you were reading.

So the shared part can go neither up nor down, and the answer so far has been to
COPY it.

## Instances so far

- `compiler/builtin/promoint.pas` reimplemented a bignum core rather than use
  `lib/rtl/bignum.pas`, and says so in a comment.
- `compiler/builtin/pylib.pas` will copy ~420 lines of exact-decimal float
  conversion out of `lib/rtl/sysutils.pas`
  ([[bug-nilpy-float-repr-is-not-pythons-shortest-roundtrip]]).

Two is a coincidence; three is a pattern. Numeric cores are the obvious
candidates (fixed point, decimal, date arithmetic, hashing), because they are
exactly the code that is pure, dependency-free and wanted on both sides.

## What would need deciding, when it is worth deciding

- Is copying simply the accepted answer, with a **differential test** as the
  standing mitigation? That is what the float ticket does, and it turns drift
  from a hope into a checked property. If so, write it down as policy so nobody
  re-litigates it per instance.
- Or is there a third home — a unit that is neither a builtin nor a Track B
  library, visible to both, and NOT in NilPy's flat name scope? That last
  clause is the hard part and is where any real solution has to start.
- Or does NilPy's flat unit scope stop being flat (a real module namespace),
  which removes constraint 1 outright and is a much larger change with its own
  benefits?

## Gate

None — nothing is blocked. Revisit when a third instance appears, or when the
NilPy scope question comes up for its own reasons.


## 2026-08-06 — the clash landed; user's call is still WAIT

This ticket says "review when the next clash lands — not a blocker for anything
now". One landed, and it is a good one:

- `lib/rtl/sysutils.pas` `FmtFixed` scales through an Int64 — wrong from ~9e13
  ([[bug-b-format-fixed-overflows-int64-and-loses-digits]]);
- `compiler/builtin/builtinheap.pas` `PXXWriteFloatFixed` expands in Double —
  wrong from 1e23 ([[bug-a-write-fixed-emits-false-digits-past-1e22]]);
- and **each unit already contains a correct exact base-10^9 implementation**
  (`ExDecDigits`/`ExDecRound`, `PxxSciDigits17`) that its own fixed-point path
  does not use.

So the float core sits in three units and two of the three fixed-point paths
are wrong, in two different ways. That is the strongest evidence yet for the
sharing question.

**Still deferred. User's call:** `builtin` has been stable for many weeks, so
the copies are not actually *drifting* — the two bugs are independent
pre-existing defects that predate the duplication rather than consequences of
it. Unifying now would mean a structural refactor of shared ground to fix two
bugs that each have a local, well-understood fix sitting in the same file.

Fix both in place; keep this ticket as the hook. Revisit if a *future* clash
shows the copies actually diverging — i.e. a fix applied to one and forgotten in
the others — which is the failure mode this ticket exists to catch and is not
what happened here.

Handoff carrying the work: `devdocs/dev/handoffs/2026-08-06-float-exactness-track-a-and-b.md`.

## 2026-08-08 — moved to rainy-day/ so it stops ranking as READY

The 2026-08-06 entry records the user's call as **WAIT** — the clash landed and
the answer is deliberately deferred. It nonetheless stayed in `backlog/` and kept
ranking in `ready --track U`.

Same disposition and same rule as
[[decide-abi-portable-vs-target-split]]: a deferred decision lives in
`rainy-day/`. Nothing about the substance changes; it is waiting on events, not
on an answer.

## DECIDED 2026-08-08 (user): STRICT SEPARATION — copying is the accepted answer

> builtin vs library is already decided - strict separation. even if that means
> double code.

Both constraints stand as written: a builtin unit does **not** `uses` a
`lib/rtl` unit, and library source stays readable and steppable as a whole file.
Neither is traded away. **Duplication is the accepted cost**, not a debt to be
paid off later.

That resolves the first of the three questions above and **rules out the other
two as answers to THIS problem**:

- a "third home" visible to both and outside NilPy's flat name scope — not
  pursued;
- making NilPy's unit scope non-flat — may still happen for its own reasons, but
  it is not the fix for this, and this decision must not be cited as a driver
  for it.

### The standing mitigation is now mandatory, not optional

Copying is only safe with the drift check attached, so this is policy:

- **A copied core carries a differential test that pins the copies against each
  other**, the way the float ticket does. Drift becomes a checked property
  rather than a hope.
- **Every copy says it is one**, naming its sibling, so the next reader knows to
  look. `compiler/builtin/promoint.pas` already does this.
- **Change one, change all.** The exact-decimal float core already exists in
  three places (`lib/rtl/sysutils.pas`, `exdec.inc`, `pylib.pas`), each pinned by
  its own test — that is the shape every future copy should take.

The "revisit when a third instance appears" trigger in the Gate above is
**withdrawn**: a third instance is now expected, not a signal. Nothing to
revisit.

Moved out of rainy-day/ — it was deferred, and now it is answered.
