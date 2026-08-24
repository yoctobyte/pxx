---
track: P
prio: 60
type: bug
blocked-by: []
status: done
owner: claude-A
summary: "`i := s` with i an Integer and s an AnsiString compiles clean and prints a heap address; `s := i` compiles clean and SEGFAULTS. Seventeen assignments fpc 3.2.2 rejects with `Incompatible types` are all accepted silently — record to integer, class to integer, string to boolean, every direction. This is not dialect laxness: it is a missing check that turns a one-character typo into a wrong value or a crash with no diagnostic anywhere."
---

# An assignment between incompatible types is not checked at all

Found 2026-08-24 while measuring how many errors one compile reports
([[feature-a-error-does-not-halt-so-a-parse-can-be-speculative]]). The
error-count measurement turned up something worse than the thing being measured.

## Measured

Harness (fpc 3.2.2 `-Mobjfpc`, warnings off, vs `compiler/pascal26` at
7fcf3108b):

```pascal
type TRec = record a: Integer; b: AnsiString; end;
     TCls = class x: Integer; end;
var r: TRec; c: TCls; i: Integer; s: AnsiString;
    d: Double; b: Boolean; p: Pointer; ch: Char;
```

| assignment | fpc 3.2.2 | pxx |
| --- | --- | --- |
| `i := s` | `Incompatible types: got "AnsiString" expected "LongInt"` | **accepted** |
| `s := i` | rejected | **accepted** |
| `i := r` / `r := i` | rejected | **accepted** |
| `i := c` / `c := i` | rejected | **accepted** |
| `i := 'text'` | rejected | **accepted** |
| `b := s` / `s := b` | rejected | **accepted** |
| `d := s` | rejected | **accepted** |
| `p := i` / `i := p` | rejected | **accepted** |
| `ch := s` | rejected | **accepted** |
| `s := r` | rejected | **accepted** |
| `b := i` / `i := b` | rejected | **accepted** |
| `i := d` | rejected | **accepted** |
| `d := i` | **accepted** (widening) | accepted |

Seventeen of eighteen. The one FPC accepts is the one that is actually legal.

## Why this is a bug and not the dialect being lax

CLAUDE.md says pxx's dialect is deliberately lax by default and that FPC-parity
strictness lives behind per-feature strict flags. That rule is about
*restrictions that were historic rather than necessary* — accepting something
FPC rejects for no good reason. It does not cover this, by the escape rule in
the same paragraph: **a finding that means silent wrong behaviour is a normal
bug, not a compat item.** These are silent wrong behaviour.

```pascal
s := 'hello';
i := s;        WriteLn(i);   { prints -1411383264 — the string HANDLE }
i := 7;
s := i;        WriteLn(s);   { SEGFAULT — 7 is dereferenced as a string handle }
```

No diagnostic, at any stage, for either. The second one is a crash produced by
code the compiler said was fine.

## Where it should live

The check belongs at the one place every assignment already funnels through, not
per statement form — `GenMakeAssign` is the obvious candidate, and putting it
anywhere else guarantees the second path stays unchecked
(`devdocs/dev/normalise-dont-special-case.md`). Note that a `for` loop variable,
a `+=`, an out-param clear and a record-field store all reach the same node, so
one check covers all of them; that is the argument for doing it there rather
than in `ParseStatementAST`.

## What must NOT start failing

The dialect deliberately allows conversions FPC does not, and the point of doing
this carefully is that the check must be a *whitelist of what is legal*, not a
blacklist of what is not. At minimum, before touching anything: Variant in both
directions (a Variant assigns to and from everything by design), the
Char/AnsiChar and string-family widenings, `PChar`/`^Char`/array-of-Char
interchange (see the `IsNodePChar` normalisation), enum-to-ordinal, a class to
its ancestor, an interface from a class implementing it, and every numeric
widening. `make test` and the demos are the real specification here, and this
change will find code in `lib/**` and `examples/**` that relies on laxness — that
discovery IS part of the ticket, and any such site is a Track B ticket, not a
reason to weaken the check.

Landing it behind `--strict-assign` first, defaulting off, and reading what the
full corpus says before flipping the default, is the low-risk sequencing.

## Gate

Track P's, plus a `{%FAIL}`-shaped test asserting each row of the table above is
refused with the line named, and one asserting the legal conversions listed
under "What must NOT start failing" still compile. The two runtime rows
(`i := s` printing a handle, `s := i` segfaulting) are the ones that make the
case; keep them in the ticket even after they stop compiling.

## Resolution (2026-08-24)

**Fixed. The check exists, it recovers, and the whitelist was MEASURED against
fpc 3.2.2 over a 625-pair cross-product rather than reasoned about.**

### Where it landed

Not `GenMakeAssign` as the ticket guessed — the `AN_ASSIGN` arm of `IRLowerAST`
(`compiler/ir.inc`), which is the node every assignment form funnels through
*while the AST types are still available*. `GenMakeAssign` is downstream of the
point where the two sides' kinds are still distinguishable. Same argument, one
level up: a `for` variable, a `+=`, an out-param clear and a record-field store
all reach this node, so one check covers all of them.

Three pieces:

- `AssignKindsIncompatible(dstTk, srcTk)` in `compiler/symtab.inc` — the
  whitelist, expressed as a short list of REFUSALS over kind predicates
  (`TypeIsManagedStr`, `TypeIsCharKind`, `TypeIsPlainScalar`,
  `TypeIsFrozenString`) rather than a 32x32 table. Unknown/Variant/Auto and
  identical kinds are legal up front, so the rule set only has to name the
  handle-vs-number and aggregate-vs-scalar boundaries.
- `AssignSideKind(node, out tk)` in `compiler/ir.inc` — the *conservative*
  half, and the one that makes this safe. It answers "is this node's TypeKind
  actually the kind of the value?" and says **no** for arrays (the kind is the
  ELEMENT's), by-ref/untyped params (the slot holds an address), procvars (the
  kind is the RESULT's), captured cells (one indirection away), and interfaces.
  Anything it declines is simply not checked. A false "yes" here is a rejected
  legal program; a false "no" is only a missed diagnostic, so every uncertain
  shape goes in the second bucket.
- `ErrorAtRecover` in `compiler/lexer.inc` — reports and CARRIES ON, so one
  compile lists every bad assignment instead of stopping at the first. That is
  what the new test's count assertion pins.

### The measurement

25 declared variables spanning every kind (ordinals, both char widths, both
string families, floats, pointers, PChar, two distinct records, a class and its
descendant, an interface, a set, a static and a dynamic array, a procvar, a
Variant) x 25 = **625 assignment pairs**, each its own one-line program,
compiled by fpc 3.2.2 `-Mobjfpc -O1` and by pxx before and after:

```
fpc accepts       :  99
pxx before accepts: 618
pxx after accepts : 416
pairs pxx now refuses that fpc ALSO refuses (correct tightenings): 202
pairs fpc accepts that pxx now refuses (regressions):                0
still lax (pxx accepts, fpc rejects):                              319
pairs fpc accepts and pxx refuses, ALL causes, incl. pre-existing:   2
```

Zero regressions is the number that mattered, and it was not free — the first
run had one. `Pointer := IIntf` broke, because **an interface variable is
spelled `tyRecord`** (a 16-byte fat pointer {IMT, instance}), so the
record-vs-scalar rule fired on it. That is exactly the class of thing reasoning
would not have caught, and it is why `AssignSideKind` now declines
interface-typed symbols outright. Measured, not guessed.

### A crash the check fixed on the way past

`AnsiString := UCS4Char` was accepted by `pinned` and **segfaulted at run time**
— a raw code point handed to the AnsiString runtime as a heap pointer. FPC
rejects it, for the good reason that `UCS4Char = LongWord`: it is an integer
wearing a character's name. Omitting `tyUCS4Char` from `TypeIsCharKind` turns
that crash into a diagnostic, so it needs no separate ticket. `Char` and
`WideChar` stay legal string sources (fpc accepts both; verified running, not
just compiling).

`TypeKindSpelling` also lost its `else Result := 'type'` catch-all, which had
been rendering the message as `cannot assign type to AnsiString`. Every member
of `TTypeKind` is now spelled; a kind appended to the enum and forgotten shows
up as the obviously-wrong `<unspelled type>`.

### What the corpus said

- `compiler.pas` compiles itself clean with the check active, and the
  fixedpoint converged in one round every time.
- 128 of 132 `lib/rtl` + `lib/pcl` units compile; **zero** "incompatible types"
  among the 4 that do not (they fail for the reasons they failed before).
- `examples/**`, all 45 programs, compiled by HEAD and by `pinned` in the same
  run for a like-for-like comparison: **31 ok / 14 fail on both**, zero
  "incompatible types" among the 14.

So the ticket's expectation that this would "find code in `lib/**` and
`examples/**` that relies on laxness" did not materialise — the laxness was
never load-bearing, which is why landing it on by default (rather than behind
`--strict-assign` first, as the ticket sequenced) was the right call.

### Deliberately NOT done

`i := d`, `b := i`, `i := b`, `p := i`, `i := p`. fpc rejects all five; each has
a defined meaning in this dialect (truncation, an ordinal round-trip, a
systems-language pointer/integer conversion). They are the bulk of the 319
remaining lax pairs and they belong behind the proposed `--strict-assign` flag,
which this ticket does not introduce. The FAIL test says so in a comment so
nobody "completes" the table by accident.

The sweep found exactly TWO pairs in the other direction — fpc accepts and pxx
refuses — and neither is mine: `Variant := WideChar` and `Variant := IIntf`,
both `Variant := this type not yet supported`, both on `pinned` as well as HEAD.
Filed as [[bug-p-a-variant-refuses-wide-chars-and-interfaces]]. That the whole
"pxx is stricter than fpc" column is two pre-existing entries is the strongest
single statement this measurement makes about the new check.

### Tests

- `test/test_assign_incompatible_types_fail.pas` — 13 rows, ONE program, and the
  Makefile asserts the *count* is 13, which is what proves recovery works (a
  check that halted at the first error would still satisfy a plain grep).
- `test/test_assign_compatible_types.pas` — the other half, and it RUNS, because
  "accepted" and "correct" are different claims.

Both wired into `test-core`.

### Gate

`make compiler/pascal26` (self-host fixedpoint, converged in 1 round) + both new
tests + the 625-pair differential + the RTL/PCL and examples corpora +
`tools/gate.sh quick` GREEN.

## Log
- 2026-08-24 — resolved, commit 497fc8e78.
