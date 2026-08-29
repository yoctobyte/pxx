---
prio: 55
track: A
---
# `AllocArray` leaves `RecName` stale on a recycled symbol slot

**Retitled and moved to Track A on 2026-08-29**, after measuring it. It was
filed as a Track R oddity ("a fn with a slice param and >= 2 params erases
`main`'s record-array element type"); the mechanism is one line in
`compiler/symtab.inc` and every frontend that allocates a fixed array is
exposed to it, so the Rust spelling below is a symptom, not the subject. Prio
raised from 30 to 55 for the same reason: the ROOT is shared machinery and one
of its two symptoms is silent.

Found on 2026-08-29 while probing the `[Name { .. }; N]` rung (rung 16 of the
Track R ladder). **Pre-existing** — it has nothing to do with that rung: the
narrowest repro declares its array with no initializer at all, a path that rung
did not touch.

## Repro

```rust
struct Move { from: i64, to: i64 }
fn t(b: &[i64], i: i64) { }              // never called; the BODY is irrelevant
fn main() {
    let mut a: [Move; 4];
    a[0].to = 7;                          // Rust: unexpected token  near: a >>> to
    println!("{}", a[0].to);
}
```

Delete `fn t`, or drop it to a single parameter, and it compiles and prints 7.

## What is actually broken

The parse error comes from `RParsePrimary`'s `arr[i].field` arm, whose guard is
`Syms[symIdx].ElemType = tyRecord` (`compiler/rparser.inc`, the "plain
fixed-array indexing" block). So `a` was allocated as an array whose ELEMENT
TYPE is not a record — `RTypeKindFromName('Move')` did not answer `tyRecord` at
`AllocArray` time in `main`, even though `FindUClass('Move')` plainly still
works right next to it.

Note the failure MODE changes with the element type, and the second one is the
dangerous half:

| element type of the array in `main` | symptom |
| --- | --- |
| a struct (`[Move; 4]`) | parse error on `.field` — loud, harmless |
| the same struct when the slice param is `&[Move]` | **compiles, then segfaults** |

## The probe matrix (all measured, not reasoned)

Program shape is fixed: `struct Move`, the listed declaration, then
`fn main() { let mut a: [Move; 4]; a[0].to = 7; println!("{}", a[0].to); }`.

| declaration inserted before `main` | result |
| --- | --- |
| *nothing* | 7 |
| `struct Other { x: i64 }` | 7 |
| `fn t(x: i64) -> i64 { x }` | 7 |
| `fn t(b: &i64) -> i64 { 1 }` | 7 |
| `fn t(b: &[i64]) { }` | 7 |
| `fn t(b: &[i64]) -> i64 { b[0] }` | 7 |
| `fn t(b: &[i64], i: i64) { }` | **broken** |
| `fn t(i: i64, b: &[i64]) { }` | **broken** |
| `fn t(b: &[i64], c: &[i64]) { }` | **broken** |
| `fn t(b: &[i64], i: i64, j: i64) { }` | **broken** |
| `fn t(i: i64, j: i64) { }` | 7 |
| `fn t(b: &[Move], i: i64) { }` | **segfault** (compiles clean) |

So the trigger is exactly: **a fn whose parameter list contains at least one
`&[T]` slice AND has arity >= 2.** One slice alone is fine; two scalars are
fine; the body is irrelevant (an empty body triggers it).

Two further facts that a root-cause has to explain, and both cut against the
obvious "the slice UClass shifts an index" story:

- **It is specific to `main`.** The identical array in an ordinary fn is fine:
  `fn u() -> i64 { let mut a: [Move; 4]; a[0].to = 7; a[0].to }` compiles and
  answers 7 with `fn t(b: &[i64], i: i64) { }` present.
- **The slice fn must precede `main` in TOKEN order.** Move `fn t` below `main`
  and it compiles. That is surprising, because `RRegisterFnSignatures` prescans
  every top-level fn — and therefore calls `RSliceClassForRec` — before any body
  is parsed, so the slice UClass exists in both orderings.

`Move` itself is undamaged: `let m: Move = Move { from: 1, to: 2 };` still works
in the same `main` that cannot type `a[0].to`.

## Knock-on

`let m: Move = a[2];` under the same conditions fails with
`Rust: struct assignment from a non-literal expression is not supported by the
skeleton yet` — that is this bug, not a missing feature: without the slice fn,
the same line compiles. Do not file it separately.

## Why the corpus engine does not hit it

`test/test_rust_chess_engine.rs` has three slice-param fns with arity >= 2
(`is_attacked`, `king_sq`, `gen_moves`) declared before `main`, and it is green
— because `main`'s only arrays are `[i64; 64]` boards. Scalar element types are
unaffected. The engine's move list is a `MoveList` STRUCT local, not a record
array in `main`. The bug is one `let mut a: [Move; 4];` in `main` away at all
times.

## ROOT CAUSE (measured 2026-08-29, probes in the compiler, not reasoning)

`AllocArray` (`compiler/symtab.inc:4411`) writes `Name`, `TypeKind`, `ConstVal`,
`IsArray`, `ArrLen`, `SymDynDepth`, `ElemRecName` and the rest of the element
shape into `Syms[SymCount]` — and **never touches `RecName`**. The symbol table
recycles slots, so the new array symbol inherits whatever record id the previous
occupant of that slot left behind.

Probed at the `a[` dispatch in `RParsePrimary`, same program, one parameter
added to an unrelated fn:

```
one param:  PROBE brk sym=5 name=a tk=5 rec=0  isarr=1 isslice=0 base=16
two params: PROBE brk sym=5 name=a tk=5 rec=19 isarr=1 isslice=1 base=16
```

`rec=19` is `REC_UCLASS_BASE + 3` — the auto-registered `&[i64]` slice class,
left in that slot by the slice PARAMETER of the fn declared above. `RIsSliceSym`
tests exactly `TypeKind = tyRecord` and `RSliceCi[RecName - REC_UCLASS_BASE]`,
and an array-of-record symbol has `TypeKind = tyRecord` (the ELEMENT kind), so
the stale `RecName` alone flips the answer. `a[0]` is then routed to the
slice-index arm — `AN_DEREF(__ptr + i*stride)` over an array that has no header
— instead of the plain fixed-array arm, and `.field` never gets a chance to
parse.

That is why every strange fact in the matrix above is a fact about **slot
arithmetic**, not about classes: the fn must precede `main` (so its params are
allocated first), it needs arity >= 2 (so a param lands on the slot `main`'s
array will reuse), and it is specific to `main` (a fn parsed earlier reuses
different slots). None of the "the slice UClass shifts an index" stories were
close.

Confirmed by fixing it: resetting the field immediately after the `AllocArray`
call makes the repro print 7 instead of failing to parse. That one-line probe
was applied in `rparser.inc`, verified, and **reverted** — the fix does not
belong there.

## Fix (Track A, one line, NOT applied)

```pascal
  Syms[SymCount].RecName := REC_NONE;     { in AllocArray, beside ElemRecName }
```

An array symbol's record identity lives in `ElemRecName` by design —
`ResolveNodeRec` says so in its own comment ("Array symbols store their ELEMENT
record in ElemRecName, not RecName ... a recurring landmine throughout this
codebase") — so `RecName` on an array symbol is meaningless and must be cleared,
not merely ignored. `AllocVar` sets it; `AllocArray` is the odd one out.

Left for Track A deliberately: `symtab.inc` is shared core, Track R does not
edit it, and the blast radius is every frontend that allocates a fixed array
(C, NilPy, Pascal and Zig all call `AllocArray`). Whoever takes it should check
whether the other frontends have latent instances rather than only re-running the
Rust repro — a stale `RecName` is readable by anything that asks a record
question about an array symbol, and it fails silently wherever the answer is not
a parse decision.

---

## CROSS-FRONTEND AUDIT 2026-08-29 (claude-N) — read-only

Answering the handoff's ask: *"whoever takes it should look for latent instances
in the other frontends rather than only re-running the Rust repro."* No compiler
source touched — `symtab.inc`, `ir.inc` and `pyparser.inc` were held by other
agents throughout. Everything below is measured black-box, against gcc and FPC.

### First: the allocator has a sibling, and the ticket names only one

| allocator | writes `RecName`? |
| --- | --- |
| `AllocVar` (`symtab.inc:4046`) | yes |
| `AllocParam` (`:4218`) | yes |
| **`AllocArray` (`:4411`)** | **no** — writes `ElemRecName` only |
| **`AllocDynArray` (`:4556`)** | **no** — writes `ElemRecName` only, same hole |
| `AllocTemp` (`:4683`) | delegates to `AllocVar`, so yes |

**`AllocDynArray` has the identical defect and the fix must land on both.**
Fixing only `AllocArray` would leave `array of TRec` exposed — the exact
"grep for the sibling before closing the ticket" case in
`normalise-dont-special-case.md`.

The discipline was already known at these sites: every allocator carries
comments like *"slot recycling — every Alloc\* must reset EVERY parallel array"*.
`RecName` is a field of the record rather than a parallel array, which is
plausibly how it slipped past a rule written about parallel arrays.

(`AllocTemp` sets `RecName` from the global `LastTypeRecId`, which is its own
staleness with its own recorded bug at `ir.inc:12292` — *"arm's hidden temp got
no RecName -> wrong RecSize -> garbage copy"*. Different mechanism, not this
ticket.)

### The reader census

126 reads of `Syms[..].RecName` across the frontends and shared code. 86 have no
`IsArray` or `ElemRecName` anywhere within ±12 lines. **20 are guarded by
`TypeKind = tyRecord` and nothing else** — and that is the trap, because an
array-of-record symbol *has* `TypeKind = tyRecord`: it holds the ELEMENT kind.
A guard that looks like a type check is not one.

### Per frontend

| frontend | `AllocArray`/`AllocDynArray` calls | verdict |
| --- | --- | --- |
| **Rust** | 6 | **LIVE** — `RIsSliceSym`, this ticket's repro; confirmed still red at HEAD |
| **C** | 6 | **LIVE — new repro below**, and it is the silent kind |
| **Zig** | 2 | **latent** — two exact structural twins, not reachable today |
| **Pascal** | 3 + 3 | mainline guarded; exposed readers are exotic |
| **NilPy** | **0** | **not exposed** — `pyparser.inc` calls neither allocator |

### C — a live, silent instance

```c
#include <stdio.h>
struct A { long x; };
struct B { long y; long z; };
void t(struct B b, long i) { (void)b; (void)i; }   /* by VALUE; a pointer param does not trigger */
int main(void) {
    struct A a[4];
    printf("%s\n", _Generic(a, struct A: "A", struct B: "B", default: "other"));
    return 0;
}
```

**gcc says `other`** (the array lvalue-converts to `struct A *`, matching no
association). **pxx says `B`.** Delete `t`, or change its parameter to
`struct B *`, and pxx says `other` again.

The chain: `CExprCG`'s `AN_IDENT` arm types the symbol as `cgStruct` with
`CGRecA[Result] := Syms[sym].RecName` (`cparser.inc:1110`), and `CGMatch`
selects an association by `CGRecA[a] = CGRecA[c]` (`:1208`). The stale id is
`struct B`'s, left in the recycled slot by `t`'s **by-value** struct parameter —
a `struct B *` parameter has `TypeKind = tyPointer`, so its `RecName` is not the
struct id, which is why the pointer variant is clean. That asymmetry is the
mechanism confirming itself.

No error, no warning, wrong branch. This is exactly the failure mode the handoff
predicted: *"a parse-decision reader fails loudly and every other kind fails
silently."* Rust's instance is a parse error you cannot miss; C's picks the wrong
`_Generic` arm and compiles.

**The one-line fix makes C *more* correct here, not merely different.** With
`RecName := REC_NONE`, the array symbol's `cgStruct` matches neither
association, so every variant answers `other` — agreeing with gcc in all five
probe shapes. Note that today's no-`t` case answers `other` **by accident**: the
recycled slot simply happened to hold no record id.

### Zig — two structural twins, unreachable today

```pascal
function ZIsSliceSym(symIdx: Integer): Boolean;      { zparser.inc:307 }
begin
  Result := (Syms[symIdx].TypeKind = tyRecord) and
            (Syms[symIdx].RecName >= REC_UCLASS_BASE) and
            ZSliceCi[Syms[symIdx].RecName - REC_UCLASS_BASE];
end;
```

That is `RIsSliceSym` character for character, and `ZIsOptSym`
(`zparser.inc:272`) is a third copy of the same three lines over `ZOptCi`. Both
would misfire identically.

They cannot fire **today**, and the reason is worth recording because it is
temporary: the Zig skeleton refuses `var a: [4]Move = undefined` with *"struct
type Move is only allowed for local variables in the skeleton"*, so no Zig
symbol can currently be both `IsArray` and `TypeKind = tyRecord`. **The day
Track Z accepts an array of struct, both predicates become live**, in a frontend
with no test that would notice. Measured, not assumed — the refusal above is the
compiler's own message.

### Pascal — mainline guarded, exposure is exotic

Ten shapes probed against FPC (fixed and dynamic array of record; field write,
whole-element copy, `SizeOf(a)`, `SizeOf(a[0])`, `Length`), each with and
without a preceding by-value record parameter at arities 2 and 3, and with a
`var` parameter and a global. **All twelve outputs identical to FPC.** Pascal's
mainline array path goes through `ResolveNodeRec`, which reads `ElemRecName` by
design and says so in its own comment.

The unguarded Pascal readers are real but hard to reach: `pasparser_stmt.inc:494`
and `:549` put `Syms[varIdx].RecName` on an `AN_DEREF` node for a `for..in` over
a generator yielding records — a stale value there gives `ResolveNodeRec` the
wrong size and produces a **garbage copy**, silent, but it needs an
array-typed loop variable. `:6799`/`:6810` sit behind `DelphiMode and
SymProcSig[idx] >= 0`. Not reproduced; not cleared either.

### Recommendation

1. Apply the one-line fix to **both** `AllocArray` and `AllocDynArray`.
2. Pin it with **two** tests, because the two failure modes are different
   evidence: the Rust parse error (loud) and the C `_Generic` selection
   (silent, and diffable against gcc). A C test also covers the arm no current
   test touches.
3. When Track Z gains arrays of structs, `ZIsSliceSym`/`ZIsOptSym` need the
   Rust repro transliterated — worth a line in the Zig ladder now, while the
   connection is visible.

### The shape

Three frontends grew their own `Is<X>Sym` predicate over one shared symbol
field, each with the same latent flaw, and the flaw is only reachable where that
frontend's *other* features happen to line up. One concept, several
implementations, and a fix on one arm is no evidence about the others — the same
thing the `builtinheap` twin census found one level down, in
[[audit-a-builtinheap-invariants-x86-64-inlines-past]].
