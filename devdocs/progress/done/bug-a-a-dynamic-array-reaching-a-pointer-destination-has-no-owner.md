---
type: bug
track: A
prio: 6
summary: a dynamic array reaching a Pointer cast, parameter or assignment leaked every array — frees=0, 9976 live in one program
owner: frankB
---

## What

The same three seams as the string family, one managed kind over. All read
`frees=0` — every array leaked:

| spelling | before | after |
| --- | --- | --- |
| `Pointer(MkArr(i))` — the cast | 921 | 2 |
| `TakeQ(MkArr(i))` with `TakeQ(p: Pointer)` — **implicit** | 921 | 2 |
| `q := Pointer(MkArr(i))` — the assignment | 921 | 2 |
| `TakeQ(Pointer(a))`, `a` a named local — **control** | 921/919 | 921/919 |

After the fix all four read `921/919 live=2`: the three leaking spellings land
exactly ON the control, not near it.

## Why the string park could not see it

**A dyn-array-typed node already reads `tyPointer`.** Every predicate in the
string family asks the node's type tag, so no spelling of the string park would
ever have fired here. The test has to be the node's dyn DEPTH
(`NodeDynDepth`), which is why this is a second helper rather than a widened
condition.

The temp is also a different object: a dyn-array local carries an element type
and a nesting depth, and its scope-exit release is `PXXDynArrayRelease` reading
that SYMBOL's layout descriptor. A string temp has neither, so sharing one
allocator would mean threading an element shape through every string call site
that has none. `IRParkManagedDyn` returns its input unchanged for anything that
is not a dyn array, so a call site can ask unconditionally.

## Measured

`test/test_dynarray_to_pointer_seam_leaks.pas`: **9976 → 14** against a bound of
50, on `39e033c85335` vs the fixed binary, `allocs` 10975 either way — same
traffic, so the delta is ownership. Rejected by the pre-fix binary (rc=1).
Identical on x86-64/aarch64/arm32/riscv32.

The `array of AnsiString`, `array of array of Integer` and `array of TRec` arms
make the layout descriptor do real work; a wrong element type there is a double
free rather than a leak, so they are also run under `-dPXX_HEAP_DEBUG`, clean.

**No i386 row**, and that is a limit of the target: i386 refuses the program with
*"target i386: arrays not yet supported"* — `Length(a)` alone is enough. A cross
row there would compare against a file that was never built.

FPC rejects the implicit `TakeQ(MkArr(i))` (*"Incompatible type for arg no. 1:
Got TIntArr, expected Pointer"*), as it rejects the string family's implicit arm.
With that one call spelled `TakeQ(Pointer(MkArr(i)))` the whole program compiles
under FPC and prints exactly what pxx prints for both spellings, so the OUTPUT
has an oracle and the COUNT does not.

## Log

- 2026-09-01 — found by sweeping the string family's seams for other managed
  kinds, fixed and closed in the same session, commit PENDING-COMMIT.
