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
