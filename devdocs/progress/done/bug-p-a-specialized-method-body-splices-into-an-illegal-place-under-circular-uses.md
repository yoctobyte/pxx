---
prio: 55
track: P
status: done
summary: "RESOLVED 2026-09-09. THIS TICKET NAMED THE WRONG SUSPECT: FlushPendingClassSpecializations never runs in the repro -- measured with a channel added for it (PXXDBG=p.specsplice), the failing compile prints no flush event, because nothing was ever pended. The splice site is BufferGenericMethod, which streams a body for every registered specialization of the template while asking neither which unit registered it nor whether that unit is visible from here. Order is the defect: unit A's implementation says `uses B` ABOVE A's own template bodies, so B is parsed NESTED INSIDE A; B specializes A's template before A's method bodies are walked, so nothing is buffered, the GenericMethodCount>0 pend does not fire, and the body is streamed much later into A -- where B's implementation-private specialization name does not exist. The pre-scan cannot help: it walks the same section in the same order and hits `uses` first too. BOUNDARY NARROWER THAN THE TITLE: only ONE side need specialize; one-way cross-unit specialization was always fine, so circularity alone is the discriminator. Fixed by BufferTemplateMethodsAhead (buffer the template's methods ahead of the parser when a nested `uses` forces the question, so the existing pend/flush streams at the specialization site where the name IS visible), plus two once-only guards -- GenericMethodSrcOff dedupes the arena copy, SpecMethodsDone stops the second stream -- because the before/after split assumed the two orders are exclusive and under a cycle both fire for one pair. Fixture test_circspec26, three arms, each template adding a DIFFERENT constant to one input so a wrong materialisation prints a wrong number; the PINNED compiler refuses it with this ticket's own shape, so the fixture can fail. fpc 3.2.2 agrees byte for byte. Corpus row tgeneric91.pp burned, verified byte-identical to fpc before deleting."
owner: frankH
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

## 2026-09-08 — the channel the fix needs is a COORDINATED resource

Looked at, not attempted, so the next reader knows what the "parallel channel on
the splice" costs before starting.

The banked diagnosis is right that the spliced run has to carry its host unit to
the HEADER. Two ways to carry it, and both touch something shared:

- **A token-index range table**, in the manner of `PasSrcRangeStart`/`PasSrcRangeId`
  (`dbg_filetable.inc`), which already maps token index to source key for exactly
  these splices. Cheapest to write, and it inherits whatever that table's answer
  is to later inserts shifting indices under it.
- **A 14th token-parallel array**, which `ShiftTokParallel` must then move. There
  are thirteen today and the routine's own comment records that an earlier
  version moved exactly one of eleven; the symptom of missing one is not at the
  edit (`{$R+}` silently stops being in force inside a lifted body).
- **A marker token** in the stream, which shifts with everything for free and
  needs no parallel array at all — but a new token kind is the ONE thing
  CLAUDE.md says to coordinate on by message (`token/node numbering in
  lexer.inc / defs.inc`).

So the marker-token shape, which is otherwise the most robust of the three, is
the one that cannot be landed unilaterally. That is a scheduling fact rather
than a design objection, and it is why this was left rather than half-done.

## Resolved 2026-09-09 — and this ticket's named suspect was not on the path

**The diagnosis above is wrong in its first sentence and in its last section**,
and it is worth saying which, because both readings were reasonable from the
`near:` window alone.

`FlushPendingClassSpecializations` **never runs** in this repro. Measured with a
channel added for it (`PXXDBG=p.specsplice`): the failing compile prints no
flush event at all, because nothing was ever *pended*. The anchor choice this
ticket sends the reader to inspect is not reached.

### What actually happens

`BufferGenericMethod` is the splice site. It streams a body for **every
registered specialization of the template**, asking neither which unit
registered it nor whether that unit is visible from here — and it matches on the
template's **name**, which `SpecTemplateIdx`'s own comment already says is not an
identity.

The order is the whole defect. Unit A's implementation says `uses B` on a line
**above** A's own template bodies, so B is parsed **nested inside** A's
implementation. B specializes A's template — and A's method bodies have not been
walked yet, so nothing is buffered, so the `GenericMethodCount > 0` pend does not
fire and B materialises nothing. Later, when A's suspended parse resumes and
finally reaches `class procedure TG1.Test`, `BufferGenericMethod` streams
`class procedure TG1L.Test; ...` into **A**, where `TG1L` — declared in B's
implementation section — does not exist.

The pre-scan does not help and it is worth recording why, because it looks like
it should: the implementation pre-scan walks the same section in the same order
and hits `uses` first too.

**The boundary is narrower than this ticket's title.** Only ONE side needs to
specialize; "two units each specialize the other's" is the shape it was found
in. Measured, one-way cross-unit specialization was always fine (`oneway` arm) —
circularity alone is the discriminator.

### The fix

The bodies must be materialised where the specialization is **visible**, which
means buffering the template's methods **ahead** of the parser when a nested
`uses` forces the question. `BufferTemplateMethodsAhead` does that, and the
existing pend/flush then streams at the specialization site, inside B.

Two once-only guards, because the "before/after split" that kept each (method,
specialization) pair materialised exactly once assumed the two orders are
exclusive, and under a cycle they are not — both halves fire for one pair:
`GenericMethodSrcOff` dedupes the arena copy when the suspended parse walks over
a body already read ahead, and `SpecMethodsDone` stops the second stream.

`GenericMethodSrcOff` is keyed on the source offset, **not** the token index,
because a splice earlier in the stream shifts every index after it — and the
lookahead exists precisely because splices are happening.

### Verified

`test_a_specialized_body_materialises_under_circular_uses` (fixture
`test_circspec26`), three arms: the mutual pair, the one-sided pair, and the
plain call. Each template's `Bump` adds a **different** constant to one input of
20, so a body materialised against the wrong template prints 21/22/23 wrongly
rather than passing — the right answer cannot collide with another arm's.

**The fixture can fail:** the PINNED compiler, which predates the fix, refuses it
with this ticket's own shape — `expected ':' before '.'`, near
`; end ; class function TGenALong >>> . Bump (`.

fpc 3.2.2 runs all three arms and agrees byte for byte.

**Corpus row burned:** `tgeneric91.pp` is out of `test/pascal-conformance/pxx.skip`.
Verified before deleting rather than trusted: it compiles under pxx, and its
output is BYTE-IDENTICAL to fpc's (`TSomeGeneric2<System.LongInt>` /
`TSomeGeneric1<System.LongInt>`), both exiting 0. It is `%NORUN`, so only the
parse was required; it runs anyway.

Gate GREEN, FPC seed canary PASS — which matters here, since the fix adds
routines called above their definitions.

Log: fixed in `compiler/pasparser_generic.inc` + `compiler/defs.inc`, commit
1c16d4523. That commit also burns `tgeneric91.pp` from
`test/pascal-conformance/pxx.skip` and adds fixture `test_circspec26`; the close
is this file's move to `done/` in the same commit.
