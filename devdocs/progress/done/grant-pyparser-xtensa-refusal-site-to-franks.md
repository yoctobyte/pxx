---
track: N
prio: 50
type: grant
blocked-by: []
summary: "Bounded cross-lane grant: frankS (Track S) may edit ONE site in Track N's pyparser.inc -- the `TargetArch = TARGET_XTENSA` refusal and its justifying comment at ~line 45973 -- as part of the arch-vs-platform ruling. Nothing else in the file. Granted because leaving the fifth site unedited recreates, in NilPy, the exact refusal the ruling retires."
status: done
owner: frankS
---

# Grant: the xtensa refusal site in `pyparser.inc`, to frankS, bounded

**Granted 2026-08-30 by the coordinator, filed at the moment of giving.** An
unfiled grant fails both ways: it reads as covered because a neighbouring ticket
covers the same file, and the tooling cannot see it.

## What is granted

**One site.** `compiler/pyparser.inc` at approximately line 45973: the
`if TargetArch = TARGET_XTENSA then Error(...)` refusal and the comment
justifying it, which is carried **verbatim** from the four sites the
arch-vs-platform ruling already names.

**Nothing else in that file**, and nothing else in Track N. If the edit turns
out to need a second site, a symbol rename, or anything in `pylexer.inc`, that
is a new conversation and not an extension of this one.

## Why it is granted rather than handed off

`pyparser.inc` is **Track N's carved-out file** and the standing rule is that a
frontend owns its own parser: a lane needing a change in someone else's frontend
files the ticket and hands it over. That rule is right and this grant does not
weaken it.

Three things make this the exception rather than an erosion of it:

1. **The omission is the defect.** The ruling retires a premise — the hosted
   profile separated `arch` from `platform`, so every claim written before it
   that used "xtensa" to mean "ESP/FreeRTOS" expired without being edited. A
   session that implements the runtime and touches only the four Pascal sites
   leaves **NilPy on hosted xtensa refused by a premise that same commit just
   retired.** That is the ordinary fix-one-arm-and-forget-the-sibling hazard, and
   it is exactly what `normalise-dont-special-case` says to grep for before
   closing.
2. **Contention does not widen.** Measured before granting: no tree holds
   `pyparser.inc`, and no commit in the recent range touches it. The binding
   constraint the ruling identifies is the `pasparser_*` set, which frankA holds
   and which this does not go near. `symtab.inc` is likewise frankA's and is not
   in scope here.
3. **Two copies here are the intended design, not drift.** Under
   `the-substrate-is-ast-and-ir-not-the-parser`, the Pascal and NilPy frontends
   duplicating a refusal is correct — parsers are duplicated across languages on
   purpose. So there is no refactor to propose and no shared helper to reach for;
   there is one line in each frontend and both must move.

## Standing constraint

**Push immediately after the edit.** The value of the narrow scope is that the
file is held for minutes rather than a session, and an unpushed edit holds it
without anyone being able to see that it does.

`regression-nilpy-a-literal-str-receiver-with-key-reaches-no-keyed-overload`
[N p50] also needs this file — the keyword promoter, far from line 45973 — and
whoever takes it should sequence after this grant is pushed rather than merge
against it. That ticket is unclaimed as of this filing.

## Provenance

frankS found the fifth site by grepping for the refusal's own comment text after
the coordinator flagged an **adjacency** between two expired xtensa premises and
explicitly declined to assert it was one mechanism. It is one mechanism, and the
grep rather than the adjacency is what says so. The ruling's own file list names
four sites; this is the fifth, and the ruling has been amended.

## Consumed 2026-08-30 by frankS — and the GUARD DID NOT MOVE. Read this before assuming it did.

One site, comment only. `compiler/pyparser.inc` ~45972: the three-line
justification was replaced; `if TargetArch = TARGET_XTENSA then Error(...)`
is byte-for-byte what it was. Nothing else in the file, nothing else in Track N.

**Why the refusal stays, when the ruling says the axis is wrong.** Both are true
and they are not in tension. Measured, not assumed —
`grep -rn "EmitSignalRuntime" compiler/*.inc`:

| target | signal-runtime arm in `EmitSignalRuntimeForTarget` |
| --- | --- |
| x86-64, aarch64, arm32, i386 | present |
| riscv32 | present, gated `if not EspBareBoot then` — the model the ruling cites |
| **xtensa** | **absent — no arm at any platform** |

So the *stated* reason expired exactly as the ruling derives (it reasons from
arch to platform, and the hosted profile split those). The *live* reason is
**broader, not narrower**: there is no xtensa signal runtime for ESP **or** for
hosted, so refusing is correct on both today. Re-keying this on `not
EspBareBoot` right now would not fix a wrong axis — it would **open a hole**,
accepting `__pxxSig*` on hosted xtensa and answering out of a handler that was
never installed. That is a plausible wrong value in code that dispatches on it,
i.e. the precise failure the refusal was written to prevent, and the ruling is
explicit that the runtime is *authorized in principle, not dispatched*.

**The axis moves in the same commit that adds `EmitSignalRuntimeXtensa`, never
ahead of it.** That sentence is now in the comment, at the site, where the person
who writes the runtime will be standing.

**The Pascal sibling is deliberately untouched.** `pasparser_expr.inc:4382`
still carries the retired premise verbatim. It is frankA's file and the ruling
gates on exactly that contention; this grant did not cover it and I did not take
it. Whoever lands the runtime moves both — that is now written at the NilPy site
and in the ruling's addendum, so the sibling is discoverable from either end
rather than from neither.

**Evidence it is inert:** `make compiler/pascal26` converged in 1 round and the
resulting binary is **byte-identical** (`2d2bc2fb0e15`) to the one saved before
the edit. A comment-only change that moved the binary would itself have been the
finding; it did not.

## Log
- 2026-08-30 — resolved, commit 2c9abddc9.

## CORRECTION — the grant's stated justification was WRONG, 2026-08-30

**Filed by the coordinator who wrote it.** This grant said *"the omission is the
defect"* and that leaving the fifth site unedited *"recreates, in NilPy, the
exact refusal the ruling retires."* **That is false, and frankS declined to
consume the grant on it.**

The refusal is **not** retired. `EmitSignalRuntimeForTarget` has **no xtensa arm
at all** — measured: x86-64 / aarch64 / arm32 / i386 unconditional, riscv32
gated, xtensa absent. So hosted xtensa has no signal handler either, and the
guard is correct on **both** platforms today. Re-keying it on `not EspBareBoot`
would have accepted `__pxxSig*` and answered out of a handler that was never
installed — **a hole, not a fix.**

What frankS did instead: corrected the stale comment to state the live reason,
left the guard alone, and wrote at the site that the axis moves in the same
commit as the runtime, in all five places at once. That sentence now sits where
whoever writes the runtime will be standing.

**The generalisation, and it is worth more than the edit: an expired premise does
not imply the guard it justifies is wrong.** Here the true reason turned out
**broader** than the stated one, so the stale comment was concealing a refusal
that is *correct* rather than one that is wrong. Both readings look identical
from the comment alone, and the grant — written from the ruling's premise, not
from the code — assumed the wrong one.

Two rules this cost, both already written down and both mine:

- *Verify against a source the claimant did not choose.* The ruling named four
  sites and a reason; I checked the ruling's reasoning and granted on it. frankS
  checked `EmitSignalRuntimeForTarget`, which the ruling never mentions.
- *A grant reads as authorisation for the action it describes.* This one
  described a reversal, and a lane acting on it in good faith would have opened
  the hole with the coordinator's authority behind it. **A wrong grant is worse
  than a wrong ticket, because a ticket invites judgement and a grant retires
  it.**

The grant itself was still correctly SCOPED — one site, push immediately — and
that scope is what kept the damage to a comment. Scope survived; justification
did not.
