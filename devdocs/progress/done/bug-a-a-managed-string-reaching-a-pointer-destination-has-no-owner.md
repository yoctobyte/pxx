---
type: bug
track: A
prio: 6
summary: three more seams where a managed string became a raw pointer with no owner — implicit PChar param, PChar assignment, Pointer() cast — all frees=0
owner: frankB
---

## What

Three spellings, each leaking every string, `frees=0`:

| spelling | before | after |
| --- | --- | --- |
| `Cish('lit' + c)` with `Cish(s: PChar); cdecl` — **implicit**, no cast in source | 921 | 3 |
| `p := 'lit' + c` with `p: PChar` | 921 | 3 |
| `Pointer('lit' + c + 'x')` | 921 | 4 |

A pointer destination retains nothing — a PChar/Pointer parameter keeps an
address, a pointer variable stores a bare handle, a pointer cast is a tag
change. The +1 belonged to nobody and was never a symbol, so no scope-exit scan
could find it.

## Why this is one bug and not three

Sixth, seventh and eighth instance of **one shape**: a lowering hands a fresh
managed string to a consumer that keeps a RAW POINTER. The five before were
`88e1ab536` (Variant→AnsiString, twice), `f42665459` (`array of const`
element) and `7cd695c7d` (the explicit `PChar()` cast).

The common cause is that **ownership is decided by asking the argument's AST
SHAPE** at seven call-argument sites (`ParamWantsManagedStrTemp` plus an
`AN_IDENT`/`AN_FIELD`/`AN_INDEX`/`AN_DEREF` exclusion). That is sound reasoning
about SOURCE and wrong about a LOWERING, and for a POINTER parameter it is worse
than wrong: `ParamWantsManagedStrTemp` is False by construction, so none of the
seven ever fire.

So this commit does the structural half as well: one named helper,
`IRParkManagedStr`, and all eight sites call it. The implicit-parameter arm goes
at **`IRLowerCallArg`'s single tail** — the funnel every call argument passes,
where the width conversion already lives — rather than at the seven sites.

## No oracle row for two of the three

FPC **rejects** the implicit spellings: `Cish('lit' + c)` is *"Incompatible type
for arg no. 1: Got AnsiString, expected PChar"* and `p := 'lit' + c` is
*"Incompatible types: got AnsiString expected PChar"*. Only the `Pointer(...)`
cast compiles there. pxx accepts all three deliberately — it is what lets a C
binding take a Pascal string without `PChar()` boilerplate — and accepting what
FPC rejects is not a defect. It does mean the ownership rule for those spellings
is ours to define, and dropping the +1 was still wrong.

## Measured

`test/test_string_to_pointer_seam_leaks.pas`: **3138 → 6** against a bound of
50, on `fa002ef63d15` vs the fixed binary. Rejected by the pre-fix binary
(rc=1). Identical on x86-64/i386/aarch64/arm32/riscv32. Clean under
`-dPXX_HEAP_DEBUG`.

`allocs` rises 4274 → 4809 rather than staying put, and that is the one number
that is not "same traffic": the unowned value used to let a concat be dropped.
4809 matches what the named-intermediate spelling (`t := 'lit' + c + 'x';
q := Pointer(t)`) reads on its own, so 4809 is the honest count and 4274 was a
second symptom.

## Log

- 2026-09-01 — found by sweeping sibling seams rather than by a report; fixed,
  refactored the eight sites onto one helper, and closed in the same session,
  commit b788c5865.
