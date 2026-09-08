---
track: P
prio: 50
type: bug
blocked-by: []
status: open
owner: frankS
---

# A specialization's concrete argument is keyed by its SPELLING, so two scopes' types of one name collide into a single specialization

**THREE ARMS, one cause.** Class templates (below), generic ROUTINES (measured
2026-09-07, at the end of this ticket) and the alias mirror in
`bug-p-a-nested-specialization-is-named-by-its-alias-...`. The routine arm also
carries a visibility defect that must NOT be fixed on its own — doing so turns a
compile error into a silent wrong value.

```pascal
generic TBox<T> = record f: T; end;
procedure Outer;
type TRec = packed record p, q, r: Byte; end;   { 3 }
     TBoxRec = specialize TBox<TRec>;
  procedure Inner;
  type TRec = packed record s: Byte; end;       { 1 }
       TBoxRec = specialize TBox<TRec>;
  var ib: TBoxRec;
  begin Writeln(SizeOf(ib.f)); end;             { fpc 1, pxx 3 }
```

A bare `TRec` in `Inner` resolves correctly now (the five name tables are
scoped), so the compiler knows perfectly well which type is meant one line
earlier. The specialization does not ask it. `ParseSpecialization`'s
already-declared shortcut compares `SpecConcreteNames[...]` — the argument's
SPELLING — against the existing row, finds `TRec` = `TRec`, and reuses the outer
specialization whole. **The type identity is carried by a string, and two
distinct types in two scopes have the same string.**

Split out of `bug-p-routine-local-name-scoping-is-implemented-in-one-of-three-tables`
after the scoping fix landed: it was invisible while the bare name resolved
wrong too, because both halves agreed on the wrong type and the program looked
merely consistent.

## The mirror image is already open, and they should be fixed together

`bug-p-a-nested-specialization-is-named-by-its-alias-so-one-name-serves-every-outer-specialization`
[p55, working, same owner] is the SAME keying flaw in the opposite direction:
there, two aliases of ONE specialization mint TWO classes (`a1 is TIntBox2`
answers FALSE where fpc says TRUE). Here, two DIFFERENT types collapse into one
specialization. Over-minting and under-minting from a single cause — a name
standing in for the thing it names — and its body already says the canonical key
exists and is already correct for the inline spelling (`TBox$Int64`). If that
key were also what the dedup compares, both directions close.

Do not fix this one by making the comparison stricter in isolation: that mints a
second specialization per scope and lands on the other ticket's defect from the
other side.

## What is green over it

`tgeneric94.pp` passes and cannot see this either, for the reason recorded in
`bug-p-a-nested-routines-local-type-does-not-shadow-the-enclosing-routines`: its
expected value comes from the same lookup as its actual. The assertion that does
fail is the one in this ticket's own repro.

## THE GENERIC-ROUTINE ARM — measured 2026-09-07 at compiler 46709f4e7648

Same root cause, third arm, and it carries one mechanism the class arm does not.
Found via `tgenfunc10.pp`, whose own header says *"ensure that specializations
with local types are handled correctly"* — it is the fpc suite's test for
exactly this, and it is the corpus row for this ticket.

```pascal
generic function Test<T>(aArg: T): String;
begin Result := aArg.Test; end;

procedure Test1;
type TTest = record Test: LongInt; end;      { one shape }
begin ... s := specialize Test<TTest>(t); end;

procedure Test2;
type TTest = record Test: String; end;       { a DIFFERENT shape, same name }
begin ... s := specialize Test<TTest>(t); end;
```

**Two defects stacked, and the first one hides the second.**

1. **Visibility, which the class arm does not have.**
   `SpecializeInlineGenericFuncUses` runs immediately after the template is
   parsed, scans forward for every `specialize F<...>` use, and splices all the
   concrete bodies **at the template's own declaration position** — top level.
   A routine-local type argument is not in scope there, by construction:

   ```
   pascal26:3: error: unknown type: TTest
     near: ;  Test_TTest ( aArg : >>> TTest ) :
   ```

   Line 3 is the template's line, not the call's.

2. **The keying flaw underneath it, which is this ticket.** The mangled name is
   `Test_` + the argument's SPELLING, so both procedures mint `Test_TTest`, and
   `SpecFuncAlreadyEmitted(nm, nValParams)` — name plus value-parameter count,
   1 in both cases — suppresses the second. **So fixing (1) alone gives Test2
   the body compiled for Test1's TTest: a LongInt read against a String field.**
   A refusal would become a silent wrong answer, which is strictly worse than
   today.

That ordering is the point. **Do not fix the visibility half on its own.** It is
the more obvious of the two, it is what the error message points at, and landing
it without the key turns a compile error into a wrong value.

### What this adds to the fix

The canonical-key fix this ticket already argues for closes (2) for routines as
well as for classes. (1) is additional and routine-specific, and there is a
dependency-graph problem behind the obvious answer: hoisting the local type to
the splice point means hoisting whatever it references — other local types,
local constants in its array bounds — so it is not a one-liner and should not be
attempted as one. Emitting the body in the USE site's scope instead avoids the
graph entirely and is the direction worth costing first.

### Why it was not attempted this session

Diagnosis banked rather than fixed: this is a core change to
`pasparser_generic.inc`, and a two-line change to that same file earlier today
broke four corpus rows (tgenfunc3/4/9/12) while `gate.sh quick` reported GREEN —
see `bug-p-a-generic-routines-specialization-renames-a-field-of-the-same-name`.
Anything landed here needs the full conformance corpus, not the quick tier,
because out-of-line generic methods appear nowhere else.

## 2026-09-08 — THE CLASS/RECORD ARM IS FIXED. The ticket stays open on the other two.

Landed at compiler `2e620048f2e7`. **What moved is arm 1 of three** — the
class-template arm, the one this ticket opens with. The generic-ROUTINE arm and
the alias mirror are untouched and are re-measured below rather than assumed.

**The fix is the identity, not a stricter string.** `SpecArgIdentity(nm)` answers
WHICH DECLARATION a concrete argument's name denotes from here — `FindUClass`,
then `FindTypeAlias`, in disjoint numeric ranges, and 0 for a keyword-spelled
builtin or an undeclared name, where the spelling is the only identity there is.
It is recorded per argument at registration (`SpecConcreteIds`, beside
`SpecConcreteNames`) and compared by the already-declared shortcut alongside the
spelling. The bare `TRec` one line above already resolved correctly since
`0221a024a`; the shortcut simply never asked.

**This ticket's own warning — "do not make the comparison stricter in isolation,
that mints a second specialization per scope" — is answered, and row 4 of the
fixture is the control.** A stricter STRING would over-mint. An identity does
not: two routines naming one GLOBAL `TRec` resolve to one `ci`, stay one
specialization, and `sib-shared A 3 / B 3` is the assertion.

### And that control found a SECOND defect, pre-existing and in the opposite direction

Measured on pre-change HEAD by stash-and-rebuild, so it is not mine: two sibling
routines each writing `type TBoxRec = specialize TBox<TRec>` over one GLOBAL
`TRec` **refused legal code** —

```
pascal26:12: error: unknown type: TBoxRec
```

The shortcut consumed the second declaration as an already-declared no-op
against a class that `UClsOwnerProc` scopes to the FIRST routine, so the two
halves of one visibility question disagreed. That is the shape
`FindSpecialization`'s own header already records at the unit/section level
(`bug-p-a-specialization-minted-in-a-units-implementation-is-seen-by-the-importers-duplicate-test`),
one level finer, and the third absent copy of the same rule. `SpecOwnerProc` is
the sixth table to take the `ScopeReachesProc` key the other five took at
`0221a024a`; the filter went INTO `FindSpecialization` rather than beside its
caller, because two filters for one rule is how the second goes stale.

### What is still open, measured at `2e620048f2e7`, not assumed

- **The alias mirror**, `bug-p-a-nested-specialization-is-named-by-its-alias-...`:
  `TIntBox` and `TIntBox2` both `= specialize TBox<Integer>` still mint two
  classes and `a1 is TIntBox2` answers **FALSE** where fpc 3.2.2 answers TRUE.
  Unchanged by this. **The canonical key does NOT close it and this ticket said
  it would** — the key is built from the argument's spelling, so both aliases
  produce `TBox$Integer` either way; what closes it is minting under that key
  and registering the user's name with `RegisterUClassAlias`, which is that
  ticket's own remedy and wants a full tier.
- **The generic-ROUTINE arm**, `tgenfunc10.pp`: still stops at
  `pascal26:14: error: unknown type: TTest`, the VISIBILITY half, unchanged. Its
  keying half is a different mechanism — `SpecFuncAlreadyEmitted(nm,
  nValParams)`, name plus value-parameter count — and is NOT what this fix
  touched. The ordering warning above still stands in full: fixing the routine
  visibility alone would hand Test2 the body compiled for Test1's `TTest`.

### Fixture

`test/test_a_routine_local_type_keys_its_own_specialization.pas`
(`test_speckeyid26`, Makefile), differential against fpc 3.2.2, five rows.
Row 1 is the defect and **needs the same name in both scopes**: measured first
with `TRec`/`TRec2` and it PASSED, which would have read as the defect being
closed. Rows 2 and 3 keep that measurement as controls, varying the type name
and the alias name independently. Every nested type is 1 byte and every
enclosing one is 3, so a collapse prints 3 where 1 is correct and no row passes
by nothing happening. Row 4 asserts a COMPILE, not a size: two identical record
types over-minted in two routines are not observable from Pascal, so that row
cannot see an over-mint and does not claim to.

## 2026-09-08 — the generic-ROUTINE arm is blocked on PASS ORDER, not on keying

Measured at `1defef6b62d0`, then re-checked at `dffc987ce33e`. This arm is
recorded as parked rather than attempted, because the remedy is a new mechanism
and the ticket's "both halves must land together" understates what the first
half costs.

**The wall is not visibility policy. It is that the type does not exist yet.**

```
pascal26:14: error: unknown type: TTest
```

`tgenfunc10.pp` is not needed to see it — ONE routine and ONE local type is
enough, so the two-scopes collision this ticket is about cannot even be reached:

```pascal
generic function Test<T>(aArg: T): String;
begin Result := aArg.Test; end;
procedure Test1;
type TTest = record Test: LongInt; end;
var s: String; t: TTest;
begin t.Test := 42; s := specialize Test<TTest>(t); end;   { unknown type: TTest }
```

Declare `TTest` at unit level instead and the identical program compiles and
runs (`one 42` / `two 7` with two callers). **Routine-locality alone is the
wall.**

### Why, and it is three routines deep

1. `SpecializeInlineGenericFuncUses` sweeps at the TEMPLATE's declaration — pass
   1, before `Test1` has been read at all. It is a token rewrite and mints the
   mangled name `Test_TTest` lexically. Nothing semantic exists to key on.
2. `FlushPendingFuncSpecializations` runs where the declaration section ENDS
   (`PreScanPass := False;` … `afterDeclTok := TokPos - 1`), which is the fix
   from `73fa72b9e` and is right for every top-level type.
3. A routine's local `type` section is parsed in **pass 2**. `ParseSubroutine`
   skips the body outright while `PreScanPass` is set, so at flush time
   `TTest` has not been declared anywhere — it is not out of scope, it is
   ABSENT. `ScopeReachesProc` cannot help; there is no row to reach.

### What a fix would have to be

The concrete body has to be instantiated during pass 2, inside the routine that
used it — which is what fpc does and what the language means. Nested routines
are the natural home and they work: two sibling routines may each declare their
own `Inner` and they stay distinct (measured), so **the keying collision this
ticket is about dissolves entirely in that design** — `Test_TTest` inside
`Test1` and `Test_TTest` inside `Test2` are two routines, no identity column
needed for this arm.

Sketch, with the traps found while costing it:

- record the use's TOKEN INDEX at sweep time (`PendFuncUseTok`), adjusted by
  `AdjustPreScanSpans` and `AdjustPass2Spans` like every other index into that
  array;
- at flush, splice only the entries whose use lies OUTSIDE any routine's
  DeclItem span; leave the rest queued;
- in pass 2, after a routine's local declarations are parsed, splice the queued
  entries whose use lies inside THAT routine.

**Containment by token span is load-bearing and "does it resolve now" is not a
substitute.** A routine that declares a same-spelled type but never uses the
generic would otherwise get an instantiation spliced into it and fail to
compile, in a program fpc accepts. And a "is this name a known type here"
predicate would be a second copy of `ParseTypeKind`'s cascade — the exact
second mechanism `normalise-dont-special-case.md` is about, and it has to be
right about builtins or a working program stops compiling.

Not attempted. The skip row for `tgenfunc10.pp` carries the same conclusion.
