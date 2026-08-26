---
summary: "Typed constants: `const N: T = v` fails for a PChar, for a nested aggregate initialiser, and gives a string constant no storage -- one declaration path, four filed symptoms"
type: bug
track: P
prio: 70
---

# Typed constants — one declaration path, four filed symptoms

**Umbrella, opened 2026-08-26.** Five tickets were filed against
`ParseConstSection` / the `PendingInit*` machinery in
`compiler/pasparser_decl.inc` between 2026-08-20 and 2026-08-26. They are one
piece of work, and two of them were the same defect reported twice.

## Why these are one ticket

Every row below is `const NAME: T = value` failing in the **declaration**
parser. The expression contexts for the same values all work — that is the
point, and it is what makes this a single machinery gap rather than a set of
type-conversion bugs. `bug-single-char-literal-as-pchar-argument-segfaults`
already fixed every *expression* context a one-char literal reaches; its own
write-up says the typed-CONST declaration "is a different machinery and was not
touched". This is that machinery.

| what the declaration says | today |
| --- | --- |
| `const GP: PChar = '-'` | compiles, then **SEGFAULTS** (folds to the ordinal) |
| `const KC: PChar = 'konst'` | `Expected: begin, but got: konst` |
| `const A: array[0..1] of PChar = ('-', '--')` | `too many array constant elements` |
| `const S: string = 'a'` then `S := 'b'` | `undefined variable (S)` — no storage at all |
| `const CN: TNest = (p: (x: 1; y: 2); ...)` | `not a constant` (nested RECORD field) |
| `const CR: TR = (a: ((x:1;y:2),(x:3;y:4)); ...)` | `not a constant` (array-of-RECORD field) |

Three distinct gaps in one path:

1. **the value's TYPE** — a pointer target is not among the kinds the typed-const
   arm accepts, so a string literal against `PChar` either fails to parse or
   (at one character) folds to an ordinal and is accepted as a pointer. That
   last row is the dangerous one and sets this umbrella's priority: it compiles
   and segfaults.
2. **the value's SHAPE** — the record-constant arm handles an array-valued field
   and an array-of-record, but cannot recurse into a nested *aggregate*
   initialiser, so it reaches the inner `(x: 1; y: 2)` and reports `not a
   constant` on the identifier `x`.
3. **the constant's STORAGE** — a typed string constant is registered in the
   StrConst table rather than as a variable, so `{$WRITEABLECONST ON}` cannot
   work for it. The tell is that the diagnostic is a *name-resolution* error,
   not "cannot assign to a constant": there is no storage, not read-only storage.

## Duplicate, merged

`bug-p-a-typed-pchar-const-cannot-be-initialised-from-a-literal` (filed
2026-08-26, prio 70) and `bug-p-a-typed-constant-of-pchar-type-is-a-parse-error`
(filed 2026-08-24, prio 55) are the **same defect**: the later one's second row
IS the earlier one's whole repro, and it adds the one-character segfault case.
Both are preserved below; the later one subsumes the earlier.

That duplication is itself filed, as
[[bug-the-queue-makes-filing-a-duplicate-the-path-of-least-resistance]].

## How to take it

Do **not** fix one row. The 2026-08-24 ticket already said so and listed the
shape family to check first — `PChar`, `Pointer = nil`, `array[0..1] of PChar`,
a record with a PChar field. Per `devdocs/dev/root-cause-over-microfix.md`,
count the mechanisms before choosing: three gaps in one parser is the shape
where the overhaul is the smaller job, because it deletes cases rather than
adding a fourth.

## Gate

`make compiler/pascal26` + each row above diffed against fpc 3.2.2 +
`tools/gate.sh quick`.

---

# The folded tickets, verbatim

Each section below is a ticket that was filed separately and is now
part of this one. Nothing is summarised away: the repro tables, the
measured oracle output and the located source lines are the reason
these are worth keeping, and they are reproduced unchanged.

## A typed `PChar` const cannot be initialised from a string literal

*(was `bug-p-a-typed-pchar-const-cannot-be-initialised-from-a-literal`, prio 70)*

# A typed `PChar` const cannot be initialised from a string literal

Found 2026-08-26 by Track P while fixing
`bug-single-char-literal-as-pchar-argument-segfaults`. That fix covered every
*expression* context a one-char literal reaches (argument, method argument,
overload, assignment, comparison); the typed-CONST DECLARATION is a different
machinery (`PendingInit*`) and was not touched.

## Repro — three shapes, all broken, one of them silently

```pascal
program d;
const GP: PChar = '-';
begin Writeln(GP); end.
```

| shape | FPC 3.2.2 | pxx (HEAD, 2026-08-26) |
| --- | --- | --- |
| `const GP: PChar = '-'` | prints `-` | **compiles, then SEGFAULTS** |
| `const GP: PChar = '--'` | prints `--` | `error: unexpected token` |
| `const A: array[0..1] of PChar = ('-', '--')` | prints `-` | `error: too many array constant elements` |
| `const A: array[0..1] of PChar = ('--', '--')` | prints `--` | same error |

The one-character row is the dangerous one and the reason this is prio 70
rather than 55: it is accepted, because the literal folds to its ORDINAL and
an ordinal is a perfectly good initialiser for a pointer-sized slot. The
program then dereferences address 45. The two-character rows at least refuse.

## Mechanism (partly measured)

`compiler/pasparser_decl.inc`, the scalar typed-const arm (~2288, "SCALAR typed
const: `const P: Pointer = @Something`"): its own comment says *"The string arm
cannot fire here — a string-typed const is handled well above this point"*, so
a pointer-typed const falls to `TryParseInitValForm` / `ParseInitValTk`, which
know `@proc` / `@var` / an ordinal and nothing else. A one-char literal IS an
ordinal there; a multi-char literal is not a token either of them expects.

The array arm is `compiler/pasparser_decl.inc:2002`/`2012` — the flat element
tally counts differently from what the parser then consumes for a literal
element.

A fix needs a new `PendingInit` kind that emits a data-section relocation to
the interned literal's character data (the `+8` past the length prefix), which
is the same address the argument path now passes.

## Sibling check while fixing

The parameter-default form is filed separately as
`bug-p-a-string-literal-is-refused-as-a-pchar-parameter-default` — same
"a literal must become a pointer to its data" rule, a third machinery.

## Gate

Track P: `make compiler/pascal26` (self-host fixedpoint) + all four rows above
matching FPC. Add them to `test/test_char_literal_to_pchar_param.pas`, which
already asserts the expression side of the family.

## A typed constant of PChar type is a parse error (duplicate of the above)

*(was `bug-p-a-typed-constant-of-pchar-type-is-a-parse-error`, prio 55)*

# A typed constant of PChar type is a parse error

Found 2026-08-24 while writing the differential for
[[bug-p-a-string-literal-assigned-to-a-pchar-is-empty]] — the const row had to
be deleted from the test program before pxx would compile it at all.

```pascal
const KC: PChar = 'konst';
begin
  writeln(KC);
end.
```

```
Expected: begin, but got: konst (Kind: 3, Line: 1)
pascal26:1: error: unexpected token
```

FPC compiles it and prints `konst`.

A LOUD failure, not a silent one, which is why the prio is 35 rather than
alongside its parent. But `const S: PChar = '...'` is the ordinary way to name
a C string constant, so any real binding header hits it on the first line.

## Where to look

The typed-constant path in `compiler/pasparser_decl.inc` — `const NAME: T = value`.
It evidently accepts the ordinal and string type kinds and not a pointer one.
Check the whole shape family before fixing one arm:

- `const P: PChar = 'text'` (this ticket)
- `const P: Pointer = nil`
- `const A: array[0..1] of PChar = ('a', 'b')`
- `const R: TRec = (f: 'x')` where the field is a PChar

and note that whatever accepts the initialiser must apply the same `+8`
character-data skip the ASSIGNMENT path just gained, or this will parse and
then be empty — the identical defect one construct over.
`devdocs/dev/normalise-dont-special-case.md`: fixing one arm of a double case
without grepping for the sibling is how the second one stays broken.

## Gate

Track P's, plus the program above matching fpc 3.2.2 on x86-64 and one cross
target, plus whichever siblings the shape family turns up.

## A typed string constant cannot be assigned

*(was `bug-p-a-typed-string-constant-cannot-be-assigned`, prio 55)*

# A typed string constant cannot be assigned

Found 2026-08-22 by an FPC differential sweep over less-trodden language
features (`fpc -Mobjfpc -O1` 3.2.2 vs pxx `015bbbaf2`).

## The measurement

`{$WRITEABLECONST ON}` in every row (it is FPC's default outside `{$MODE
DELPHI}`, and pxx ignores the directive entirely — see below).

| declaration + assignment | fpc | pxx |
| --- | --- | --- |
| `const N: Integer = 0;` then `N := 1` | ok | ok |
| `const C: Char = 'x';` then `C := 'y'` | ok | ok |
| `const A: array[0..2] of Integer = (1,2,3);` then `A[1] := 9` | ok | ok |
| `const S: string = 'a';` then **read** `S` | ok | ok |
| `const S: string = 'a';` then `S := 'b'` | ok | **`undefined variable (S)`** |

So one type out of four, and the failure is a name-resolution error rather than
a "cannot assign to a constant" diagnostic — which is the tell that the constant
has no storage at all rather than a read-only one.

## Root cause

`ParseConstSection` (`compiler/pasparser_decl.inc`) registers a typed string
constant in the **StrConst** table, not as a variable, and its own comment says
why:

> Treated as a read-only string-literal alias — registered in the StrConst table
> exactly like the untyped `const Name = 'literal'` path, with NO storage var (a
> phantom var would shadow a same-named variable and ParseInitVal has no string
> case).

Both reasons are real. A use of the name expands to an `AN_STR_LIT` over the
source span, which coerces to a managed string wherever one is wanted — that is
why READING works and only the store fails.

## What a fix has to deal with

Allocating a real global for a typed string const means:

1. **Initialisation.** `ParseInitVal` has no string case; the literal has to
   become a managed-string assignment run before the main body, alongside the
   existing `LocalInitCount` typed-const initialiser mechanism for
   routine-locals.
2. **Shadowing.** The comment's hazard is
   `bug-set-of-char-const-corrupts-char-codegen`'s shape: a phantom var matching
   case-insensitively against a same-named variable. Registering the storage
   under a mangled key and resolving the NAME through the const table (as class
   consts already do via `ClassConstMangle`) sidesteps it.
3. **The untyped form must not move.** `const Name = 'literal'` (no type) is a
   literal alias in FPC too and must stay one — only the TYPED form gets
   storage. That distinction is already visible at the declaration site.

## A related, separate question for Track U

**`{$WRITEABLECONST}` is not implemented at all** — grepping the compiler finds
no reference. So typed consts are unconditionally writable here for the types
that have storage, and unconditionally unwritable for strings; the directive
that is supposed to decide it does nothing either way. Whether pxx should honour
`{$WRITEABLECONST OFF}` (and refuse the store with a proper diagnostic) or
document typed consts as always writable is a dialect call, not a bug fix —
file `decide-writeable-const-directive` if the taker wants it settled first.
Fixing the string case is worth doing regardless, since it only removes an
inconsistency between types.

## Gate

The five rows above matching `fpc -O1`, a read of the const still producing the
literal (no regression in the many places `const S: string = ...` is read), and
self-host byte-identical.

## A record-typed FIELD in a typed record constant

*(was `feature-p-nested-record-field-in-a-typed-record-constant`, prio 48)*

# A record-typed FIELD in a typed record constant

Found 2026-08-20 by an FPC differential probe over records. FPC accepts, pxx
rejects:

```pascal
type TPt   = record x, y: Integer; end;
     TNest = record p: TPt; tag: string; n: array[0..2] of Integer; end;
const CN: TNest = (p: (x: 1; y: 2); tag: 'k'; n: (7, 8, 9));
```

`pascal26: error: not a constant` — ConstEval reaches the inner `(x: 1; y: 2)`
and sees the identifier `x`.

It is exactly one shape. These all already work:

| shape | pxx |
| --- | --- |
| `const C: TPt = (x: 3; y: 4)` | works |
| `const C: TArrF = (tag: 'k'; n: (7,8,9))` (array field) | works |
| `const C: TA = ((x:1;y:2),(x:3;y:4))` (array OF record) | works |
| `const C: TNest = (p: (x:1; y:2); ...)` (record field) | **rejected** |
| `const C: TIn = (a: 1; inner: (q: 9))` (inline anon record) | **rejected** |

The parser says so itself, at the head of the record-typed-const branch in
`parser.inc`: *"Nested record/array fields are not handled yet."* The array half
of that sentence was implemented afterwards (the TGuid `D4` path, PendingInit
Kind 7); the record half was not.

## Why it is not a one-liner

A pending init records its target as **one** field-name span (`PendingInitFOff`
/ `FLen`), and the emitter builds a target chain

```
IDENT  ->  [INDEX elem]  ->  [FIELD span]  ->  [INDEX ValAux]
```

from it. A nested record needs a *path* of spans (`C.p.x`), and there is
nowhere to put the second one. Bolting on an `F2Off`/`F2Len` pair would make
one-level nesting work in about ten lines — and would be precisely the second
path that `devdocs/dev/normalise-dont-special-case.md` says stays broken, since
`a.b.c.d` would still be rejected and the next person would add `F3`.

The shape that generalises: give the pending init a **field path** rather than
a field, i.e. a small side table of spans plus a start/count pair in the
parallel arrays, and have the emitter loop the FIELD nodes instead of building
one. The parser side is then genuinely recursive — the record-const branch
calls itself for a record-typed field, pushing a span per level — and the same
loop covers `array of record` elements with nested records for free.

## Priority

Prio 40, not higher, because it fails **loudly**: the program does not compile,
so nothing silently computes a wrong answer. Workaround is a `var` plus an
assignment in the initialisation section.

## A record constant with an array-of-RECORD field does not parse

*(was `feature-p-record-const-with-an-array-of-record-field`, prio 45)*

# A record constant with an array-of-RECORD field does not parse

- **Track P** (Pascal frontend: `ParseConstSection`'s record-constant arm).
- Found 2026-08-20 by an FPC differential probe (the probe that found
  [[bug-p-record-field-array-with-a-non-zero-low-bound-writes-out-of-bounds]]).
  Loud, not silent — it is a compile error, which is why this is a feature
  ticket and not a bug.

## Repro

```pascal
type
  TSub = record x, y: Integer; end;
  TR = record g0: Integer; a: array[1..3] of TSub; g1: Integer; end;
const
  CR: TR = (g0: 7; a: ((x:1;y:2),(x:3;y:4),(x:5;y:6)); g1: 8);
```

```
pascal26:22: error: not a constant
  near:   a    >>> x
```

FPC 3.2.2 compiles and runs it.

## Where it stops

The record-constant arm already has an **array-valued field** path — it emits
one `sym.field[k] := v` init per element (PendingInitKind 7) — and it reads each
element through `ParseInitValTk(fTk)`, i.e. a SCALAR. A `(x:1;y:2)` element is a
record constant, so the scalar reader meets `x` and reports "not a constant".

Note the neighbouring case that DOES work: a top-level `const t: array[1..N] of
TRec = ((name:'AND'; c:1), ...)` — the array-of-record-with-named-fields form
Pascal Script's keyword table needs. So the two halves of the same concept are
split across two arms, and only the nested one is missing.

## Sketch

The kind-7 emitter builds `sym.field[k]`, and the record-element path builds
`sym[k].field`; what this needs is `sym.field[k].subfield`, i.e. one more
component in the same target chain. `PendingInitFOff` already carries one field
span and `PendingInitValAux` the element index, so the shape is there — it needs
a second field span (or a small target-path encoding) rather than a new
mechanism.

## Gate

The repro compiles and its values match FPC; a test under `test/` pins the
nested form alongside the two that already work.
