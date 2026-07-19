---
track: N
prio: 55
type: feature
---

# NilPy: string methods (.upper/.lower/.strip/.split/.join/.startswith...)

Part of [[feature-nilpy-corpus-uforth]] milestone 1. Current uforth wall
(with [[feature-rtti-field-reflection]]) at uforth.py:190
`return str(t).upper()` / `t.word.name.upper()`.

Design sketch: method-call syntax on str-typed expressions desugars to
pylib functions (pystr_upper(s), ...), implemented in Pascal over
managed strings. Census uforth's actual set first; CPython is the oracle
(unicode-aware upper() can be ASCII-only v1 with a note — uforth words
are mostly ASCII + emoji, and emoji are case-stable).

Related: str(x) builtin already exists for scalars; needs variant + object
forms (repr-ish) eventually.
