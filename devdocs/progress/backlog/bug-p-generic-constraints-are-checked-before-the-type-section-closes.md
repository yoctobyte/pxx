---
slug: bug-p-generic-constraints-are-checked-before-the-type-section-closes
track: P
prio: 70
type: bug
blocked-by: []
status: open
created: 2026-08-30
summary: "Generic constraint checking runs inside ParseSpecialization, which the Delphi rewriter reaches BEFORE the argument's class is parsed, so any argument that is not already a fully declared class must be skipped. Cost: tgenconstraint4 (`LongInt`) and 5 (`TClass`) are still wrongly accepted, and no constraint is enforced against a forward-declared class. The fix is to check at end of type section; the hook exists but its call site is guarded."
---

# P: generic constraints are checked before the type section closes

Follow-up to [[bug-p-generic-type-constraints-are-parsed-and-discarded]], which
implemented constraint checking and took 33 of the 35 FAIL-marked
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
constraints load-bearing for the first time — correctly; 35 FAIL-marked
`tgenconstraint` tests were being wrongly accepted. The moment it landed, this
ticket stopped being a timing curiosity nothing could observe and became the
mechanism behind a **NEW-RED on `test-fgl`**, on real FPC-corpus code:
`TFPGObjectList<TThing>` is rejected because `TThing` — a bare `class`, i.e. an
implicit `TObject` descendant — is declared in the **same type section** as the
specialization.

Tracked as [[regression-p-generic-constraint-check-rejects-a-class-declared-in-the-same-type-section]],
which carries the repro and a 30-second discriminating test. **Do not fix by
loosening the check** — the 35 tests are the arm that would silently undo.

This is the second time today that a carrier nothing read turned out to be wrong
the instant a reader existed (the other: `UFldStrElemTk` hardwired to
`Ord(tyChar)` under a comment justifying it as safe *today*). Same shape: correct
when written, false the moment something consumed it.
