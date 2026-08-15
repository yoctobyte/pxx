---
track: N
prio: 30
type: bug
commit: c9be1dddb
blocked-by: []
summary: "`setattr(o, name, v)` was `undefined variable` — the READ half of a dynamic attribute (hasattr/getattr) was expressible and the WRITE half was not, on a receiver whose `o.name = v` already writes through the same store."
---

# `setattr` is absent

```python
p = P()
setattr(p, "y", 7)      # pascal26: error: undefined variable (setattr)
print(getattr(p, "y"))  # ...while THIS half has been here all along
```

Found 2026-08-15 by a CPython differential sweep over the builtin surface, one
name at a time. Loud, and trivially worked around by `p.y = 7` for a LITERAL
name — but the shape setattr exists for is the computed one, `setattr(o, "f_" +
k, v)` in a loop, which has no other spelling.

## Fix

The trio's three members share one store: `PyMakeDynAttrSet` for a literal name
(what `o.name = v` compiles to), and a new `PyMakeDynAttrSetByExpr` for a
computed one — the mirror of `PyMakeDynAttrByExpr`, which getattr/hasattr have
had for computed names since that path landed. A name resolving to a DECLARED
field builds the ordinary field store, so `setattr(p, "x", 5)` and `p.x = 5`
write the same slot rather than two.

A user `def setattr` shadows it, which is Python's rule and the pattern this
family of intercepts follows.

## Also absent, measured in the same sweep, NOT fixed here

`delattr`, `globals()`, `locals()` — re-filed as
[[bug-nilpy-delattr-globals-and-locals-are-absent]]. `delattr` needs a runtime
entry that does not exist (there is no `pydynattr_del` to call), and
`globals`/`locals` want a run-time name table this dialect deliberately does not
build — the same answer `exec(src)` with no namespace already gives.

## Gate

`test/test_nilpy_setattr.npy` (+`.expected`, in the Makefile), byte-identical to
CPython: a declared field written both ways (one slot, not two); an undeclared
attribute through the dynamic store, read back by all three of `p.y`, `getattr`
and `hasattr`; a computed name from a variable and from a concatenation; the
loop idiom; overwriting with a str, a list and None; the absent-attribute rows
unchanged; and a second instance not seeing the first's dynamic attributes.
`gate.sh quick` GREEN. No pin — frontend-only.
