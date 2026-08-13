---
track: N
prio: 40
type: bug
blocked-by: []
summary: "Four small refusals found by the 2026-08-13 CPython sweep: `issubclass(A, B)`, `d.update(k=v)` (the keyword form), `key=str.lower` (an unbound method as a callable value), and Unicode special-casing in upper()/lower() ('ß'.upper() is 'ß', CPython 'SS'). Each is a parse error or a wrong string, none is a silent wrong VALUE"
---

# Small builtin-surface gaps from the 2026-08-13 sweep

- **Type:** bug (refusals / one wrong string) — **Track N**
- **Found:** 2026-08-13, sweeping the str / dict / sequence / class surface
  against CPython. The rest of those four files matched CPython exactly; these
  are what did not.

| shape | pxx | CPython |
| --- | --- | --- |
| `issubclass(Derived, Base)` | `error: unexpected token` | `True` |
| `d.update(z=6)` (keyword form) | `error: unexpected token` | updates |
| `sorted(xs, key=str.lower)` (an UNBOUND method as a value) | `error: unexpected token` | sorts |
| `"ß".upper()` | `ß` | `SS` |
| `"İ".lower()` | `İ` | `i̇` |

The first three are diagnostics at compile time, which is the honest failure
mode; the case-mapping rows are a wrong VALUE but only for non-ASCII letters
whose case change alters LENGTH (the ASCII and Latin-1 letters are correct).

## Notes for whoever takes it

- `issubclass` has a runtime twin already: `pyisinstance_v` walks the RTTI
  parent chain, and `issubclass` is the same walk from a class ref rather than
  an instance — the frontend intercept is what is missing.
- `d.update(**kw)` / `d.update(k=v)` is the dict twin of
  [[bug-nilpy-kwargs-and-star-unpack-at-a-construction-are-refused]]: a keyword
  argument reaching a pylib method.
- `str.lower` as a VALUE is the unbound-method form of
  [[bug-nilpy-map-over-a-bound-method-segfaults]] (which fixed the BOUND form,
  `obj.method`). A str method has no instance to bind, so it wants the same
  callable-value treatment a plain def gets.
- Case mapping: `pystr_upper`/`pystr_lower` map byte by byte, so a mapping that
  changes the code-point COUNT cannot be expressed. Worth doing only with the
  wider unicode question, not on its own.

## Gate

A `.npy` diffed against CPython covering each row, kept in one file so the four
are visible together.
