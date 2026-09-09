---
slug: compat-p-at-over-a-method-pointer-field-yields-the-fields-address-not-the-methods
title: "`@o.Ev` where `Ev` is a method-pointer FIELD yields the field's address; FPC's Delphi mode yields the method's"
track: P
prio: 30
type: compat
status: low-prio
owner: ""
created: 2026-09-06
found-by: frankA
blocked-by: []
summary: "MODE-ONLY, and every table here compared two different languages. Measured 2026-09-09 with BOTH compilers in BOTH modes across three operand shapes: under {$mode objfpc} pxx and fpc 3.2.2 agree EXACTLY -- `@` yields the address for an of-object field, an of-object local and a plain procedural local alike. The divergence exists only under {$mode delphi}, where fpc yields the VALUE for all three while pxx yields the value for a plain procvar and the ADDRESS for the two of-object shapes. Earlier tables compared pxx in its DEFAULT mode against `fpc -Mdelphi`, which is not a comparison; so frankH's `pxx is inconsistent with itself` is correct but holds only inside delphi mode, and objfpc -- what this project targets -- has no defect at all. Corpus census done: the only reachable-corpus code writing `@<of object procvar>` for the value sits under fpc-testsuite/tests/test/jvm/ (tpvardelphi.pp, unsupported.pp), JVM-target files outside any population we build, and the one non-JVM delphi-mode hit (tprocvar3.pp) uses `@Class.Method` and `@objectvar`, neither of which diverges. Real, delphi-mode only, needs a two-part change (`@` retargeted AND `@@` added, refused today), ZERO reachable consumers -- moved to low-prio on CLAUDE.md's rule that compat ranks by how much real code uses it. Reopen with a delphi-mode program we actually compile."
---

# `@` over a method-pointer field: address or value?

Found while fixing
[[bug-p-at-over-a-class-base-consumes-only-one-selector]], by a probe that
used a method-pointer field as the chain's last member and so measured two
things at once. The selector-walk defect is fixed; this is what was underneath.

## The measurement

```pascal
type TNotify = procedure(S: TObject) of object;
     TOwner = class public Ev: TNotify; end;
var o: TOwner; pp: Pointer;
begin
  o := TOwner.Create;             { Ev is never assigned }
  pp := @o.Ev;  WriteLn(pp = nil);
end.
```

| compiler | answer | reading |
| --- | --- | --- |
| pxx at `182dd5cad3f2` | `FALSE` | `@` took the FIELD's address |
| pxx at **pin v404** | `FALSE` | pre-existing, not from this week |
| fpc 3.2.2 `-Mdelphi` | `TRUE` | `@` read the procedural variable's VALUE, which is nil |

A typed `pe: ^TNotify` target answers identically, so it is not about the
result type either.

## Why it is filed and not fixed

**Delphi's rule is that `@procvar` is the VALUE and `@@procvar` is the
address.** Adopting it is a one-line change in intent and a behaviour change for
every existing use of `@<procedural-field>` in this tree — and that population
has not been counted. `lib/pcl`'s event wiring and anything doing
`p := @obj.OnSomething` would silently change meaning rather than fail to
compile, which is the worst shape a compat change can have.

**So the first step is the census, not the fix:** how many sites take `@` of a
procedural-typed field or variable, and what do they do with the result.

Also unmeasured, and it decides how much this matters: whether `@@` is accepted
at all today. If it is not, there is currently no spelling for "the address of
this method pointer", and adopting FPC's rule would remove the only one.

## What it is NOT

Not the selector walk. `@o.Ev` is ONE dot and diverges on its own; the
multi-selector spellings inherit it rather than cause it. And not a defect in
the fix that found it — `test_at_over_a_class_base_walks_every_selector`
deliberately ends every chain in a DATA field for exactly this reason, so its
rows measure the walk and nothing else.


## 2026-09-06 — THE CENSUS THIS TICKET SAID WAS THE FIRST STEP (frankB, Group 21)

The body says *"NOT ESTABLISHED: which spelling real code wants ... that census
is the first step and it is why this is filed rather than fixed."* Run at
`1d9d36ff3`. **The in-tree population that a Delphi-rule change would silently
reinterpret is ZERO**, so the blocker this ticket filed itself behind is
discharged — but read the aperture before treating that as licence.

### Processed / matched / classified — and the fourth number is the aperture

| | |
| --- | --- |
| Pascal sources scanned | 2478 |
| `@` applied to a dotted designator | 323 (`lib` 32, `examples` 36, `compiler` 78, `test` 177) |
| of `lib` + `examples`, name-matched as event/procedural-looking | 14 |
| of those 14, confirmed by opening the declaration | **14 are METHODS, 0 are procedural fields** |

Every one of the 14 is the same idiom — `PaintBox.OnPaint := @Handler.OnPaint`,
where `OnPaint` is declared `procedure OnPaint(Sender: TControl; Canvas:
TCanvas)` on the handler class. **The procedural field is the assignment's LEFT
side; the `@` operand is a method**, and taking a method's address is not the
diverging construct. Verified by reading the declaration in `life.pas`,
`triangle.pas`, `solitaire_gui.pas`, `raytracer_gui.pas`, `mandelbrot_gui.pas`.

The remaining `lib` targets are `@c.Seq`, `@e.DoneWord`, `@e.State`,
`@f.DefBuf`, `@h.TidWord`, `@lc.MonWord`, `@m.State`, `@obj.Method`, `@Self.M` —
data fields, where `@` means the address and is correct today, and methods.

### The aperture, stated because a zero is worthless without one

- **The classifier is a regex over `@ident.ident…`.** It cannot see
  `@(expr).field`, `@a[i].field`, or a spelling broken across lines. Those are
  rarer, not absent.
- **`compiler/` (78) and `test/` (177) were NOT classified.** They are ours to
  update, so they bound the work rather than the risk — but a change would still
  have to build them, and this census does not say it will.
- **Name-based selection chose the 14; inspection confirmed them.** A procedural
  FIELD named unlike an event — `@r.f`, `@p.b` — would not have been selected.
  So the strong claim is about the 14, and the claim about the other 54 is only
  "they did not match a pattern", which is weaker evidence than reading them.
  **Zero-because-absent and zero-because-unselected are not distinguished here.**

### What it means for the fork

The reason this was filed rather than fixed — *"matching FPC changes what
`@o.Ev` means for every existing user of that spelling in this tree, and that
population has NOT been counted"* — no longer holds: **in `lib` and `examples`
there are no existing users of that spelling at all.** The cost side of the
trade-off is empty, which does not by itself make the change right; it moves the
decision onto the value side, where the argument is external code (Delphi and
FPC sources that spell the procedural-variable read `@p`) and not ours.

Left open deliberately, and left at its prio: a change with zero in-tree
consumers is cheap AND low value, and this ticket is now blocked on wanting it
rather than on not knowing.

## 2026-09-09, frankH — the census is done, and it inverts the conclusion

This ticket says *"the first step is the census, not the fix"* and names two
unmeasured things. Both are measured now. **The blast radius in this tree is
zero, and the divergence is narrower and more self-inconsistent than recorded.**

### 1. Is `@@` accepted today? NO — and that changes the shape of the fix

    pxx:  pp := @@o.Ev;   ->  pascal26:8: error: expected identifier after @
    fpc:  @o.Ev  nil=TRUE     (the VALUE)
          @@o.Ev nil=FALSE    (the ADDRESS)

The ticket asked this and called it decisive; it is. FPC carries the full
Delphi PAIR. pxx accepts only `@`, and gives it the ADDRESS meaning — so `@` is
currently the only spelling for the address, and adopting FPC's rule for `@`
ALONE would leave no way to spell it at all. **This is a two-part change —
retarget `@` and add `@@` — not the one-line change in intent the ticket
assumed.** Doing half of it is strictly worse than doing none.

### 2. The at-risk population, counted: ZERO sites

`@` over a dotted name appears 67 times in `lib/` + `examples/`. Every one is
either a data field (`@m.State`, `@e.Seq` — 14 + 6, unaffected: this is about
PROCEDURAL operands) or a METHOD reference. The 14 that look like the feared
shape are the ones to be careful with:

    examples/life/life.pas:418:  PaintBox.OnPaint := @Handler.OnPaint;
    examples/gl/triangle.pas:210: Timer.OnTimer  := @Handler.OnTimer;
    examples/solitaire_gui:431:   pm.Code := @H.OnPaint;  pm.Data := H;

The NAME says event field; the declaration says otherwise —
`life.pas:30` is `procedure OnPaint(Sender: TControl; Canvas: TCanvas);`, a
METHOD on the handler class. `@Handler.OnPaint` is `@obj.Method`, the
AN_METHODREF path, which this change does not touch. **Checked by reading the
declaration, not by reading the name, because here the name is wrong in exactly
the direction that would have inflated the census.**

**And `lib/pcl`, which the ticket names by name as the thing that would
silently change meaning, is not in the population at all:**

    lib/pcl/extctrls.pas:37:    FOnPaint: TMethod;
    lib/pcl/extctrls.pas:44:    property OnPaint: TMethod read FOnPaint write FOnPaint;

pcl's events are `TMethod` **records** behind properties, not procedural-typed
fields. `gtk3widgets.pas:527` reads one as a value (`m := paintBox.OnPaint`)
with no `@` at all. So the feared silent-meaning-change has no sites.

### 3. The divergence is NARROWER than the title, and pxx is inconsistent with itself

The title says "method-pointer FIELD". Measured across three operand shapes:

| operand | pxx | fpc |
| --- | --- | --- |
| `of object` FIELD (`@o.Ev`) | address | **value** |
| `of object` LOCAL (`@lv`) | address | **value** |
| plain procedural LOCAL (`@pl`) | **value** | **value** |

So it is not about fields — a local method-pointer diverges identically — and
**pxx already implements Delphi's rule for ordinary procedural variables.** The
gap is exactly the `of object` case, in both storage classes. That reframes the
work: not "adopt a foreign rule and hope", but "extend a rule this compiler
already applies to one more type, where it is currently inconsistent with
itself".

### What is still NOT established, and it is now the only open question

Whether any real corpus program wants `@<method-pointer>` to mean the address.
Nothing in THIS tree does. That is a fact about this tree and not about
`rtl-generics` or the Pascal corpora, which is where the population that would
actually break lives. Someone adopting this should grep those before landing,
and should land `@@` in the same commit or not at all.

Not fixed here deliberately: the census was the stated blocker, the census is
what was missing, and the remaining decision is a compat change whose sole
justification is FPC parity — which CLAUDE.md ranks by *how much real code uses
it*, and that is the one number still absent.


## 2026-09-09 (frankD) — THE MODE WAS NEVER STATED FOR PXX, AND IT IS THE WHOLE ANSWER

Every table in this ticket compares **pxx in its default mode** against **`fpc
-Mdelphi`**. Those are two different languages, and the comparison is what made
the divergence look unconditional. Measured with both compilers in both modes,
one source, three operand shapes, using the `nil` probe (`@x = nil` is TRUE for
the VALUE of an unassigned procvar, FALSE for the address of the variable):

| mode | operand | fpc 3.2.2 | pxx |
| --- | --- | --- | --- |
| **objfpc** | of-object FIELD | address | address |
| **objfpc** | of-object LOCAL | address | address |
| **objfpc** | plain procedural LOCAL | address | address |
| delphi | of-object FIELD | **value** | address |
| delphi | of-object LOCAL | **value** | address |
| delphi | plain procedural LOCAL | value | value |

**In objfpc mode there is no divergence at all** — nine of nine cells agree, and
objfpc is what this project targets. `ir.inc`'s `IRProcVarAutoCall` states that
policy in as many words: *"this project targets FPC, with Delphi behaviour only
under {$MODE DELPHI}"*. frankH's "pxx is inconsistent with itself" is correct and
is a statement about delphi mode only; the section above presents it
unconditionally.

The plain-procvar cell really is the VALUE and not a collision: with `pl :=
Real_` assigned, pxx and fpc both answer `@pl = @Real_` TRUE and `@pl` non-nil,
and both answer nil after `pl := nil`. The nil row alone could not separate "the
value" from "a broken address", which is why the assigned row is here.

### The corpus census this ticket called its only remaining question

Delphi-mode files using `@`: **21** in `library_candidates/fpc-testsuite`, 3 in
`rtl-generics/src`. Those that take `@` of an `of object` operand:

- `tests/test/jvm/tpvardelphi.pp:93` — `@shortpvar1 := @shortpvar2;` over two
  `of object` vars, the file's own comment saying it must copy the procedure
  pointer and not the instance. **Exactly the construct, wanting the Code half.**
- `tests/test/jvm/unsupported.pp:57` — `if @m2 = nil` on an `of object` local.

**Both sit under `tests/test/jvm/` — JVM-target tests, outside any population we
compile.** That is the aperture and it is the whole result: the two files that
prove Delphi-mode code really does write this are the two we will never build.

The one non-JVM delphi-mode hit, `tests/test/tprocvar3.pp`, uses `@to1.test1`
(`@Class.Method`, the AN_PROCADDR path) and `@o1` (the address of an object
VARIABLE). Neither diverges. pxx refuses that file anyway, on old-style `object`
constructors — an unrelated open ticket.

### Ranking, and why this is a move rather than a fix

Real, reproducible, delphi-mode only, needs `@` retargeted AND `@@` added in one
commit (frankH measured that `@@` is refused today, and half the change is worse
than none), and **zero reachable consumers**. CLAUDE.md ranks compat by how much
real code uses it and the answer here is none that we can build. `low-prio/` —
real, probably correct, not worth ranker attention — rather than `rejected/`,
which would claim the report is wrong. It is not wrong; it is narrow.

**Reopen it with a delphi-mode program we actually compile.** That is the one
missing piece of evidence, and it is now precisely stated instead of being "the
census".

### One near-miss, recorded because it would have been a confident wrong fix

`IRProcVarAutoCall`'s comment carries a measured FPC table whose last row reads
`Assigned(fp), @fp | address | address`, which against the table above looks
flatly wrong for delphi mode. It is not. That table's columns contrast **CALL**
against **address** — "is the bare procvar auto-called" — so "address" there
means "yields a pointer rather than calling", not "the address of the variable".
Read as the latter it becomes a bug report against a correct comment.
**The disambiguator is the column header, two lines above the row**, and a row
quoted without it reads as the opposite claim.
