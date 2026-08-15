---
track: N
prio: 55
type: bug
blocked-by: []
summary: "A second `.method()` on the result of a RUNTIME-DISPATCHED method call is a parse error. The dispatcher hands back an AN_TERNARY (the `pyvar_is_strtag(recv) ? str-method : class-method` fan), and every suffix loop in ParseFactor's Python cluster that could claim the next link requires AN_CALL. `open(p).read().strip()` parsed; `.strip().upper()` did not."
status: done
---

# A chained method on a runtime-dispatched result is refused

## Symptom

```python
p = "/etc/hostname"
print(open(p).read().strip().upper())
```

```
Expected: ), but got:  (Kind: 81, Line: 2)
pascal26:2: error: unexpected token
  near:    strip   >>>  upper
```

One link (`.strip()`, `.upper()`) always worked. Any second link failed, for
every name — strip, upper, lower, replace, title.

## Root cause

`PyStrMethodLosesToClass(mname)` is True when some class in the program also
declares the name. Then `PyParseVariantMethod` builds the runtime fan and
returns an **AN_TERNARY**, not an AN_CALL. Back in ParseFactor's suffix
cluster, the two loops that could take the next suffix off a dynamically typed
receiver — the `.method()` loop and the bare-attribute loop — both gate on
`ASTKind[CurASTNode] = AN_CALL`. Nothing claimed the ternary, so the '.' was
left for whoever came next: `unexpected token`.

This is the same family the cluster's own header comment describes (nine loops,
one concept), and the same asymmetry as
`bug-nilpy-a-bare-attribute-on-a-call-result-is-refused`: the receiver SHAPE,
not the language, decided whether a suffix was legal.

## Why it surfaced now

The predicate is program-dependent, so the gap was latent: it needed a name
declared by both the str table and a class. Adding the Python method set to
`TPyBytes` (`bug-a-bytes-has-almost-none-of-its-python-methods`) put
strip/upper/lower/replace/split/join/index into every program's class scan at
once, and three tests in the nilpy suite went red — `test_nilpy_encode`,
`test_nilpy_encode_decode_codecs`, `test_nilpy_intrinsic_result_chain`.

## Fix

Both loops admit `AN_TERNARY` beside `AN_CALL`. A user's own
`(a if c else b).upper()` lands there too, which is right — Python's grammar
lets a primary take a suffix whatever produced it.

## Gate

`make compiler/pascal26` + `tools/gate.sh quick` GREEN. The five affected tests
verified against CPython / their `.expected`:
`test_nilpy_intrinsic_result_chain` is the regression test — it pins exactly
this chain, one to four links deep.

## Log
- 2026-08-16 — resolved, commit e10590243.
