---
track: P
prio: 45
type: feature
blocked-by: []
summary: "DONE — `{$CLAIM name}` lands: a conditional symbol that outlives the unit that sets it, set-once, whole-compilation, not retroactive. `{$DEFINE}` is unchanged and still unit-scoped (FPC parity kept). Held in a claim list that no snapshot saves, so never-cleared is structural rather than a list of restore sites; read through PasDefineExists so every conditional sees it. Two Gate clauses are answered differently than the ticket assumed and both are recorded below."
status: done
---

# `{$CLAIM xyz}` — a define that crosses unit boundaries

> **RESOLVED 2026-09-04 (frankD, Track P).** Built as `{$CLAIM}`, per
> [[decide-a-cross-unit-define-name-and-semantics]]. `{$DEFINEGLOBAL}` was NOT
> implemented and deliberately stays an unknown directive — verified: it still
> warns `unknown compiler directive {$DEFINEGLOBAL} — ignored` while `{$CLAIM}`
> does not, which is the membership rule frankS asked for.
>
> ## What landed
>
> - `compiler/defs.inc` — `PasClaimList`, one `|`-delimited lowercase string.
> - `compiler/lexer.inc` — `PasClaim` / `PasClaimed` / `PasClaimKey`; the
>   `else if CaseEqual(command, 'claim')` arm; `PasDefineExists` split into
>   `PasDefineInTable` (the table, what `PasDefine` and `PasSetDefineValue` ask)
>   and the union (what every conditional asks).
> - `compiler/elfwriter.inc` — the include-expansion pass's arm.
> - `docs/reference/directives.md` — the row and the semantics paragraph.
> - `test/test_pascal_claim_crosses_units.pas` + `test/units_claim/`, wired into
>   `test-core`.
>
> ## Why a separate list and not a row in the define table
>
> The define table is snapshotted and rolled back **wholesale** in two places —
> `CompileUnit`, around every unit, and `ExpandIncludes`, around include
> expansion. A claim stored there is undone by whichever restore runs next. A
> list nothing saves makes *whole-compilation scope* and *set-once, never
> cleared* **structural**, not a list of sites someone remembered to patch;
> `{$UNDEF}` cannot reach it for the same reason, so "a claim you can release is
> not a claim" needs no check to enforce it.
>
> ## The bug the first cut had, because every file is walked TWICE
>
> First cut took the claim in `ExpandIncludes` too. That pass runs before the
> lexer over the same text, so the claim was already held when the lexer arrived
> and the unit's own `{$IFNDEF C} {$CLAIM C} {$DEFINE I_WON} {$ENDIF}` took the
> ELSE arm — **the documented claim-and-skip pattern defeating itself**, with no
> other claimant anywhere in the program. Measured: unit `a` printed `stood
> down`. Expansion is a PREVIEW whose define state is rolled back at the bottom
> of the routine, so that arm now calls `PasDefine`, not `PasClaim`, and the one
> authoritative walk takes the claim.
>
> ## Two Gate clauses answered differently than the ticket assumed
>
> **1. "visible to `{$IFDEF X}` in the program" — NO, and it is the SAME rule,
> not a hole.** pxx lexes a source file whole (`LexAll`) and then parses the
> token array, so every conditional in the main program is resolved before its
> `uses` clause has compiled a single unit. The program is, in scan order, the
> FIRST thing compiled — so a unit's later claim is not retroactive **to it**,
> which is answer 4 of the decision applied consistently, and the same reason a
> unit's plain `{$DEFINE}` has never reached the program (the ticket's own
> measured FPC-parity row). Making it work means interleaving lexing with parsing
> for the main file: an architectural change in shared lexer territory, with no
> motivating use — the motivating pattern is unit-to-unit and it works. A program
> that wants the name claims it itself, above its `uses`. Documented as the rule
> in `docs/reference/directives.md`.
>
> **2. A claim inside an INCLUDE is durable, but invisible to include SELECTION —
> and that is pre-existing.** `ExpandIncludes` restores the define table per
> nesting level, so an include's own `{$DEFINE}` does not reach its includer
> during that pass either. Reproduced with a plain `{$DEFINE}` and no `{$CLAIM}`
> anywhere, at HEAD **and under the pinned compiler**, where both arms of the
> conditional vanish silently. Filed as
> [[bug-p-a-define-set-in-an-include-is-invisible-to-the-includers-own-include-selection]]
> (p45). `{$CLAIM}` inherits it identically rather than growing a third store to
> special-case itself around a general bug; `test/units_claim/uclaim_c.pas`
> records the boundary in its header.
>
> ## Gate
>
> `make compiler/pascal26` — `converged after 1 round(s)` (the recompute verb).
> `tools/gate.sh quick` — `gate: GREEN (exit 0)` with `PASS  FPC seed canary`,
> run before committing so the canary was live rather than SKIP.
>
> **Positive control, drawn from the right population:** the same test compiled
> with `stable_linux_amd64/default/pinned`, which has no `{$CLAIM}`, flips
> exactly the five discriminating rows — `b: claimed`,
> `undef: UNDEF CLEARED THE CLAIM`, `inc: INCLUDE CLAIM LOST`,
> `later: INCLUDE CLAIM DID NOT CROSS` — and leaves unchanged the two that cannot
> fail (`early`, `program`), as the test's own header says they must. Those two
> pin the SHAPE of the answer rather than catching a regression: "no claim yet"
> is also what a no-op prints, so they are labelled in the test, not counted as
> coverage.

## Original ticket

> **UNBLOCKED 2026-08-19 — the decision landed. Build `{$CLAIM}`, not `{$DEFINEGLOBAL}`.**
> See [[decide-a-cross-unit-define-name-and-semantics]] in `decided/` for the full rationale.
>
> - **`{$CLAIM}`** is the spelling. `{$DEFINEGLOBAL}` is retired.
> - **Set-once, never cleared** (derived from the semantics, not quoted — see the decision).
> - **Whole-compilation scope.**
> - **Not retroactive**: a unit already compiled does not see a later claim.
>
> **Order-dependence is the FEATURE, not a wart to document around.** The user's framing:
> this is how C works — `#ifndef GUARD / #define GUARD`. The first unit to arrive claims the
> name and crafts its code; every later unit sees the claim and stands down. That is why the
> tension with [[bug-p-uses-order-does-not-decide-which-unit-wins]] dissolves: that bug was
> order deciding something the program did not ask for; this is the program asking, in a
> spelling that says so.
>
> Restored to p40 (it had been de-ranked to 25 while blocked). The four design questions
> below are ANSWERED — read the banner, not them.

- **Type:** feature (dialect extension) — **Track P** (Pascal frontend; the
  implementation is in the shared `lexer.inc`, so it lands under Track A's
  no-concurrent-edit rule).
- Raised by the user 2026-08-14, having circled it earlier the same day:

> *"In Pascal, `$define`s are per unit, by definition. A unit has no way of
> setting a global `$define`. Because if we could, there would be no issue — we
> can just implement one or the other, whichever gets loaded first sets the
> global define and the second implementation can skip it."*

## Measured — the current behaviour is correct, and is the constraint

```pascal
unit u1;  {$DEFINE FROM_UNIT}   …
program p;  uses u1;  {$IFDEF FROM_UNIT} … {$ENDIF}
```

| | result |
|---|---|
| pxx | `define stayed in the unit` |
| FPC | `define stayed in the unit` |

Identical. So this is **not a bug and not a gap** — it is standard Pascal, and
`{$DEFINE}` must keep behaving this way. The feature is a *new, explicitly
named* directive alongside it, not a change to the existing one.

## What it is for

The motivating pattern is **claim-and-skip**: two units can supply the same
capability, and whichever is compiled first claims it, so the second compiles
itself out rather than colliding.

```pascal
{$IFNDEF PXX_HAS_EXCEPTION_CLASS}
  {$DEFINEGLOBAL PXX_HAS_EXCEPTION_CLASS}
  type Exception = class … end;
{$ENDIF}
```

That is the shape the user identified as dissolving the pylib/sysutils
`Exception` problem — see [[decide-merge-variant-c-with-bare-name-collision]]
and [[decide-class-namespace-scoping]]. Whether it is the right answer *there*
is settled separately (that case was closed as synthetic); the mechanism is
useful regardless, and this ticket is the mechanism, not the application.

> **BLOCKED on [[decide-a-cross-unit-define-name-and-semantics]] as of 2026-08-19, and
> de-ranked 40 -> 25.** The four questions below are a Track U decision, not engineering:
> an engineer taking this ticket would have to guess the directive's NAME, and the name is
> the whole decision because the mechanism is order-dependent by construction. Nothing pulls
> on this — the motivating case was closed as synthetic — so there is no cost to waiting and
> a real cost to guessing a spelling we cannot rename later.

## Design questions to settle before building

1. **Ordering makes it order-dependent by construction.** "First one wins"
   means the answer depends on `uses` order — the exact property
   [[bug-p-uses-order-does-not-decide-which-unit-wins]] worked to make
   deterministic. That is acceptable *when the program asked for claim-and-skip*
   and unacceptable as an accident, so the directive's name and documentation
   have to make the dependence obvious. `{$DEFINEGLOBAL}` reads as "global",
   not as "order-sensitive"; a name like `{$CLAIM}` might be more honest.
2. **Can it be undefined?** A global `{$UNDEF}` reopens the same race. Probably
   set-once, never cleared, which also makes it cheap.
3. **Scope of "global".** Whole compilation, presumably — not "all units
   compiled after this point in the uses graph", which would be subtler and
   harder to reason about.
4. **Does it survive into a used unit's own conditionals?** i.e. is it visible
   to units compiled *before* the setter, if they are re-entered? Almost
   certainly no, and saying so is cheaper than discovering it.

## Not a substitute for scoping

Worth stating so it is not reached for as a shortcut: claim-and-skip papers over
a name collision, it does not resolve one. Where the real answer is unit-scoped
resolution ([[bug-pascal-uses-is-transitive]]), this must not become the excuse
not to do it.

## Related

- [[feature-a-strict-flags-scope-to-dialect-ownership-not-program-vs-unit]] —
  sibling idea from the same conversation; both are about a unit declaring
  something about itself that the rest of the compilation must respect.

## Gate

A unit setting `{$DEFINEGLOBAL X}` is visible to `{$IFDEF X}` in the program and
in units compiled after it; a plain `{$DEFINE X}` in a unit still is **not**
(the FPC-parity test above, which must keep passing); and two units guarding the
same capability with claim-and-skip compile with exactly one of them active.

## Triage 2026-08-19 (Track D re-triage pass, pin v363)

**Genuine feature — but not buildable as it stands: it is gated on a Track U
decision, not on engineering.** Its own "Design questions to settle before
building" lists four open forks, and the first is a naming/semantics call the
user should make (`{$DEFINEGLOBAL}` reads as "global" while the mechanism is
order-dependent; the ticket itself floats `{$CLAIM}` as more honest).
Meanwhile its motivating application was closed as synthetic, so nothing is
pulling on it.

Re-measured the FPC-parity half that the ticket rests on and it still holds: a
unit's plain `{$DEFINE}` does not reach the program under either compiler, so
the constraint this feature works around is real and unchanged.

**Recommendation: split the four design questions into a `decide-` ticket
rather than leaving them inside a `feature-`, or drop the prio to match "no
live caller".** Filing one would need the user, so it is queued, not taken.
Whoever picks this up should also re-read it after the current import/uses
spelling work lands — that work is settling adjacent questions about how a unit
declares something the rest of the compilation must respect.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit d10527193.
