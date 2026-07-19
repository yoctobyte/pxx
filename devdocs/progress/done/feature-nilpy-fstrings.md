---
track: N
prio: 55
type: feature
---

# NilPy: f-strings

Hangs off [[feature-nilpy-corpus-uforth]]. 42 sites in uforth.py, and they
are spread through every diagnostic and every word-listing path, so the
corpus cannot produce comparable OUTPUT without them even once it parses.

## Shape

Lex `f"..."` into its literal spans and `{expr}` holes, then lower to the
concatenation NilPy already has: `"a" + str(x) + "b"`. `str()` is already
wired for every scalar and for variants (VariantToStr), so the lowering needs
no new runtime.

Scope for v1 — exactly what the corpus uses:

- plain `{expr}` holes, expressions being names, attribute access, calls and
  subscripts;
- `{{` / `}}` escapes;
- format specs `{x:d}` / `{x:04x}` / `{x!r}` are NOT in v1 unless the census
  says otherwise — check before writing the lexer, because a spec changes the
  hole grammar rather than extending it.

## Why it is worth doing before the Track A blockers clear

It is entirely frontend: no variant reads, no RTTI, no ABI. That makes it one
of the few uforth-blocking features Track N can land alone, alongside
[[feature-nilpy-bytes-and-slices]].

## Landed

v1 landed 2026-07-19 in f8f1231e: plain holes + escapes, expanded in the
source before lexing, holes lowered through pylib's `pystr_of` overloads.
`test/test_nilpy_fstrings.npy` is in `make test-nilpy`, diffed against
CPython.

Completed the same session: `!r` / `!s` conversions (2fd05bda) and format
specs (35e15c0f). The whole uforth f-string census is covered — 64 plain
holes, 18 `!r`, 3 specs.

Spec grammar is `[<|>] [0] [width] [d|x|X|o|b|s]`, interpreted in pylib from
the spec TEXT rather than compiled in the lexer, so one place decides what
"05x" means and adding a spec later needs no frontend change. Anything
outside the grammar halts naming itself.

Still open, if a corpus ever needs them: nested same-quote f-strings (errors
cleanly), triple-quoted f-strings, and `=` debugging specs.

## Gate

`test-nilpy` green with a `.npy` case diffed against CPython + `--tier quick`
+ self-host byte-identical + `make fpc-check`.
