---
slug: bug-p-a-generic-specialisation-suffix-on-an-unknown-name-is-dropped-in-field-position
track: P
prio: 45
type: bug
status: done
owner: ""
created: 2026-09-06
found-by: frankD
blocked-by: []
summary: "`A: TNope<Byte>;` inside a record or class body leaves `<`, `Byte`, `>` UNCONSUMED, because DelphiRewriteGenericUses only rewrites a specialisation whose template it can resolve, and the field type parser has no fallback for the tokens it leaves behind. In VAR position the same source reaches ParseTypeKind, which consumes them and reports `unknown type: ` -- with an EMPTY name, because it errors on the trailing `>` rather than on `TNope`. So one type-reference position stumbles into a mislabelled diagnostic and the other drops three tokens on the floor; neither names the template. Until 76efae23e the field-position drop was SILENT -- the member-loop terminus was a bare `else Next` and stepped over all three, so the field was declared with the specialisation discarded. Found by the catch-all census over the fpc-testsuite corpus (trtti12.pp, trtti16.pp: `A: TArray<byte>;` with no `uses SysUtils`, which is where pxx keeps TArray). The fix is one type-reference path that recognises `ident <` as a specialisation attempt and refuses it BY NAME in both positions."
---

# An unresolved `<...>` suffix is consumed in var position and dropped in field position

Measured 2026-09-06, probe build at `7ac35fe566ff` (behaviourally the
pre-narrowing terminus), then confirmed against the narrowed one.

```pascal
{$mode delphi}
type TRec = record A: TNope<Byte>; end;   { field:  <, Byte, > reach the member-loop terminus }
var  a: TNope<Byte>;                      { var:    consumed, then `unknown type: ` (empty name) }
```

| position | `<Byte>` consumed? | diagnostic |
| --- | --- | --- |
| record/class field | **no** | pre-`76efae23e`: none, tokens stepped over. After: "this token is not a record member", pointing at `<` |
| plain `var` | yes | `unknown type: ` — **empty**, because it errors on the trailing `>`, not on `TNope` |

Neither message names `TNope`, and the field-position one names the wrong
question entirely.

## Why it only bites an UNKNOWN template

`DelphiRewriteGenericUses` (`pasparser_generic.inc:1616`) sweeps the token
stream and rewrites a Delphi-surface `TFoo<Byte>` into the mangled
specialisation **when it can resolve `TFoo`**. A declared template is therefore
never seen by either type parser in its `<...>` form:

```pascal
type
  TBox<T> = record V: T; end;
  TRec    = record A: TBox<Byte>; end;   { compiles and runs — verified }
```

So the two paths only diverge on the name the rewrite could not resolve, which
is exactly the case where a good diagnostic matters most.

## Where the corpus hit it

`library_candidates/fpc-testsuite/tests/test/trtti12.pp` and `trtti16.pp`,
`A: TArray<byte>;`. `TArray` is real but lives in `lib/rtl/sysutils.pas:79`,
and neither file has `uses SysUtils` — FPC reaches it through `System`. That
part is a known, deliberate placement (see the comment at sysutils.pas:87) and
is NOT this ticket; it is merely how the corpus produced an unresolvable
template name.

## The fix

One type-reference path that treats `ident <` as a specialisation attempt
wherever a type may appear, and refuses an unresolvable one with the template
NAME in the message. That deletes the divergence rather than teaching the field
parser a second copy of the var parser's stumble —
`devdocs/dev/normalise-dont-special-case.md`.

Check while writing it: the var path's empty `unknown type: ` is the same
defect wearing a different coat, so fixing only the field side leaves a
mislabelled error in place and closes nothing.

## Provenance

Catch-all census over the fpc-testsuite corpus, probe logging every token
reaching either member-loop terminus:
**`processed=2294  compiled=803  refused=1491  fires=12`** across four files.
Read that as twelve fires over the **803 files the probe actually reached** —
1491 never got there (`{ %FAIL }` rows and units, which pxx cannot compile
standalone), and a construct appearing only in those is invisible to this run.
See [[a-file-that-fails-early-is-an-absence-not-a-zero]].


## 2026-09-06 — RE-MEASURED: the defect is gone in all three positions; what is left is a different ticket

Tree `9341b19ac`, compiler `8b2d6f26c7b2`, fpc 3.2.2 `-Mdelphi`. Group 23 took
this and measured before reading, which is how the split below was found.

**The stated defect does not reproduce.** `A: TNope<Byte>;`:

| position | pxx now | the ticket's claim |
| --- | --- | --- |
| record field | `unknown type: TNope` | three tokens dropped, silent |
| var | `unknown type: TNope` | `unknown type: ` with an EMPTY name |
| class field | `unknown type: TNope` | (not measured then) |

All three refuse **by name**, which is exactly this ticket's own *Done when*:
*"one type-reference path that recognises `ident <` as a specialisation attempt
and refuses it BY NAME in both positions."* And a specialisation whose template
IS resolvable still compiles and runs (`TArr<T>` declared locally: field read
and written, `9 1`).

### What is left is NOT this defect, and it needs its own owner

The corpus rows this ticket was found through — `trtti12.pp`, `trtti16.pp` —
still fail, on a different cause: **`TArray<T>` lives in SysUtils here and in
the SYSTEM unit in FPC**, so a file naming it without `uses SysUtils` is refused
by name, correctly, for a type that ought to be ambient. Filed as
`bug-a-tarray-is-not-ambient-so-a-unit-that-names-it-without-uses-sysutils-is-refused`
(Track A — pxx has no `lib/rtl/system.pas` and its ambient types are
compiler-side, so it is not a lib move).

**And the population claim that put TArray in SysUtils is inverted between two
corpora**, measured while checking: 7 of 7 rtl-generics files naming `TArray<>`
use SysUtils; **0 of 6** fpc-testsuite files do. Structural rather than luck —
rtl-generics code uses generic COLLECTIONS, which need SysUtils anyway, so
`TArray` arrives free; testsuite files exercise `TArray` itself and carry no
more `uses` than the feature requires. The comment in `lib/rtl/sysutils.pas` is
corrected in the same commit, since it asserted the opposite.

Closing: the parse defect is fixed, the residual is filed with an owner and a
measurement, and leaving this open would attach a fixed diagnosis to a live
symptom.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 48a18d6ec.
