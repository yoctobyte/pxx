---
track: P
prio: 60
type: bug
blocked-by: []
summary: "A record-typed lvalue assigned an AnsiString is type-checked in exactly ONE of its six forms. Only `r := s` (plain variable) is rejected; the dyn-array element, fixed-array element, record FIELD, class FIELD and pointer DEREF all compile clean and segfault. FPC rejects all six. Root cause measured 2026-08-30: the check at the AN_ASSIGN funnel (ir.inc:9349) is correct and correctly placed, but AssignSideKind (ir.inc:75) types only AN_IDENT and literals, so for AN_INDEX/AN_FIELD/AN_DEREF it returns False, the `and` chain short-circuits and the check is SILENTLY SKIPPED — it never runs. TRAP for the implementer: defs.inc:422 documents AN_INDEX.Left as a base SYM index while ir.inc:1544 reads it as a NODE; a wrong reading turns a false-accept into a false-REJECT, which looks like progress and is a regression. The var/out neighbour is a separate question (AssignSideKind IsRef bail)."
status: working
owner: ""
---

# A string assigned to a record ARRAY ELEMENT is not type-checked

- **Type:** bug (frontend type checking) — **Track P** (Pascal frontend).
- **Filed:** 2026-08-29 by the wasm32 lane (branch `wasm`, 24 ahead / 89 behind
  `d93190c4a` at the time). Target-independent: the native x86-64 build is what
  segfaults below.
- **Not a compat item.** By CLAUDE.md's table this is row two — *real Pascal
  source compiles but runs wrong* — so it is a bug in its own lane at its own
  prio, not a parity note. The program does not merely diverge from FPC; it
  crashes.

## Repro

```pascal
program TB2;
type
  TR   = record S: string; N: Integer; end;
  TRs  = array of TR;
  TFix = array[0..1] of TR;
var rs: TRs; fx: TFix; s: string;
begin
  SetLength(rs, 2);
  s := 'x';
  rs[1] := s;          { dyn-array element   — ACCEPTED }
  fx[0] := s;          { fixed-array element — ACCEPTED }
  writeln('compiled and ran');
end.
```

```
$ pascal26 tb2.pas tb2
ok: tb2  [code=62255B data=2036B bss=42500B procs=129]
$ ./tb2
Segmentation fault (core dumped)
```

The plain-variable form IS checked, in the same program:

```pascal
  r := s;   { -> pascal26:11: error: incompatible types: cannot assign AnsiString to record }
```

FPC rejects every one of them:

```
typebug.pas(9,12) Error: Incompatible types: got "AnsiString" expected "TR"
typebug.pas(11,8) Error: Incompatible types: got "AnsiString" expected "TR"
```

## Why this is worth more than one diagnostic

It is the shape `devdocs/dev/normalise-dont-special-case.md` is about: **one
concept — assigning to an lvalue of record type — reachable through two shapes,
with the check on only one of them.** The variable arm has it; the element arm
does not, for either array kind. The document's own advice applies to the fix:
when you add the missing check, grep for the sibling before closing this —
a record FIELD (`r.Inner := s`), a `var`/`out` parameter, and a class field are
the obvious neighbours and none of them was tested here.

The consequence is the expensive kind rather than the cheap one. It does not
fail to compile, it compiles to a byte move of a string HANDLE over a record's
first field, and what happens next depends on what that field is. Here it is
itself a managed string, so the segfault arrives at scope exit while releasing a
handle that was never one.

## How it was found, which is the part worth recording

Not by a test for this. The wasm32 lane wrote a bad line into its own slice —
`rs[1] := o2.Inner.S + '';`, a leftover from an edit — expected a type error,
and got a working compile and a core dump. **A test whose bad line is caught by
the compiler teaches nothing; this one was only found because the compiler
agreed with it.** Nobody was looking at record assignment that day.

## Gate

Per CLAUDE.md: `make compiler/pascal26` plus the repro above rejecting all four
forms. A `{%FAIL}` conformance case for each shape is the natural regression,
since the assertion is that compilation FAILS.

## 2026-08-30 (frankB) — root cause found; the hole is WIDER than filed, and the fix is Track A

Binary: HEAD `fa0aff661`, self-host fixedpoint `faf762981c3c` (= pin v397).
Repro confirmed: compiles clean, segfaults, exit 139.

### The hole is 5 of 6 forms, not 2

The ticket names the two array-element forms and *predicts* the neighbours
("a record FIELD, a `var`/`out` parameter, and a class field are the obvious
neighbours and none of them was tested here"). They were tested here. **Every
predicted neighbour is also unchecked**, plus pointer deref:

| # | form | pxx | FPC 3.2.2 (oracle) |
| --- | --- | --- | --- |
| 1 | `r := s` plain variable | **rejects** | rejects |
| 2 | `rs[1] := s` dyn elem | accepts | rejects |
| 3 | `fx[0] := s` fixed elem | accepts | rejects |
| 4 | `r.Inner := s` record field | accepts | rejects |
| 5 | `c.F := s` class field | accepts | rejects |
| 6 | `p^ := s` deref | accepts | rejects |

FPC rejects all six (`Incompatible types: got "AnsiString" expected "TR"`);
pxx rejects one. Verified non-vacuously: with form 1 deleted, forms 2-6 compile
**clean** — they are not being skipped after a first error.

### Root cause: the check never runs, because the destination cannot be typed

The check itself is fine and correctly placed, at the `AN_ASSIGN` funnel in
`compiler/ir.inc:9349`. Its own comment claims the funnel means "one rule covers
`for` variables, `+=`, out-param clears and field stores instead of the ~20
sites that build an `AN_ASSIGN`" — **and that claim is what is false.** The
guard is:

```pascal
if AssignSideKind(ASTLeft[node], asgDstTk) and
   AssignSideKind(ASTRight[node], asgSrcTk) and
   AssignKindsIncompatible(asgDstTk, asgSrcTk) and ...
```

`AssignSideKind` (`ir.inc:75`) handles **only `AN_IDENT` and literals**. There
is no case for `AN_INDEX`, `AN_FIELD` or `AN_DEREF`, so it returns False, the
`and` chain short-circuits, and **the check is silently skipped**. It does not
fire and pass — it never runs. So the funnel is real but the typing of the
destination is not, and the rule covers exactly the shapes that reach it as a
bare identifier.

Note the shape: the bail is *deliberate and documented*. For an identifier,
`if Syms[si].IsArray then Exit;` carries the comment `{ the kind is the
ELEMENT's }`. That comment is also the ingredient a fix needs — for an array
symbol `Syms[si].TypeKind` already IS the element's kind, which is exactly what
an `AN_INDEX` destination wants.

### Do not take the obvious patch on trust — the two sources disagree

`defs.inc:422` documents `AN_INDEX` as `{ Left = base sym idx; Right = index
expr }`, which would make the index case nearly free. But `ir.inc:1544` reads
`ASTKind[ASTLeft[node]]` — treating `Left` as a **node**, not a symbol. Both
cannot be right for all builders of the node. Anyone fixing this must establish
which is true (and whether nested `rs[1][2]` differs) **before** writing the
case; a wrong reading here produces a check that mis-types a destination, which
is worse than the missing check because it would reject valid code.

The `IsRef` bail on the same function is why the ticket's `var`/`out` parameter
neighbour is a *separate* question — a by-ref slot holds an address — and it is
not covered by the table above.

### Lane: this is a Track A change, filed under P

The defect is a Pascal-frontend symptom but the fix is in **`compiler/ir.inc`**,
shared core. Per CLAUDE.md that is Track A's file and must not be edited under
Track P. **Not edited.** frankS is concurrently in `defs.inc` /
`pasparser_generic.inc` / `pasparser_decl.inc`, so the sole-A guard is not
satisfied by inspection. Escalated to the coordinator for the A slot rather than
guessed. Diagnosis above is complete enough to hand to whoever holds A.

### Gate when it lands

`make compiler/pascal26` + all six forms rejected, with a `{%FAIL}` case per
shape. **Include form 1 in the regression** — it works today and is the arm that
proves a fix did not break the path that already worked.
