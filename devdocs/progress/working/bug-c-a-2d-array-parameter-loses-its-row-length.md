---
track: C
prio: 65
type: bug
blocked-by: []
summary: "`int f(int a[][4])` lost the 4: the parameter declarator's brackets were consumed by a blind balanced skip, so `a[1][2]` flattened to 1+2 and read a[0][3]. The equivalent `int (*a)[4]` spelling was right, so the two spellings of one C type disagreed — silently, on the ordinary way a 2-D array is passed."
---

# A 2-D array parameter loses its row length

- **Type:** bug (silent wrong value) — **Track C** (`compiler/cparser.inc`).
- **Found:** 2026-08-16, by a gcc-differential sweep over C dark corners (the
  same sweep as
  [[bug-c-a-string-literal-row-of-a-2d-char-array-stores-its-address]]).

## Measured (before)

```c
int m[3][4];                       /* filled with i*4+j */
int g(int a[][4]) { return a[1][2]; }
```

`gcc: 6`, `pxx: 3` — that is `m[0][3]`, i.e. the index flattened as `1 + 2`
instead of `1*4 + 2`. `int g(int (*a)[4])` answered 6, and the two declarators
name the same parameter type in C.

## Root cause

A parameter's trailing brackets were consumed by a balanced-bracket skip whose
only job was to reach the end of the declarator, and the parameter was then
retyped as a bare pointer-to-element. `SymPtrElemArrLen` / `SymPtrElemNDims` —
the channel `int (*a)[4]` already fills, and which `a[i][j]` reads to compute
the stride — were left at 0. So the pointee was `int`, not `int[4]`.

## Fix

Record each bracket's bound while skipping it (a plain integer bound only; a
VLA or macro bound stays unknown exactly as before), drop the first dimension —
which is the one C decays away — and apply the rest through the same
`pptrarrlen` / `pptrndims` / `pptrdims` channel the `(*a)[N]` form uses. One
mechanism, reached by both spellings.

## Result

`test/carr2d_param_row_length.c` — `[][4]`, `(*)[4]`, `[3][4]`, `[][3][4]`, a
loop summing through the parameter, and the 1-D and `char *[]` forms that must
stay untouched — returns 42 under both gcc and pxx.

## Gate

`make compiler/pascal26` + the test + `tools/gate.sh quick` — GREEN.
