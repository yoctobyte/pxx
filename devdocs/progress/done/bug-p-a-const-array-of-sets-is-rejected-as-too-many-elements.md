---
slug: bug-p-a-const-array-of-sets-is-rejected-as-too-many-elements
track: P
prio: 55
type: bug
status: done
owner: frank-rust
blocked-by: []
summary: "`const tbl: array[0..2] of TSetOfByte = ([], [0..255], [$41..$5A]);` is rejected as `too many array constant elements`. A SET element is not consumed by the array-constant element loop, so cElem desyncs from the token stream and counts the SAME `[` once per declared slot before erroring -- the reported position is the FIRST element, which makes it read like a size error rather than a parse one. A scalar set const and an array of ordinals each work; only the combination fails. This is fcl-xml's `names.inc` (namingBitmap, 13 sets of Byte) and so the next wall on rung 3 of [[feature-pascal-corpus-oop]], immediately after the interface-property one."
---

# A `const` array whose ELEMENTS are sets is rejected

## Repro

```pascal
program s1;
type TSetOfByte = set of Byte;
const
  tbl: array[0..2] of TSetOfByte = ([], [0..255], [$41..$5A]);
begin
  if 65 in tbl[2] then WriteLn('yes') else WriteLn('no');
end.
```

```
pascal26:4: error: too many array constant elements
  near: 2 ] of TSetOfByte = ( >>> [ ] ,
```

Binary `93e89c5795c1` (self-host fixedpoint at HEAD `0f0fd6642`).

Both halves work alone, which is what makes this the combination and not either
piece: `const one: TSetOfByte = [$41..$5A];` compiles and `65 in one` is TRUE,
and `const t: array[0..2] of Integer = (1,2,3);` compiles and indexes.

## Mechanism (diagnosed, not guessed)

`pasparser_decl.inc:2340`, the array-constant element loop. Its arms are
`(` / `)` / `,` / a named-field record element / everything-else, and
everything-else calls `ParseInitVal`, which does not consume a `[`. So the loop
spins on the same token, `Inc(cElem)` each pass, and trips
`cElem >= cFlatLen` at `pasparser_decl.inc:2368` after exactly `cFlatLen`
passes -- with `TokPos` still on the FIRST element, which is why the reported
position looks like a length complaint about a correct length.

**This is the third instance of one shape.** The same desync is documented in
that arm's own comment for a multi-character string literal
(`bug-const-array-of-ansistring-literal-too-many-elements`) and for a PChar
element -- both fixed by giving the element its own arm that consumes its
tokens. A set element is the third, and "two is a smell, three is a design
flaw": the real question is why the fallback arm may fail to consume and still
count, rather than which literal shapes get an arm. A loop that counted only
when `TokPos` advanced would have turned all three into a clear diagnostic.

## The part that is NOT just a parser arm

`BakeSetConst` (`pasparser_decl.inc:1932`) already parses a set literal and
bakes it into the data segment, and the scalar path at 2517-2529 registers the
result as a named `SetConst`. What does not exist is a way to put those baked
32-byte blobs into an ARRAY's static storage: `PendingInit` records ordinal and
string-literal elements, not blobs. So the fix is a parser arm **plus** an
element-init kind that carries a baked-set offset, and that second half is the
real work. Estimate before starting -- do not assume the arm is the job.

## Why it matters

fcl-xml's `xmlutils.pp` includes `names.inc`, which is
`namingBitmap: array[0..$0C] of TSetOfByte` -- 13 set constants, the W3C XML
naming-character tables. Every fcl-xml unit reaches it, so rung 3 of
[[feature-pascal-corpus-oop]] stops here, one wall past
[[bug-p-a-property-in-an-interface-declaration-is-rejected]]. Outside the corpus
this is ordinary FPC-parity Pascal: a table of character classes as sets is a
common lexer idiom.

## Gate

`make compiler/pascal26` + the repro above printing `yes`, plus
`./compiler/pascal26 <fcl-xml>/xmlutils.pp` getting past `names.inc`. FPC
(`-Mdelphi`) is the oracle for the repro's output.

---

## FIXED — and it was smaller than this ticket sized it

**The sizing above was wrong and the correction is the useful part.** I wrote
"an array's static store has no element-init kind that carries a baked blob, so
that second half is the real work". The first thing I then did was MEASURE it
rather than believe it:

```pascal
var a: array[0..2] of TSetOfByte;
begin a[0] := []; a[1] := [0..255]; a[2] := ns_A; ...
```

compiles and gives the right answers today. `arr[i] := <set>` was already a
working assignment, so nothing below the parser was missing — the pending-init
flush builds an ordinary `arr[ei] := <value>` AST, and a set value node
(`AN_SET_CONST_REF`) is one it can carry like any other. The estimate came from
reading the init-kind table and seeing no set in it; the answer came from
running four lines. **Reading the mechanism told me what was absent; running it
told me what was needed, and those were different.**

### The change

- **One arm** in the array-constant element loop (`pasparser_decl.inc`), before
  the fallback: element type `tySet` and the token is `[` or a named set
  constant → `BakeSetConst` (which already folds `A + B` / `A - [x]` into a
  32-byte mask in `Data[]`) and record the offset.
- **Init kind 9** in both emitters — `pasparser_prog.inc` for a global const and
  `pasparser_proc.inc` for a routine-local one — rebuilding `AN_SET_CONST_REF`
  from that offset. Same encoding on both sides, deliberately: kind 2 already
  carries a comment saying the two emitters must not drift, and this is the
  second kind that would have.
- `TryBakeConstArrayIntoData` sees a kind it does not know and falls back to
  runtime stores. That is its documented fail-closed behaviour and it is correct
  here, so it needed no change.

### Measured

Binary `390a091ff683`, self-host fixedpoint at HEAD.

The repro prints `yes` / `1`, matching FPC `-Mdelphi` exactly. New test
`test/test_const_array_of_sets.pas` (wired into `test-core`) covers the empty
set — the shape that spun first — plus a full set, a range and a named constant,
in a global const array AND a routine-local one, the latter because it goes
through the LocalInit emitter where a second encoding would drift.

**The oracle claim is split, on purpose.** With the `ext` rows deleted, FPC
compiles the test and prints the `tbl`/`loc` rows identically — that is
FPC-parity, verified by diff. FPC **rejects** both `ext` forms, a named set
constant as an element and a set expression as an element, as *"Illegal
expression"*. We accept them, which is not a defect (CLAUDE.md's compat
ceiling), and they are kept in the test because they reach `BakeSetConst`
through `FindSetConst` and through its `+`/`-` folding, which no literal row
exercises. Their expected values come from the set algebra, not from FPC, and
the test says so.

### The corpus wall is cleared, and the next two are named

`fcl-xml`'s `xmlutils.pp` now gets past `names.inc`. The next errors in the same
unit are `undefined variable (PWideChar)` at line 285 and `undefined variable
(AllocMem)` at line 478 — a missing type and an RTL gap, different lanes, and
not filed here. See [[feature-pascal-corpus-oop]].

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
