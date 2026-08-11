---
track: A
prio: 50
type: bug
blocked-by: []
status: done
owner: claude-A
---

# A typed const array of `string[N]` is never initialised — silently

- **Type:** bug (silent wrong value) — **Track A**
- **Found:** 2026-08-10 by an FPC differential over the recursion / sorting /
  const-table surface. A lookup table of short strings is an everyday
  construct (month names, enum labels, keyword tables).
- **Pre-existing:** identical on `pinned`.

```pascal
const Names: array[0..2] of string[8] = ('aa','bb','cc');
begin WriteLn('[', Names[0], ']'); end.
```

FPC prints `[aa]`. pxx prints eight NUL bytes and trailing garbage — **no
diagnostic**.

## Boundary (measured, `fpc -O1` as oracle)

| element type | pxx |
| --- | --- |
| `Integer` | correct |
| `Char` | correct |
| `string` (AnsiString) | **correct** |
| `string[8]` | **garbage** |
| a named alias `TS8 = string[8]` | **garbage** |
| `ShortString` | **garbage** |

So it is exactly the FROZEN string forms, and the managed `string` sibling
beside them works — the usual two-spellings split.

The equivalent VAR array is fine: `var a: array[0..2] of string[8]` then
`a[0] := 'aa'` reads back `aa`. So the storage and the ordinary assignment path
are healthy; only the const INITIALISATION is wrong.

## Measurements to start from (mechanism NOT yet established — do not assume)

- `SizeOf` agrees between the const and the var array (24 for
  `array[0..2] of string[8]`), so the two symbols are laid out the same and the
  difference is in the initialisation, not the allocation.
- `Length(Names[0])` on the const answers a value that looks like an ADDRESS
  (e.g. 4243361), while `Length(a[0])` on the uninitialised var answers 0.
  Something pointer-shaped is reaching the slot.
- The parser DOES have a frozen-string arm for array-const elements: the element
  loop tests `cElemTk in [tyString, tyAnsiString, tyFixedString, tyShortString]`
  and records a `Kind=1` (string-literal span) init. The `Kind=1` emitter
  (`parser.inc`, the `PendingInitFOff[i] = -3 or PendingInitKind[i] = 1` arm)
  builds an `AN_STR_LIT` tagged **`Ord(tyString)`**.
- The nearby comment on the array-const path still says *"Ordinal/Char/Int64
  element types; string/float/record initializers remain a follow-up"*, which
  predates the `Kind=1` arm — so the parse side was extended and the comment
  (and possibly the emit side) was not.

**I did not confirm which of those is the fault**, and a plausible-sounding
story here would be worth nothing — see `devdocs/dev/debugging-playbook.md`.
Dump the emitted init with `PXXDBG=a.ast:main` / `a.ir:main` and compare against
the working `a[0] := 'aa'` lowering before concluding anything.

## Note for whoever takes it

Nothing in `lib/`, `compiler/`, `examples/` or `test/` currently uses this
construct (checked), so there is no in-repo code depending on today's behaviour
— a diagnostic is a safe intermediate step if the real fix is large. **Silent
garbage is the one outcome that must not survive**, since the array-of-record
sibling right beside it already refuses what it cannot do
(`array-of-record constant with string fields must be global`).

## Gate

The six element types above matching FPC, plus a named-alias element and an
N-D const array of `string[N]`; `test/test_const_array_of_string.pas` still
green; self-host byte-identical.

## Log
- 2026-08-11 — resolved, commit 6900505aa.
