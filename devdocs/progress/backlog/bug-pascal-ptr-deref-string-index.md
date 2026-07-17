---
prio: 45
track: P
---

# SILENT: char-indexing through a pointer-to-string deref (`p^[k]`) reads garbage

- **Type:** bug — **SILENT** wrong value. Track P (string indexing IR lowering).
- **Found:** 2026-07-17 building `parallel for` ansistring capture (which lowers a
  captured string to `^AnsiString` + `s^[k]` and hit this).

## Symptom / minimal repro

```pascal
procedure R;
var s: AnsiString; p: ^AnsiString;
begin
  s := 'ABCDE';
  p := @s;
  writeln(Ord(s[1]));      { 65 — correct }
  writeln(Ord(p^[1]));     { 24 — WRONG (expect 65) }
  writeln(Ord(p^[2]));     { 0  — WRONG (expect 66) }
end;
```

`s[k]` (direct) is correct; `p^[k]` (same string through a pointer deref) reads
garbage — it reads bytes at the string's HANDLE SLOT, not the char data.

Note the OTHER string ops through the deref DO work: `Length(p^)`, `p^ = 'x'`
(compare), `p^ := 'y'` (assign) are all correct. Only CHAR INDEXING is broken.

## Root cause (localized)

`ir.inc` AN_INDEX, the `tk = tyAnsiString` branch (~line 1164): it sets
`lo:=1; elemSize:=1; tk:=tyChar` and emits `IR_INDEX(baseAddr, index, 1, 1)` =
`baseAddr + (index-1)`. For that to hit char data, `baseAddr` must be the string's
DATA POINTER (handle).

- For an **AN_IDENT** string base, `IRLowerAddress` yields the loaded handle
  (data ptr) → correct.
- For an **AN_DEREF** base (`p^`), `IRLowerAddress` yields the pointed-at ADDRESS
  (the frame slot `@s`), NOT the loaded handle → `IR_INDEX(@s, k)` reads the
  handle's own bytes as chars → garbage.

## Direction

In the `tyAnsiString` (and likely the managed-string-via-field/deref) index path,
ensure `baseAddr` is the char-data HANDLE: when the base is not an AN_IDENT whose
address already resolves to the handle (AN_DEREF, and check AN_FIELD /
AN_INDEX-of-string cases), insert an `IR_LOAD_MEM` to load the handle from the
slot before the `IR_INDEX`. Compare against the frozen-string (`tyString`) path,
which may already handle this. Gate = `make test` + self-host byte-identical +
string-heavy corpora (the whole-string ops must stay correct — only indexing
changes). Add the `p^[k]` repro as a regression.

## Unblocks

`feature-parallel-processing` ansistring capture: the parallel-for worker lowers a
captured string to `^AnsiString` + `s^[k]`; once `p^[k]` indexes correctly, the
existing capture mechanism (Length/compare/assign already verified) covers strings
with no further work. Currently ansistring capture is a clean compile error.
