---
slug: bug-a-an-indirect-call-returning-a-dynamic-array-leaks-every-allocation-on-every-backend
track: A
prio: 55
type: bug
status: new
found: 2026-09-01
found-by: frankB
owner: ""
blocked-by: []
summary: "`fp := @MakeArr; a := fp(i)` with a procedural variable returning a dynamic array leaks EVERY allocation -- frees=0, live=1871 of 1871 -- on x86-64, i386, arm32, aarch64 and riscv32 alike. The same function called DIRECTLY is clean (live=2), so this is the ownership guard testing IR_CALL alone and missing IR_CALL_IND, the dynamic-array twin of the string bug fixed in 746cbb20f. Unlike that one it is broken on the DEFAULT backend too, because x86-64's dyn-array path was never migrated to a shared predicate the way its string path was. xtensa is exempt: it refuses the program outright ('only ordinal/float/pointer/string function results supported yet'), which is the correct behaviour. Measured with -dPXX_ALLOC_CENSUS."
---

# An indirect call returning a dynamic array leaks every allocation

Found while closing
[[refactor-a-the-owned-string-release-predicate-is-hand-copied-across-five-backends]]
by checking the sibling it named — the dynamic-array twin of the same guard —
rather than by taking the note's word for it being merely untidy.

## The measurement

`fp := @MakeArr; a := fp(i)` over 2000 iterations, `MakeArr` returning
`array of Integer`, built `-dPXX_ALLOC_CENSUS`:

| target | allocs | frees | live |
| --- | ---: | ---: | ---: |
| **x86-64** | 1871 | **0** | **1871** |
| i386 | 1871 | **0** | **1871** |
| arm32 | 1871 | **0** | **1871** |
| aarch64 | 1871 | **0** | **1871** |
| riscv32 | 1871 | **0** | **1871** |
| xtensa | — | — | refuses to compile, correctly |

**The same function called DIRECTLY is clean**, which is the whole diagnosis:

```
a := MakeArr(i)    ->  allocs=1871 frees=1869 live=2     (x86-64)
a := fp(i)         ->  allocs=1871 frees=0    live=1871  (x86-64)
```

Nothing is ever released. The program's output is correct throughout.

## Why this is worse than the string twin that was just fixed

That one (`746cbb20f`) spared x86-64, because x86-64's *string* path asks the
shared `IRNodeOwnsManagedStr`. **This one does not spare x86-64**, so it is
broken on the default target for ordinary code — any procedural variable or
callback returning a dynamic array.

## Where it lives

Six cross backends spell the guard identically and narrowly:

```
if not ((IRKind[IRB[node]] = IR_CALL) and (IRA[IRB[node]] >= 0)) then
    ... PXXDynArrayIncRef
```

`ir_codegen386.inc`, `ir_codegen_aarch64.inc`, `ir_codegen_arm32.inc`,
`ir_codegen_riscv32.inc`, `ir_codegen_xtensa.inc` (keyed on `IRB[node]`) and
`ir_codegen_wasm32.inc` (keyed on `valNode`). `IR_CALL` alone — missing
`IR_CALL_IND` and `IR_VIRTUAL_CALL`.

**x86-64 is NOT one of these** and still leaks, so it reaches the retain by a
different route. `ir_codegen.inc` contains no `PXXDynArrayIncRef` call at all.
**Find x86-64's path first** — it is the one that decides whether this is one
fix or two, and assuming it is the same shape as the cross backends is the
mistake to avoid.

## What the fix probably wants

The string side ended with one predicate asking four arms. The three CALL arms
(`IR_CALL` with `IRA >= 0`, `IR_VIRTUAL_CALL`, `IR_CALL_IND`) are **type-
agnostic** — only `IRNodeOwnsManagedStr`'s BINOP arm is string-specific. So the
natural shape is to factor those three out as a `IRNodeOwnsFreshCallResult`
and have both the string predicate and the dyn-array guards ask it, rather than
a second four-arm copy under a different name. **Do not simply call
`IRNodeOwnsManagedStr` from the dyn-array sites**: it would return the right
answer today and the name would be a lie, which is how the next reader gets
misled.

## Next probes, unrun

- A **virtual** method returning a dynamic array (`IR_VIRTUAL_CALL`), same shape.
- The other managed kinds — interfaces, and `array of AnsiString` — reached
  through an indirect call.

## Guarding it

`test/test_managed_str_ownership_leaks.pas` already does exactly this comparison
for strings (census output vs the x86-64 build of the same source, wired into
all five per-arch targets). The dyn-array case needs the same file to grow a
block, **but note it cannot use the x86-64 build as its oracle here** — x86-64
leaks too, so the comparison would pass on two equally wrong numbers. This one
needs an absolute assertion (`frees` within N of `allocs`) until x86-64 is fixed.
That asymmetry is the reason this ticket exists separately from the test.
