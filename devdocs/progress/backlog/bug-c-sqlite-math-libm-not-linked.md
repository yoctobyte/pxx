# C: sqlite math functions (`fabs`, …) get no libm DT_NEEDED

- **Type:** bug (C frontend / ELF linkage) — Track C (touches the math-extern
  list in `cparser.inc`; if the gap is in DT_NEEDED emission it spills to Track
  A / `elfwriter.inc`)
- **Status:** backlog
- **Owner:** unassigned
- **Found / Opened:** 2026-06-27, M5 sqlite bring-up
  ([[feature-c-desktop-lua-sqlite-path]]), right after the preprocessor-arithmetic
  fix ([[bug-c-sqlite-undefined-symbol-memsetdefault]]) let
  `sqlite3_open(":memory:")` run.

## Symptom

```text
symbol lookup error: ...: undefined symbol: fabs
```

`readelf -d` on the sqlite executable lists only `NEEDED libc.so.6`. `fabs` is a
**weak** symbol exported by `libm.so.6`, not by `libc.so.6`'s dynamic table, so
with no `DT_NEEDED libm.so.6` it cannot be resolved at startup.

## Notes

`cparser.inc` ParseCSubroutine already maps a known set of math names
(`pow sqrt fmod floor ceil fabs sin cos tan asin acos atan atan2 exp log frexp
ldexp sinh cosh tanh`) to `extLib := 'libm.so.6'` (→ `ProcLibrary`), and
`elfwriter.inc` emits one `DT_NEEDED` per distinct library. So the plumbing
exists — yet libm is absent from the final binary. Likely causes to check:

- sqlite reaches `fabs` through a path that does **not** run the math-name
  classifier (an implicit declaration, a prototype consumed elsewhere, or a call
  with no local prototype so the extern is synthesised with the libc default),
  leaving `ProcLibrary[fabs]` = `libc.so.6`.
- or the math extern is registered but never emits its `DT_NEEDED` because the
  proc is pulled as a pure call target without going through the prototype path.

Confirm which math names sqlite actually needs (likely `fabs`, `sqrt`, `pow`,
`log`, …) and ensure each is classified to libm and contributes a `DT_NEEDED`.

## Acceptance

- A C program that calls `fabs`/`sqrt`/etc. (no explicit `external` clause)
  links with `DT_NEEDED libm.so.6` and resolves the symbols at run time.
- `sqlite3_open(":memory:")` advances past the math-symbol wall.
