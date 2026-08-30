---
slug: bug-a-indexing-through-a-pointer-to-an-array-is-wrong-for-several-element-kinds
track: A
prio: 60
type: bug
status: done
owner: frank-rust
blocked-by: []
summary: "FIXED. `p^[i]` where p points at a named FIXED array was wrong for several element kinds, with FOUR different faces: a pointer/PChar/AnsiString element SEGFAULTED, a `string[7]`/`string[31]`/ShortString element printed EMPTY and exited 0, writing to one was refused as \"cannot assign ShortString to Char\", and `WriteLn(p^[1])` on an `array of PChar` printed the pointer as a number. ROOT CAUSE, one sentence: the `[` arm chains in BOTH the parser and IRLowerAddress dispatch on the node tk, and on a pointer-to-array deref tk is the ARRAY ELEMENT kind -- so whichever arm that element kind collides with claims the node, and the symptom is a property of the ARM, not of the type. Fixed by asking what the base IS before what its elements are: IsNodeArray and NodePtrElem learn the shape, the parser`s DerefPtrArrayInfo arm moves to the head of its chain, the IR array tail takes element kind/rec/capacity from the POINTER SYMBOL, and a new SymPtrElemStrCap carries the frozen-string element capacity (the stride was LOCAL_STR_CAP+8 = 264 bytes for a 15-byte slot). Test `test/test_pointer_to_array_indexing.pas`, 19 rows, every one FPC-verified and every one comparing the pointer spelling against the direct `a[i]` -- because four of the broken rows exited 0."
---

# `p^[i]` over a pointer to a fixed array is wrong for several element kinds

> The title and slug said **segfaults** and **of-pointers** until frankB renamed
> the file (`c1f1231ad`): both were 100% accurate about the rows they described
> and wrong about the axis and the worst symptom. The silent `string[7]` row is
> the one that mattered and neither name could hold it. Sections below predate
> the rename and still use the old framing — they are history, not instructions.

## Measured

Binary `992065f21f33` (the pin). Plain default build, no define, no flag.
Same program, only the element type varying:

```pascal
type TA = array[0..3] of <ET>; PA = ^TA;
var a: TA; p: PA;
begin
  p := @a;
  p^[1] := Default(<ET>);      { WRITE -- read fails identically }
  WriteLn('ok');
end.
```

| element type | result |
| --- | --- |
| `Integer` | **works** |
| `Int64` | **works** |
| `Pointer` | **SEGFAULT** (rc=139) |
| `PChar` | **SEGFAULT** |
| `PInteger` | **SEGFAULT** |

So it is **pointer-KIND elements**, not `Pointer` the type name.

## Oracle

FPC gets the whole thing right. On the read side, four rows, FPC vs pxx:

```
                     FPC     pxx
1 direct   s[0]      100     100
2 (pl^)[0]           100     <segfault>
3 pl^[1]             101     -
4 pl^[2] := 999 ;    999     -
  then s[2]
```

pxx prints row 1 and dies on row 2. `fpc -Mobjfpc` on the identical source
prints all four.

## Not a pointer-to-array problem in general

Worth stating, because that is the obvious first guess and it is wrong:
`pointer-to-record` deref (`pr^.x`) is **correct**, and `pointer-to-array-of-Integer`
indexing (`pia^[1]`) is **correct**, in the same program that then dies on
`pointer-to-array-of-Pointer`. The dereference machinery works; something on the
pointer-element path does not.

## Why it matters more than it looks

`p^[i]` over an array of pointers is an ordinary Pascal idiom, not a corner:
it is how FPC's own `TList.List` is consumed, and fcl-xml writes
`TObject(FBindings.List^[I]).Free` at `xmlutils.pp:760`.

**It compiles clean and dies at run time**, so any check that builds without
running reports success. Found only because the program was run.

## Consequence for [[bug-b-tlist-has-no-list-property]]

That ticket asks for `property List: PPointerList read FList` on `TList`, and the
storage supports it — measured: `Pointer(a) = @a[0]` for a dynamic array and the
stride is 8, so the layout is exactly what `PPointerList` expects.

**Adding the property anyway would be wrong today.** It would compile, and then
segfault at the one idiom it exists to enable. That converts an honest
`"List": no such member` into a crash at a call site, which is strictly worse:
the current error names the problem at compile time. The property should land
**with or after** this fix, and that ticket is now `blocked-by` this one.

## Gate

`make compiler/pascal26` + the element-type table above, **run, not just built** —
every row compiles.

---

## Diagnosis at the IR, and it is TWO defects (frank-rust, 2026-08-30)

Reproduced independently, binary `2df3a1efab85`, self-host fixedpoint at HEAD.
The `Integer` and `Pointer` rows in one program, dumped with
`PXXDBG=a.ir:<proc>`, and the divergence is one node:

```
  array of Int64 (WORKS)                array of Pointer (SEGFAULT)
  2: load_sym  pia                      3: load_sym  ppa
                                        4: load_mem  a=3          <-- EXTRA DEREF
  4: index a=2 b=3 [lo=0 size=8]        5: index a=4 b=2 [lo=0 size=1]   <-- size 1
  5: load_mem                           6: load_mem
```

So `ppa^[1]` computes `[[ppa]] + 1*1` — it takes **element 0's contents as the
base address** and then steps ONE byte. That is why putting a valid address into
`pa_[1]` does not survive either: the extra load reads `pa_[0]`, not `pa_[1]`.
The crash is not a bad index, it is a bad base.

The ASTs are structurally identical; only the tags differ (`AN_DEREF` tk 13 vs
17, and the `AN_INDEX` comes out **tk 0, tyUnknown**, which is where `size=1`
comes from).

### Defect 1 — `tk = tyPointer` on a deref means two different things

`pasparser_lval.inc`, the `p^[i]` arm (`(tk = tyPointer) and (ASTKind[node] =
AN_DEREF)`) resolves the element from the pointer DEPTH parked on the deref
node: *"one level left means the element IS the base type, two or more means the
element is still a pointer."*

That is correct for `^PChar`. It is wrong for `^TPtrArr`, because there `tk` is
not the pointee's kind — it is the pointee ARRAY's ELEMENT kind, and it happens
to be `tyPointer`. The arm cannot tell the two apart, so a pointer to an array
of pointers is processed as a pointer to a pointer. **`array of Integer` escapes
only because `tyInteger` cannot collide with the test at all** — which is
exactly why the bug looks element-type-specific and is not: the discriminator is
an ambiguous tag, not the element type.

The information to disambiguate is already on the symbol and is correct:

```
PXXDBG a.symptr ppa   kind=17 depth=1 ptrElemTk=17 ptrElemArrLen=4
PXXDBG a.symptr pia   kind=17 depth=1 ptrElemTk=13 ptrElemArrLen=4
```

`ptrElemArrLen=4` on both — the pointee IS known to be a 4-element array in both
cases. Nothing needs to be computed; the arm needs to ask.

### Defect 2 — the ALIAS loses the pointee's base kind, the inline type does not

Same program, same pointee, two spellings:

```
var ppa: PPtrArr;    (PPtrArr = ^TPtrArr)   ->  baseTk=0
var ppa: ^TPtrArr;                          ->  baseTk=17
```

`AliasPtrBaseTk` is not carried for a pointer alias whose pointee is a named
fixed array. That is separable and it is a **Track P** file
(`pasparser_decl.inc` / the alias registration in `symtab.inc`), not Track A.

**Fixing defect 2 alone does NOT fix the crash** — measured, not assumed: with
the inline spelling `baseTk` is right, the index element resolves to `tyPointer`
correctly, and it still segfaults, because defect 1's extra `load_mem` is
independent of it.

### A hypothesis this ruled OUT, recorded so nobody re-runs it

`ParseTypeKind`'s `tkCaret` arm reads `childDepth := LastTypePointerDepth`
*after* an if/else whose array branch never calls `ParseTypeKind` — so it reads a
STALE depth, and `(elemTk = tyPointer) and (childDepth > 0)` looked like it would
register the alias as a pointer-to-pointer. It is a real smell and it is **not
this bug**: setting `childDepth := 0` there produced **byte-identical IR** and
the identical segfault. The symbol already had `depth=1`. Do not spend the
build on it again.

### What a fix has to do

Make the `p^[i]` arm (and whatever in `IRLowerAddress` decides to materialise
the deref) recognise that the pointee is an ARRAY, so `p^` yields the array's
ADDRESS rather than a loaded pointer, and the index takes the array's element
stride. The `array of Int64` path already does exactly this — it simply gets
there by never entering the pointer arm. The two paths should reach it for the
same stated reason, not by one of them missing a test.

**Not started.** I have no measurement of which of the two sites is the right
one to change, and guessing between them is how a plausible-looking fix that
moves the crash somewhere else gets written.


---

## 2026-08-30 (frank-rust, extended by frankB) — diagnosed, and my table was misleading

**The crash is a bad BASE, not a bad index.** frank-rust dumped both rows:

```
array of Int64 (works)        array of Pointer (segfault)
2: load_sym  pia              3: load_sym  ppa
                              4: load_mem  a=3          <-- extra deref
4: index [lo=0 size=8]        5: index [lo=0 size=1]    <-- and size 1
5: load_mem                   6: load_mem
```

`ppa^[1]` computes `[[ppa]] + 1*1` — element 0's *contents* used as the base
address. Root cause: `tk = tyPointer` on a deref node means **two** things
("the pointee is a pointer" / "the pointee is an array whose elements are
pointers") and the `p^[i]` arm reads it as the first, resolving the element from
pointer **depth**. `PXXDBG=a.symptr` shows `ptrElemArrLen=4` on both symbols, so
the information to disambiguate exists and is correct — the arm does not ask.

### My element-type table was the wrong frame, and two more rows prove it

I reported this as "pointer-KIND elements break". **That reading is wrong**, and
the two element types neither of us had tried are the ones that break it:

| element type | result | |
| --- | --- | --- |
| `Integer` `Int64` `Double` `Boolean` | **work** | tag cannot collide |
| `TObject` | **works** | and it *is* a pointer at runtime |
| `AnsiString` | **SEGFAULT** | and it is not what anyone calls pointer-kind |
| `Pointer` `PChar` `PInteger` | **SEGFAULT** | |

`AnsiString` breaking while `TObject` works kills "pointer-kind" as the
predicate in both directions at once. What survives is frank-rust's model: it is
about **pointer depth as the tag reports it**, not about the element being a
pointer in any representational sense. The working rows are not "the working
element types" — they escape only because their tag cannot collide with the test.

**The general form is this ticket's real content:** an enumeration of symptoms
looked like a cause. A type list is a plausible-looking classification, and it
had 5 of 5 rows right while being the wrong axis entirely — which is exactly the
80%-accurate-name failure, since the part I sampled confirmed it.

### Two defects, and the second does NOT cause this

frank-rust measured a **separable Track P** defect — a pointer alias whose
pointee is a named fixed array loses `AliasPtrBaseTk` (`var ppa: PPtrArr` gives
`baseTk=0`; `var ppa: ^TPtrArr` gives `baseTk=17` for the same pointee) — and
confirmed **fixing it alone does not fix the crash**: with the inline spelling
the element resolves correctly and it still segfaults, because the extra
`load_mem` is independent.

### A hypothesis already RULED OUT — do not spend a build on it

`ParseTypeKind`'s `tkCaret` arm reads a stale `childDepth` after a branch that
never calls `ParseTypeKind`. Real smell, plausible story: setting it to 0 produced
**byte-identical IR and the identical segfault**.

### No fix started, deliberately

There is no measurement saying whether the parser arm or `IRLowerAddress` is the
right site, and guessing between two plausible sites is how a fix moves a crash
instead of removing it.

---

## Two more rows, and one of them is worse than a crash (frank-rust)

Binary `18ceb4588586`, self-host fixedpoint at HEAD. Testing the corrected model
— *"the working rows escape only because their tag cannot collide"* — predicts
which untried element types break, so here are four that had not been tried:

| element | result | why |
| --- | --- | --- |
| `Char`, `Boolean` | correct | no arm matches the tag |
| a record type | correct | the record arm wants a record BASE, not a record element |
| **`string[7]` (frozen)** | **`short ` — SILENTLY WRONG, no crash** | the frozen-string arm matches |

FPC prints `short hi`; we print an empty string. The same array indexed WITHOUT
the pointer prints `hi`, so it is the `p^[i]` path and not the declaration.

**That row matters more than the crashes.** A frozen string is neither
pointer-kind nor a managed handle, so it is a third independent arm — and it
fails by producing a plausible wrong VALUE rather than a signal. Everything
found so far was a segfault, which is the cheap case; this is the expensive one
and it was sitting in the same defect the whole time.

The predicate is therefore not about pointers at all: **the `[` arm chain
dispatches on `tk`, and for a pointer-to-array `tk` holds the ARRAY'S ELEMENT
kind while every arm reads it as the type of the thing being indexed.** Any
element kind that collides with an arm above the array fall-through breaks —
`tyPointer` (three pointer arms), `tyAnsiString` and frozen strings (two string
arms) — and any kind that collides with nothing is fine.

## The parser is NOT the crash site — measured, so the two candidates are now one

Earlier I said I would not start a fix because there were two plausible sites and
no measurement to choose between them. There is one now.

I taught `IsNodeArray` (`symtab.inc`) that an `AN_DEREF` over a pointer with
`SymPtrElemArrLen > 0` is an array, which routes `p^[i]` down the ARRAY arm of
the index chain and past all five broken element-kind arms. Instrumented at
every `AllocNode(AN_INDEX)` site to confirm it actually fires:

```
PXXDBG p.idxarm site=pasparser_lval.inc:1406
PXXDBG p.idxarm chain=A basekind=36 tk=17 isarr=TRUE      <- AN_DEREF, now an array
```

**Result: the index's element tag is fixed (`AN_INDEX` goes from `tk=0` to
`tk=17`) and the program still segfaults, byte-identically.** The IR keeps both
of its real defects:

```
4: load_mem a=3                          <- still takes element 0's CONTENTS as the base
5: index a=4 b=2 [lo=0 size=1] tk=17     <- still strides ONE byte
```

So: the parser arm chain is a genuine second bug (it is what makes `string[7]`
silently wrong, and `tk=0` is its fingerprint), but **it is not what crashes.**
The crash lives entirely in `IRLowerAddress`'s `AN_INDEX` arm — the `baseAddr`
choice and the `elemSize` computation for an `AN_DEREF` base. `TypeSize(tyPointer)`
is 8 and the emitted stride is 1, so that arm is not reaching its own
`else elemSize := TypeSize(tk)` tail; something above it is claiming the node
first. That is where to look, and it is ~40 lines.

**I reverted the `IsNodeArray` change rather than landing it.** On its own it
fixes no observable row — every row behaves identically before and after, only
an IR tag moves — and it changes a predicate shared across the compiler. Landing
a shared-predicate change that fixes nothing, next to a still-broken IR, would
read as a fix to the next person. It is recorded here instead, with the exact
edit, so whoever takes the IR half can re-apply it in one minute and get the
parser half for free.


## 2026-08-30, later (frank-rust; independently confirmed by frankB) — a SILENT arm, and the model finishes

**This row belongs at the top of the ticket.** Everything above is a segfault,
which is the cheap case — it has a location and it stops. This does not:

```pascal
type TSA = array[0..3] of string[7]; PSA = ^TSA;
a[1] := 'hi';  p := @a;
                          pxx            FPC
  direct   a[1]           [hi]           [hi]
  through  p^[1]          [ ]            [hi]        exit 0, no diagnostic
```

Confirmed in my own checkout against the FPC oracle, and it is not specific to a
width: `string[7]`, `string[31]` and `ShortString` all produce the empty string
through the pointer while `Char` is correct. **A frozen string is neither
pointer-kind nor a managed handle**, so this is a third independent arm — and it
had been sitting inside the same defect the whole time, invisible because every
probe either of us wrote asked "did it crash?".

### The model, finished — and it is not about pointers

frank-rust's statement, which supersedes every element-type reading including my
corrected one:

> **The `[` arm chain dispatches on `tk`, and for a pointer-to-array `tk` holds
> the ARRAY'S ELEMENT KIND while every arm reads it as the type of the thing
> being indexed.** Collide with an arm above the array fall-through and you
> break; collide with nothing and you are fine.

That is why the symptom set looks arbitrary: it is a list of which element kinds
happen to have an arm above the fall-through, and **the symptom differs by which
arm catches it** — a pointer arm gives a wrong base and a segfault, the frozen
string arm gives a wrong value and silence. `TObject`/`AnsiString` killed
"pointer-kind"; `string[7]` kills "representational" entirely.

### The crash site is the IR, not the parser — measured

frank-rust taught `IsNodeArray` that a deref of a pointer-to-fixed-array is an
array, routing `p^[i]` past all five broken element-kind arms, and instrumented
every `AllocNode(AN_INDEX)` site to confirm it **fired** rather than assuming
(`basekind=36 isarr=TRUE`; the index's element tag moved `tk=0` -> `tk=17`).
**The program segfaulted byte-identically.**

So: the crash lives entirely in `IRLowerAddress`'s `AN_INDEX` arm — the baseAddr
choice and elemSize, ~40 lines. `TypeSize(tyPointer)` is 8 and the emitted stride
is 1, so that arm never reaches its own `TypeSize` tail; something above claims
the node first. The parser defect is real, is what makes the `string[7]` row
silently wrong, and is **separable**.

### That parser change was deliberately NOT landed

It fixes no observable row — every row behaves identically, only an IR tag moves —
and it changes a predicate shared across the compiler. **A shared-predicate change
that fixes nothing, sitting next to a still-broken IR, reads as a fix to the next
person.** The exact edit is banked in the ticket so whoever takes the IR half gets
the parser half in a minute.

## 2026-08-30, frankA — three of the readers fixed; the frozen-string arm is not

Landed with a ten-row test against `fpc -Mobjfpc`. **Fixed:** a raw pointer
element, a record-pointer element (with a field behind the second caret), an
AnsiString element (read, write and `Length`), and a PChar element written
inline. **Still broken, and it is the silent one:** a FROZEN-string element.

### What the three fixes were

One ambiguous tag, three readers. The caret arm tags a deref node with the
ELEMENT's kind, so `tk = tyPointer` on `p^` means both "the pointee is a
pointer" and "the pointee is an ARRAY whose element is a pointer".

| reader | wrong answer | effect |
| --- | --- | --- |
| `IsNodeArray` | FALSE | the array path took the managed-STRING arm: `p^` loaded as a handle, indexed 1-based at stride 1 |
| `IRNodePointerBase` | TRUE | lowered as pointer arithmetic: extra `load_mem`, stride 1, element 0's contents as the base |
| `IsNodePChar` | FALSE | had `arr[i]` and `q^`/`q[i]`, not the two composed — silent wrong value |

`DerefPtrArrayInfo` already knew the real shape; two of the three now ask it.

### The two lowering fixes are disjoint — ablated, not argued

With only `IsNodeArray` fixed, a Pointer/PChar/PRec element still segfaults.
With only `IRNodePointerBase` fixed, an AnsiString element still segfaults.

### The ticket's suspected site measured as NO CHANGE

This ticket named the parser's `p^[i]` arm. I guarded it there first — it is the
obvious fix and it reads right. Ablated properly it moved **nothing**: every row
passes without it, *including* the two compile errors it was supposed to
explain. Those come from `IsNodeArray`, which the **parser** also calls. Dropped
rather than kept.

The first ablation was itself wrong and is worth recording: `(not False and X)`
parses as `(not False) and X` = `X`, which **inverts** a guard rather than
disabling it. The rows passed anyway, which is how it survived a look.

### What is left, and why my own table missed it

**I asserted exit code, not output.** `ShortString` scored as PASSING in my
element-type sweep on `rc=0` alone. Measured properly on the fixed binary:

```
string[7]     pxx [] [] len=0                 fpc [hi] [hi] len=2
string[31]    pxx [] [] len=0                 fpc [hi] [hi] len=2
ShortString   pxx [i <220 spaces>] [] len=7493989779944505344
```

A frozen-string element is a different arm from the three above —
`TypeIsFrozenString(tk) and not isArr` in `IRLowerAddress`, plus whatever gives
`Length` a garbage answer. `isArr` is now TRUE for this shape, so that arm is no
longer the one being taken and the remaining fault is downstream of it. Not
diagnosed further.

Test: `test/test_ptr_to_array_of_pointers_index.pas`, wired in `make test`.
Non-vacuous per row on `pinned` (139 / compile error / 139 / 139), measured
individually because the file stops at the first compile error.


---

## Resolved — frank-rust, 2026-08-30

Binary `3a53468cb267`+ (rebuilt per change; the final fixedpoint sha is on the
commit). Every row below is FPC-verified with `{$MODE OBJFPC}` on the oracle —
without it FPC's `Integer` is 16-bit and `SizeOf` diverges for a reason that has
nothing to do with this bug. That cost a confused minute; noting it so it costs
the next person none.

### The model, finished

frankB's and mine converged on this and it is the whole bug:

> The `[` arm chain dispatches on `tk`, and for a pointer-to-array `tk` holds
> the ARRAY's ELEMENT kind while every arm reads it as the type of the thing
> being indexed.

Two things the earlier diagnosis had wrong, both found by measuring:

1. **There are TWO such chains, not one.** `IRLowerAddress`'s was the crash
   site, and `ParseLValueAST`'s suffix loop has the identical disease — its
   `(tk = tyPointer) and (ASTKind[node] = AN_DEREF)` arm (written for `^PChar`,
   a genuinely different shape) fired for a pointer-ELEMENTED array and skipped
   the low-bound normalisation sitting in the arm below it. My earlier note
   "the crash site is NOT the parser" was true of the CRASH and false as a
   statement about the bug.
2. **The symptom is a property of the ARM, not of the element type.** That is
   why a symptom list could never produce the model: "crashes" and "prints
   empty" and "refuses to compile" looked like three bugs.

### What was actually wrong, and where

| # | site | wrong because |
| --- | --- | --- |
| 1 | `IsNodeArray` (`symtab.inc`) | answered FALSE for `p^` over a pointer-to-array — so the `and not isArr` guards the AnsiString and frozen-string arms ALREADY CARRY could not protect them. The guards were right; the predicate under them was blind. |
| 2 | the computed-pointer-value arm (`ir.inc`) | consults no `isArr` at all and runs FIRST. `IRNodePointerBase` asked `ASTTk`, a pointer ELEMENT answered "I am a pointer", and the arm took the pointee's first 8 bytes as the base and strode 1. |
| 3 | `ParseLValueAST`'s chain (`pasparser_lval.inc`) | the `DerefPtrArrayInfo` arm — which exists precisely for this shape and does the low-bound normalisation — sat BELOW three tk-dispatch arms. |
| 4 | the IR array tail (`ir.inc`) | for a non-AN_IDENT base it takes `tk` from `ASTTk[baseNode]`. On this deref that is `tyString`, the LEGACY frozen alias, so the stride came out `LOCAL_STR_CAP + 8` = **264 bytes for a 15-byte slot** — element 1 read from outside the array. |
| 5 | `SymPtrElemStrCap` | did not exist. `SymStrCap` is the capacity of the string a symbol IS and stays 0 on a pointer, so nothing carried `string[N]`'s N through a pointer-to-array. |
| 6 | `IsNodePChar` (`ir.inc`) | arm 6 answers `a[i]` over `array of PChar` and had no twin for `p^[i]`, so `WriteLn(a[1])` printed `hi` and `WriteLn(p^[1])` printed `4303888` — in the same program, off the same array. |
| 7 | `NodePtrElem` (`pasparser_lval.inc`) | same gap, other reader. |

Sites 1, 3, 6 and 7 are all one shape: **the metadata was recorded and the
reader was missing.** `IsNodePChar`'s own arms 6 and 7 say "reader half, again"
about themselves; this is the third and fourth time in that one function.

### The fix, and the one line to remember

**Ask what the base IS before you ask what its elements are.** Concretely: the
shape test (`DerefPtrArraySym`, split out of `DerefPtrArrayInfo` so indexing can
reach the symbol) goes at the HEAD of each chain, above every arm that
dispatches on `tk`.

Also extracted `SetPtrElemArrayInfo` — the pointee-shape block was written out
**four times verbatim** across AllocVar/AllocParam/AllocArray/AllocDynArray, and
adding a fifth field to four copies is how the copies drift. Adding it once is
why the capacity is now correct everywhere rather than in the one allocator I
happened to test.

### Rows, all matching FPC

`test/test_pointer_to_array_indexing.pas`, 19 lines, wired into `test-core`.
Read and write for Integer / PChar / `string[7]` / AnsiString / record /
`array[1..4]`; `Length`/`High`/`Low`/`SizeOf` over the same deref; a multi-dim
pointee (must NOT be low-bound-normalised twice — `BuildFlatNDIndex` already
did it); a dynamic pointee (a different slot, `SymPtrElemDynDepth`, unaffected);
and expression / assignment positions, not just `Write`.

**The gate compares VALUES, not exit codes** — frankB's point, and it is the
load-bearing property of this test. Four of the broken rows exited 0.

### Not fixed here, filed separately

C's `sizeof(*p)` on `int (*p)[4]` answers 4 where gcc says 16 — the same family
(an extent through a pointer-to-array), the C frontend's lane. Byte-identical
before and after this change, so it is pre-existing, not a regression:
`bug-c-sizeof-of-a-dereferenced-pointer-to-array-answers-the-element-size`.

### What I checked, precisely

C `test/test_zig_advanced.zig`, `test/test_rust_advanced.rs` and a C
pointer-to-array program: **byte-identical output against the pinned compiler**,
which is the claim that matters for a shared-`ir.inc` change — not "the gate was
green". A NilPy canary and `gate.sh quick` are green. Everything else is Track
T's sweep.

## Log
- 2026-08-30 — resolved, commit 47eaf847c.

---

## Follow-up — the fix got SMALLER, not bigger (frank-rust, 2026-08-30)

frankA made a design point after the first landing that retired part of my own
fix, and the ablation is the interesting half.

**His point:** the pointee's low-bound normalisation had no business living
inside an arm of `ParseLValueAST`'s chain at all. *Typing an element* and
*normalising a subscript* are different jobs, coupled only by chain POSITION —
and that coupling is exactly why the regression looked the way it did: the day
`IsNodeArray` learned this shape, an earlier arm began winning, the subtraction
silently stopped running, and precisely one row of one test moved (`array[0..3]`
has lo = 0, so only the `array[1..4]` row could see it).

Moving the arm to the head of the chain — what I landed — fixes today's winner
and leaves the same trap armed for whatever arm is added above it next. The
subtraction now runs **after the whole chain**, guarded by `DerefPtrArrayInfo`,
`not isND` and `not alreadyResolved`, and cares about no arm.

**Then the ablation, which is why the diff shrank.** With the subtraction out, is
the head position still worth anything? Forced the arm to `False`, rebuilt:
`test_pointer_to_array_indexing`, `test_ptr_to_array_of_pointers_index` and
`test_pointer_to_a_named_fixed_array` **all still pass** — `IsNodeArray` now
answers this shape and its `recName := ResolveNodeRec(node)` covers the
record-element case the arm was written for. So the head position buys nothing,
and it costs: at the head it SUPPRESSES that arm, and frankA reports that
suppressing it broke `qrec^[1]^.x` with *"dereferenced value is not a pointer"*
in his own attempt at the same reorder. **The arm went back where it was.**

Net: one fewer special case than the first landing, and the arm-ordering class
of regression cannot recur through that path — not because the ordering is now
right, but because nothing depends on it.

**Why my reorder did not break `qrec^[1]^.x` and his did**, since it looks like
luck and is: the arm's body sets no `tk` and no `recName`. It only did the
subtraction. So the `^` arm's resolution survived underneath it. Two reorders of
the same arm, one safe and one not, decided by a property neither of us was
reasoning about.

**The `not alreadyResolved` guard is mine and is deliberately conservative.**
The comma-sugar path `p^[i,j]` builds and types its own node chain; an
unconditional subtraction would apply to its last subscript alone. Neither of us
tested that shape, so it is excluded rather than guessed at — which preserves
exactly the reachability the arm had before it moved.

### One measurement note, because the instrument lied

A follow-up harness of mine reported `test_named_fixed_array_of_a_dynamic_array`
FAILING. There is no `.expected` file for that test; `diff` was exiting non-zero
because the file was **missing**, and the loop scored that as a test failure.
Output is byte-identical to the pinned binary. It did not error — it answered,
correctly, about something else. Third instance tonight across three agents.

### frankA's ShortString ablation, recorded because it is a positive control

Without the `SymPtrElemStrCap` column, `string[7]` and `string[31]` are empty and
**`ShortString` is GREEN — because its capacity IS the default.** A row that
passes for a reason unrelated to the fix, sitting in the same table as the rows
that prove it. Anyone re-testing this bug with a ShortString row alone will
conclude it is fixed when it is not.
