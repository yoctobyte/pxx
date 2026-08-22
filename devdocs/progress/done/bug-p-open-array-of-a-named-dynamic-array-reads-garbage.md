---
track: P
prio: 60
type: bug
blocked-by: []
status: done
owner: claude-A
commit: 2432769d0
summary: "`procedure P(const m: array of TRow)` with `TRow = array of Integer` typed the parameter's element as TRow's BASE type, so the callee indexed dyn-array handles with a 4-byte Integer stride: `Length(m[0])` printed 124906597515344 where fpc printed 3, and a slightly larger shape segfaulted. Three arms — the parameter's element type, the `[a, b]` constructor temp, and the parser-side dyn-depth of `m[i][j]`."
---

# An open array of a named dynamic array reads garbage

Found 2026-08-22 by an FPC differential sweep over language shapes
(`fpc -Mobjfpc -O1` 3.2.2 vs pxx `f73eca492`). It is a **silent wrong value**
that escalates to a segfault, not a diagnostic.

## The measurement

```pascal
type TRow = array of Integer;  TMat = array of TRow;
```

| how the matrix is reached | fpc | pxx before |
| --- | --- | --- |
| `m[0]` in the main body | `3 11` | `3 11` |
| `const m: TMat` (the NAMED type) | `3 11` | `3 11` |
| `const m: array of TRow` | `3 11` | **`124906597515344 29082`** |
| `var m: array of TRow` | `3 11` | **`124906597515344 29082`** |
| `const a: array of Integer` | `2 8` | `2 8` |
| `const m: array of string` / `of TRec` / `of TFix` / `of Pointer` | ok | ok |

Only the *open-array* form is wrong, and only when the element is a **named
dynamic** array. The original 15-shape sweep program produced 128 MB of output
and `rc=-11` from this one row.

## Root cause — one concept lost on three paths

The element of an open array is a pointer-sized **dyn-array handle**. Three
independent places decided otherwise:

**1. The parameter's element type** (`pasparser_proc.inc`). The `array of
<named type>` branch had an arm for a named FIXED element and nothing else:

```pascal
if (paramAi >= 0) and (not ArrTypeIsDyn[paramAi]) then ...row shape...
else tk := ParseTypeKind;
```

A named *dynamic* element fell to `ParseTypeKind`, which resolves `TRow`
through `FindArrayType(lo) >= 0 -> Result := tyInteger`. So the parameter became
`array of Integer`: 4-byte stride over 8-byte handles, and `Length(m[0])` read
the header of whatever those four bytes pointed at.

**2. The `[a, b]` constructor temp** (`ir.inc`, `AN_ARRAY_CTOR`). The temp was
built as `array of <base type>` and each element stored a handle into a 4-byte
Integer slot — a segfault the moment the callee dereferenced it.

**3. The parser-side dyn depth** (`symtab.inc`, `DynArrayNodeDepth`). IR's
`NodeDynDepth` already knew that indexing an array whose element is a dyn handle
yields another array; its parser-side twin did not. Harmless for an Integer base
(the fallback happened to answer `tyInteger` anyway) but not for a managed one:
`m[0][1]` on `array of TStrs` was TYPED as a CHAR index into an AnsiString, so
it emitted a 1-byte load off an 8-byte stride and printed one garbage character.
That is the double-case rule in `normalise-dont-special-case.md` — the second
path is the one that stays broken.

## The fix

- `pElemDynDepth` / `ProcParamElemDynDepth` carry the element's dyn depth from
  the parameter list to `SymElemDynDepth[param]`, which the existing
  "fixed array whose element is a dynamic array" machinery in `ir.inc` and
  `ast_arena.inc` already keys on — no new codegen, the open-array param simply
  joins the case that was already handled for `array[0..3] of TRow`.
- `OpenArrayCtorRowLen` encodes both element shapes in the one integer
  `ParseArrayCtorAST` already took: `> 0` a fixed row of that length, `0` a
  scalar, `< 0` a dyn element of that depth. The lowering then allocates the
  temp one level deeper and assigns handles, not base values.
- `DynArrayNodeDepth` gains the `SymElemDynDepth` arm its IR twin has.

## Verified against fpc

`const` / `var` / value parameter modes; `Length`, `High` and iteration over the
parameter; writing through a `var` parameter, including `SetLength` on a row and
the caller seeing both; the `[a, b]` constructor in the same position; and the
element base types that already worked (string, record, fixed array, Pointer)
kept as control rows. Output byte-identical to `fpc -Mobjfpc -O1`.

## Known sibling, filed separately

A var of a NAMED `array[0..1] of TRow` type loses the same element-dyn-depth
(the array-type table has no `ArrTypeElemDynDepth`), so `SetLength(f[0], 1)` is
refused with `SetLength expects an array variable in IR codegen` — while the
identical INLINE declaration compiles. Pre-existing, reproduced on `pinned`:
`bug-p-a-named-fixed-array-of-a-dynamic-array-type-loses-its-element-depth`.

## Gate

`make compiler/pascal26` (self-host fixedpoint) + `tools/gate.sh quick` GREEN.
Test `test/test_open_array_of_a_named_dynamic_array.pas`, 27 assertions, wired
into `test-core`.
