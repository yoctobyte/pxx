---
slug: regression-p-generic-constraint-check-rejects-a-class-declared-in-the-same-type-section
title: "The new generic-constraint check rejects a class declared in the SAME type section as the specialization"
track: P
prio: 70
type: regression
status: done
blocked-by: []
owner: frankS
summary: "test-fgl went NEW-RED on seven's full tier: objectlist.pas fails `generic constraint violated: TFPGObjectList<T> is constrained to TObject, but TThing is not TObject or a descendant of it` -- and TThing IS `class`, i.e. an implicit TObject descendant. It is declared in the same type section as the specialization that uses it. Introduced by f4fb9d31b (constraints are recorded and checked), which is otherwise a correct and valuable fix. Real FPC-corpus code (fgl); blocked pin v397 from a clean shadow."
---

# The constraint check rejects a class declared in the same type section

**Regression, found by Track T (seven), full tier.** `test-fgl` **passed** at
`a8947307fa98` and went **NEW-RED** at `719bef10ea68` — so this is fresh, not
pre-existing.

```
test-fgl#src:compiler/.pascal26.fixedpoint
  PASS map_str.pas | FAIL objectlist.pas -- compile error:
  pascal26:9: error: generic constraint violated: TFPGObjectList<T> is
    constrained to `TObject`, but TThing is not TObject or a descendant of it
  near: = specialize TFPGObjectList < TThing > >>> ; constructor TThing
```

## The repro is already in the tree: `test/fgl/objectlist.pas`

```pascal
type
  TThing = class            { <- implicit TObject descendant }
    v: Integer;
    constructor Create(av: Integer);
  end;
  TThingList = specialize TFPGObjectList<TThing>;   { <- same type section }
```

`TThing` is a bare `class`, which **is** a `TObject` descendant. The rejection is
wrong on the language, and `near:` shows the check firing while the type section
is still open — the specialization sits between `TThing`'s `end;` and the
`constructor TThing` implementation.

## Almost certainly [[bug-p-generic-constraints-are-checked-before-the-type-section-closes]]

That ticket [P] describes exactly this defect and predates the check that now
exposes it. **Raised 40 → 70**: it was a low-prio one-liner while nothing read a
constraint, and it became a live regression on real corpus code the moment
`f4fb9d31b` made constraints load-bearing.

## The cheap discriminating test — run this FIRST, before reading any code

Split the type section:

```pascal
type
  TThing = class v: Integer; constructor Create(av: Integer); end;
type
  TThingList = specialize TFPGObjectList<TThing>;
```

**Compiles ⇒** the mechanism is confirmed as "checked before the section closes",
and the fix is to defer constraint checking to section close (or to resolve
ancestry lazily at the check).
**Still fails ⇒** the mechanism is something else — ancestry resolution for an
implicit `TObject` base, not section timing — and this ticket's framing is wrong.
Do not skip this; the two produce the identical message.

## What is NOT wrong here

`f4fb9d31b` is a correct and valuable fix and **must not be reverted**:
`TFoo<T: class>` and every other constraint form was parsed and discarded, so no
specialization was ever checked and **all 35 FAIL-marked `tgenconstraint`
fpc-testsuite tests were wrongly ACCEPTED**. The check is right; its *timing* is
wrong. Fix the timing, keep the check.

## Gate

`test/fgl/objectlist.pas` compiles and runs, `map_str.pas` stays green, and the
35 `tgenconstraint` tests stay correctly rejected — that last one is the arm a
naive "loosen the check" fix would silently undo.

---

## FIXED (frankS, 2026-08-30) — the framing was wrong: not timing, not implicit ancestry

### The discriminating test, run first, killed both hypotheses

Splitting the type section so the class closes before the specialization **still
fails**. So it is not section timing. The coordinator's stated alternative —
implicit-`TObject` ancestry — is also dead: an **explicit** `class(TObject)`
fails identically. A self-contained repro (no fgl corpus needed) mapped it:

| shape | before |
| --- | --- |
| constraint `TObject`, arg `TObject` | **ok** |
| constraint `TObject`, arg `class` (implicit), same section | FAIL |
| constraint `TObject`, arg `class` (implicit), **split** section | FAIL |
| constraint `TObject`, arg `class(TObject)` (explicit) | FAIL |
| constraint `TObject`, arg three levels down | FAIL |
| constraint **user base class**, arg its descendant, same section | **ok** |
| ordinary descendant → ancestor assignment | **ok** |

The parent-chain walk is sound — a user base class works, and works *in the same
type section*, which independently re-falsifies timing. Only `TObject` as the
constraint fails, and only for descendants.

### The mechanism: two representations of "descends from TObject"

`pasparser_decl.inc:4594-4606` deliberately refuses to link TObject as a parent:

```pascal
{ TObject is a registered builtin class row now, so exclude it from
  the parent lookup by name — a real-parent link would relocate
  every `class(TObject)` VMT and break the implicit-root model
  (and the COM/ARC synthesis for TInterfacedObject). }
if CaseEqual(CurTok.SVal, 'TObject') then tmpCi := -1;
```

So `UClsParent` is `-1` at the root for **both** `class(TObject)` and a plain
`class`. Meanwhile `CheckTemplateConstraint` does `conCi := FindUClass('TObject')`,
which **does** find the registered builtin row, then calls
`GCIsDescOrSelf(argCi, conCi)` — a walk up a chain that terminates at `-1` and
structurally can never reach that row. `TBox<TObject>` passed only because
`argCi = conCi` matched on the first iteration, before any walk happened.

The parent chain says `-1`; the class table says a row. The check asked the
question in the coordinate system where the answer is unreachable. Neither side
is wrong on its own — they were never reconciled.

### The fix — `pasparser_generic.inc` only

Answer the root constraint in the other coordinate system: in Pascal every class
descends from `TObject`, so `T: TObject` means exactly `isClass`, which the
function has already computed. Three lines at one call site.

**This is not a loosening.** A non-class still fails `isClass`, so every
FAIL-marked test stays rejected — proven by control below, not by argument.

### Why the three-part plan was not needed

The relayed plan was a pending-constraint list in `defs.inc`, recording instead
of checking at `pasparser_generic.inc:2551`, and an unconditional drain at
`TypeSectionDepth = 0` in `pasparser_decl.inc`. All three parts implement
*deferral*, and deferral does not fix this: the split-section row already defers
the check past the class's own section close and **still fails**. Building it
would have left the regression live, touched two files held by other agents, and
made the check fire later in a coordinate system that still cannot answer it.

`bug-p-generic-constraints-are-checked-before-the-type-section-closes` [P p40]
is therefore **not** this ticket's root cause and the two should not merge. It
describes a real third state (a class whose declaration has started but whose
ancestors/IMT are not yet populated) and `tgenconstraint4`/`5` are still its
evidence — it stands unchanged, and it is still worth doing on its own merits.

### Gate — all three rows, each with a pre-fix control

- `test/fgl/objectlist.pas` — compiles, runs, output matches `.expected`.
- `test/fgl/map_str.pas` — compiles, runs, output matches `.expected`.
- **The trap row:** `tgenconstraint*` conformance, post-fix **34 pass / 2 fail /
  4 skip**, and the pre-fix compiler on the same corpus gives **34 / 2 / 4** —
  byte-identical. The two failures (`tgenconstraint4` `LongInt`,
  `tgenconstraint5` `TClass`) are pre-existing, predate this work, and are
  documented in `CheckTemplateConstraint`'s own comment as the deliberate cost
  of the `argCi < 0` guard. Nothing moved.
- Wider `tgeneric*` corpus: **62 / 0 / 42 / 3** post-fix and pre-fix alike.
- `make compiler/pascal26` — `converged after 1 round(s)`, binary `9d3f4685ac45`.
- `tools/gate.sh quick` GREEN.

Corpus note: neither `fgl.pp` nor the fpc-testsuite is installed in this
checkout, so both were run against read-only copies from sibling checkouts
(`/home/neo/frankA/...`, `/home/neo/frank1/...`). Nothing in either was written.

### Regression test

`test/test_generic_constraint_tobject_root.pas`, self-contained so it runs on a
box without the fgl corpus (this one skips `test-fgl` entirely). Six rows:
implicit, explicit, three-deep, `TObject` itself, a separate type section, and a
user-base constraint. `.expected` generated by FPC 3.2.2 compiling the file;
pxx matches byte for byte, and the pre-fix compiler fails it at the first row.

The section-splitting rows are deliberate: they are what falsified the timing
diagnosis, and keeping them stops a future timing-flavoured change from quietly
re-opening it.

## Log
- 2026-08-30 — resolved, commit cce53aada.
