---
prio: 55
track: P
status: open
summary: "When two units each specialize the other's generic through mutually recursive implementation-section `uses`, the specialized method bodies are spliced somewhere the parser will not accept a method implementation: `expected 'begin' before '.'`, near `; end ; class procedure TSomeGeneric1LongInt >>> . Test ;`. Reduced to 30 lines, two units, no corpus. Was hidden behind bug-p-a-cross-unit-specialized-method-cannot-see-its-own-parameters until 2026-09-07; that fix moved the wall here and did not reach it. The conformance row is tgeneric91.pp."
---

## Repro

Two units, each specializing the other's template from its **implementation**
section, which is the only place a circular `uses` is legal:

```pascal
unit ua2;
{$mode objfpc}{$H+}
interface
type generic TG1<T> = class class procedure Test; end;
     TC1 = class class procedure Test; end;
implementation
uses ub2;
type TG2L = specialize TG2<LongInt>;
class procedure TC1.Test; begin TG2L.Test; end;
class procedure TG1.Test; begin WriteLn('g1 ', Self.ClassName); end;
end.
```

`ub2` is the same file with 1 and 2 swapped. A program that `uses ua2, ub2` and
calls `TC1.Test; TC2.Test;` runs under fpc 3.2.2 and prints two lines.

```
pascal26:16: error: expected 'begin' before '.'
  in: .../ua2.pas
  near: ; end ; class procedure TG1L2 >>> . Test ;
```

`library_candidates/fpc-testsuite/tests/test/tgeneric91.pp` is the same shape
with `{ %NORUN }`, so only the parse has to succeed there.

## What is known

The diagnostic's `near:` window shows the splice landing immediately after a
routine's `end;` and being read as a fresh declaration in a context that will
not take `class procedure X.Y;` — i.e. the anchor, not the tokens. Both units
are mid-implementation when the other's specialization is materialised, so
`FlushPendingClassSpecializations`'s two anchors (`UnitImplAnchor` when
`InInterface`, otherwise the parse cursor) are being chosen for a unit that is
not the one the cursor is in.

## Where to start

`FlushPendingClassSpecializations` (`compiler/pasparser_generic.inc`) and the
`PendingSpec*` queue that feeds it. The reason it is not obvious from reading:
the queue is drained relative to whichever unit reaches the flush first, and
under circular `uses` that is not the unit whose token stream holds the anchor.
`PXXDBG=p.specunit` prints a specialized body's unit identities and is the
channel that made the sibling defect legible.

## Not this ticket

The parameters/Result/Self visibility defect this was hiding behind is fixed:
[[bug-p-a-cross-unit-specialized-method-cannot-see-its-own-parameters]]. A
NON-circular library shape — unit B specializes unit A's template, A does not
use B — works and has a fixture (`test_xunitparams26`).

## 2026-09-08 — MECHANISM, measured. It is NOT the anchor.

Diagnosis banked rather than fixed: the fix is a visibility design question, not
a splice position, and the ticket's own "where to start" points at the wrong
routine. Measured at compiler `1defef6b62d0`.

**The class the body names is INVISIBLE at the point the body is spliced, and
correctly so.** `TSomeGeneric1LongInt` is minted in `ugeneric91b`'s
IMPLEMENTATION section, which is that unit's private business — the rule
`DeclVisibleSect` enforces for every declaration table. The body is streamed
into `ugeneric91a`, where the name cannot resolve, so
`class procedure TSomeGeneric1LongInt.Test;` is not read as a qualified method
implementation at all: the parser takes `class procedure TSomeGeneric1LongInt`
as a header and hits the `.`. **`expected 'begin' before '.'` is a NAME
RESOLUTION failure wearing a syntax diagnostic**, which is why reading the
`near:` window suggests an anchor.

**The probe that settles it, and it needs no compiler change.** Add an ordinary
declaration of that type to `ugeneric91a`'s own implementation:

```pascal
class procedure TSomeClass1.Test;
var probe: TSomeGeneric1LongInt;     { <- added }
```

```
pascal26:25: error: unknown type: TSomeGeneric1LongInt
  in: ugeneric91a.pp
```

A plain `var` declaration cannot fail for an anchor reason. The name is simply
not visible there, four lines above where the splice lands.

### Which routine actually streams it

Not `FlushPendingClassSpecializations`. `BufferGenericMethod` — when
`ugeneric91a` finally reaches `class procedure TSomeGeneric1.Test`, it walks
`Specializations[]` for every row naming this template and streams the body once
per row, at the CURRENT cursor. The row for `TSomeGeneric1LongInt` was
registered while `ugeneric91b` was being parsed (from a's `uses`), and that walk
asks nothing about visibility. The pend/flush path never fires here at all,
because when `ugeneric91b` specializes a's template a's own method bodies are
not buffered yet, so `GenericMethodCount > 0` is false.

### Why the obvious fixes are wrong, so the next reader does not spend the hour

- **Move the splice into `ugeneric91b`.** It is fully parsed by then — `a`'s
  implementation `uses ugeneric91b` completes before line 29 is reached.
- **Widen the qualified-method-header lookup to see implementation-private
  specializations of other units.** Fixes this and admits a genuinely unrelated
  impl-private class of the same name; that is a silent wrong binding, and the
  wrong-binding direction is the one this file's history keeps punishing.
- **Make `BufferGenericMethod` skip rows it cannot see.** The body then never
  exists and `TSomeClass2.Test` calls a method with no implementation, which is
  a link failure instead of a parse failure. No better.

### The shape that probably is right

The machinery already half exists: `ParseSubroutine` swaps `CurrentUnitIdx` to
`SpecTemplateDeclUnit(...)` and keeps `SpecBodyHostUnitIdx` for the
specialization's own unit, precisely so a specialized body resolves in TWO
scopes — see `bug-p-a-cross-unit-specialized-method-cannot-see-its-own-parameters`.
**It runs too late for this.** That swap happens once `methOwnerCi >= 0`, i.e.
after the qualified header has resolved, and here the header is what fails. The
body needs its host unit identity available at the HEADER, which means the
spliced token run has to carry it — a parallel channel on the splice, in the
manner of `PasSpliceTokFile`, rather than a global set at parse time.

Corpus: `tgeneric91.pp`, still `gap:`. `PXXDBG=p.specunit` prints the two unit
identities for bodies that get far enough to have them; this one does not.
