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
