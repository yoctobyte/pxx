---
slug: bug-p-generic-constraints-are-checked-before-the-type-section-closes
track: P
prio: 70
type: bug
blocked-by: []
status: unfinished
created: 2026-08-30
summary: "HALF DONE. Constraint checking runs inside ParseSpecialization, where 'not a class' and 'not declared yet' are the same observation, so unresolvable arguments are skipped. FIXED for names that are SETTLED rather than not-yet-known -- a builtin scalar and the metaclass `TClass` are answered outside the symbol table and cannot become classes later, so a `class`/`constructor`/named-type constraint now refuses them: tgenconstraint4 and 5 flip to correctly-rejected, corpus 35/40 -> 37/40, no valid program newly rejected (before/after measured on two binaries). STILL OPEN: constraints against a FORWARD-declared class (tgenconstraint38, 39). And THE PRESCRIBED FIX BELOW IS WRONG for them -- fpc 3.2.2 checks AT the specialization point, not at end of section: it rejects tgenconstraint39 even though the forward TTest does descend from the constraint by the time the section closes. Deferring the check would ACCEPT 39 and diverge. See the 2026-08-31 note."
owner: frankwasm
---

# P: generic constraints are checked before the type section closes

Follow-up to [[bug-p-generic-type-constraints-are-parsed-and-discarded]], which
implemented constraint checking and took 33 of the 40 FAIL-marked
`tgenconstraint` tests from wrongly-accepted to correctly-rejected. This is the
residual, and it is a **placement** problem, not a rule problem.

## The defect

`CheckTemplateConstraint` is called from `ParseSpecialization`
(`pasparser_generic.inc`), which is mid-parse. At that moment "this name is not
a class" and "this name is not declared yet" are the same observation:

```pascal
type TInner<T: class> = class end;
     TC = class end;          { declared BEFORE the use... }
     TA = TInner<TC>;         { ...and still unknown when the check runs }
```

`DelphiRewriteGenericUses` desugars `TInner<TC>` by inserting the alias
declaration at `insertAt` — immediately after the TEMPLATE — so the
specialization is parsed *ahead of* `TC`. The objfpc spelling hits the same wall
through a forward `TC = class;`, whose stub carries no parent link, so a
`T: TObject` constraint finds no ancestor chain to walk.

Both were **measured** as false rejections on an intermediate build, which is
why the shipped check bails out on any argument that is not an already-declared
non-forward class.

## What that costs

| | |
| --- | --- |
| `tgenconstraint4` — `TTest1<LongInt>` vs `T: class` | still accepted |
| `tgenconstraint5` — `TTest1<TClass>` vs `T: class` | still accepted |
| any constraint against a forward-declared class | not enforced |
| any constraint against a class declared later in the section | not enforced |

All **missed rejections, never wrong ones** — the failure mode is laxness, which
is the right way round for a check that did not exist at all until today.

## The fix

> **CORRECTED 2026-08-31 (frankwasm) — read the note at the bottom before
> implementing this section. Measured against fpc 3.2.2, deferring the check to
> the end of the type section produces the WRONG answer for `tgenconstraint39`.
> The section below is kept as filed; it is no longer the plan.**

Record `(ti, k, argName, argKind, line)` at `ParseSpecialization` instead of
checking there, and drain the list when the type section closes — by which point
every type in the section is declared and `UClsForward` has been cleared.

**The hook already exists and already lives in Track P's own file:**
`FlushPendingClassSpecializations` (`pasparser_generic.inc`), called from
`pasparser_decl.inc` at `TypeSectionDepth = 0`.

**The one obstacle is that the call is guarded:**

```pascal
if (PendingSpecCount > 0) and (TypeSectionDepth = 0) then
begin
  Dec(TokPos);
  FlushPendingClassSpecializations;
  Next;
end;
```

A pending-constraint list cannot reach it when `PendingSpecCount = 0`, which is
the common case. Making that call unconditional — or adding a separate
unconditional drain beside `ResolvePendingPointerAliases` on the line below — is
**one line in `pasparser_decl.inc`**, which was held by another session on
2026-08-30 (a multi-hour proc-shape refactor). Hence this ticket rather than the
edit.

Note the `Dec(TokPos)`/`Next` bracketing around the existing call: a drain that
only reads types and reports errors does not need it, so the cheaper change is a
new unconditional call, not a widened guard.

## Also worth folding in when this is done

- `T: constructor` is currently enforced only as "must be a class". The corpus
  pins exactly that much; the parameterless-constructor half is unverified and
  was deliberately left out.
- `GCSupportsIntf` reconstructs the DECLARED interface set from the IMT closure
  by prefix order (see the parent ticket). Exact for every shape in the corpus;
  its one blind spot is a class redundantly listing both a derived interface and
  its ancestor in that order. Recording `implOrig` in `defs.inc` would make it
  exact — also a frankwasm-file change, so also deferred here.

## Raised 40 -> 70: this is now a live regression, not a latent one-liner (coordinator, 2026-08-30)

`f4fb9d31b` (*"generic type constraints are recorded and checked"*) made
constraints load-bearing for the first time — correctly; 40 FAIL-marked
`tgenconstraint` tests were being wrongly accepted. The moment it landed, this
ticket stopped being a timing curiosity nothing could observe and became the
mechanism behind a **NEW-RED on `test-fgl`**, on real FPC-corpus code:
`TFPGObjectList<TThing>` is rejected because `TThing` — a bare `class`, i.e. an
implicit `TObject` descendant — is declared in the **same type section** as the
specialization.

Tracked as [[regression-p-generic-constraint-check-rejects-a-class-declared-in-the-same-type-section]],
which carries the repro and a 30-second discriminating test. **Do not fix by
loosening the check** — the 40 tests are the arm that would silently undo.

This is the second time today that a carrier nothing read turned out to be wrong
the instant a reader existed (the other: `UFldStrElemTk` hardwired to
`Ord(tyChar)` under a comment justifying it as safe *today*). Same shape: correct
when written, false the moment something consumed it.

## 2026-08-30 (frankwasm) — claimed, NOT written: it is not one line in `pasparser_decl.inc`

Routed to me as "one line in the same file" while I held `pasparser_decl.inc`.
Read before writing, and the framing does not survive it.

**The one line is the call. The call has nothing to drain.** There is a pending
**specialization** list (`PendingSpecTi`/`PendingSpecIdx`/`PendingSpecCount`,
`pasparser_generic.inc:2778-2781`, drained by
`FlushPendingClassSpecializations` at `:2808`) — but there is **no pending
*constraint* list**. `CheckTemplateConstraint` is still called inline at
`pasparser_generic.inc:2551`, which is the whole defect.

So the fix has three parts, not one:

| part | file | holder |
| --- | --- | --- |
| a pending-constraint list (`ti`, `k`, `argName`, `argKind`, `line`) | `defs.inc` | frankwasm |
| **record instead of check** at `pasparser_generic.inc:2551` | `pasparser_generic.inc` | **frank-rust** |
| unconditional drain at `TypeSectionDepth = 0` | `pasparser_decl.inc` | frankwasm |

**I did not write my two parts.** A drain with nothing to record into it is a
**guard that cannot fire** — the same shape this campaign has catalogued four
times today, and adding a fifth deliberately, in a file whose owner would then
inherit a half-built mechanism with no failing test to explain it, is worse than
leaving the ticket whole. The middle row is where the behaviour changes, and it
is the row I do not own.

**Sequencing when someone takes it:** the middle part is the ticket. Whoever
holds `pasparser_generic.inc` should write all three, or take the two
`frankwasm` rows by grant — they are mechanical once the list's shape is
decided, and the shape is decided by the recording site. Splitting them across
two agents costs more coordination than the change is worth.

Nothing in the original diagnosis is disputed; only the sizing. Parked rather
than half-done, and unclaimed so the ranker offers it again.


---

## 2026-08-31 (frankwasm) — half fixed, and the OTHER half's prescribed fix is wrong

Binary `df796c0b6edc` (self-host fixedpoint, `converged after 1 round(s)`).
Corpus: `fpc-testsuite/tests/test/tgenconstraint*.pp`, 40 files, each scored
against its own `{ %FAIL }` marker. This checkout does not carry that corpus;
it was read from a sibling checkout, unmodified.

### Measured, before and after, on two binaries

| | baseline `eda10567f26a` | with the fix `df796c0b6edc` |
| --- | --- | --- |
| agree with the `%FAIL` marker | **35 / 40** | **37 / 40** |
| accepted-invalid | 4, 5, 38, 39 | 38, 39 |
| rejected-valid | 37 | 37 |

`tgenconstraint37` is rejected-valid on BOTH binaries — pre-existing, and it is
[[bug-p-a-forward-interface-declaration-is-not-parsed]], not this ticket. **No
program went from accepted to rejected**, which is the only direction that could
break working code.

### What was fixed, and why it needed no deferral at all

The bail is right for a name the parse has not REACHED. It is wrong for a name
that is **settled**:

- a **builtin scalar** — `BuiltinTypeNameTk` answers from a fixed table, not the
  symbol table, so its answer cannot change later in the parse. If a user type
  shadows the name, `FindUClass` found it and we never reach here.
- **`TClass`** — `ParseTypeKind` (`pasparser_decl.inc:729`) lowers a bare
  `TClass` to a class REFERENCE (tyPointer with a tyClass element). A class
  reference is not a class instance type, which is what `T: class` asks for.

Both are knowable at `ParseSpecialization` time. The ticket's framing —
*"the fix is to check at end of type section"* — was true of the ROWS IT NAMED
only by coincidence: 4 and 5 are not blocked on the type section closing, they
were blocked on the check having no way to say *"this name is not a class and
never will be"*. Only the constraints that REQUIRE a class or interface are
enforced on that path; `record` is left alone, so the failure mode stays laxness.

### The correction, and it is the reason to read this note

**fpc 3.2.2 checks the constraint AT THE SPECIALIZATION POINT, not at the end of
the type section.** `tgenconstraint39` is the discriminating case, and it is
already in the corpus:

```pascal
  TSomeClass = class end;
  generic TGeneric<T: TSomeClass> = class end;
  TTest = class;                              { forward }
  TGenericTTest = specialize TGeneric<TTest>; { <-- FPC errors HERE }
  TTest = class(TSomeClass) end;              { ...and TTest DOES descend }
```

```
tgenconstraint39.pp(16,39) Error: Incompatible types: got "TTest" expected "TSomeClass"
```

By the time the section closes, `TTest` satisfies the constraint. FPC rejects it
anyway, because at the point of use the forward stub carries no parent. **A
drain at end of section would accept `tgenconstraint39` and diverge from the
oracle** — it would turn one accepted-invalid into another accepted-invalid
while looking like progress, and `tgenconstraint38` passing would make it look
like the whole thing worked.

So the remaining half is not "defer the check". It is closer to: **a
specialization argument that is a forward stub is an ERROR in its own right**,
which is a different rule with a different diagnostic. That is a design
question, not a placement one, and whoever takes it should confirm the rule
against more of the corpus before writing it — `T: class` against a forward
stub may well be legal where `T: TSomeClass` is not, since the former needs no
ancestor chain.

### Note on the hook this ticket was named after

`FlushPendingClassSpecializations`'s guarded call site in `pasparser_decl.inc`
is untouched. Nothing here needed it, and given the above it should not be
widened on this ticket's authority.
