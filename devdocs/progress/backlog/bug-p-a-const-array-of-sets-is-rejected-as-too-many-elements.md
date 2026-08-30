---
slug: bug-p-a-const-array-of-sets-is-rejected-as-too-many-elements
track: P
prio: 55
type: bug
status: backlog
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
