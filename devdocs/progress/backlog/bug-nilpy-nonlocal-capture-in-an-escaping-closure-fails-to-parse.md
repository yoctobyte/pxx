---
track: N
prio: 45
type: bug
---

# A `nonlocal` capture in an ESCAPING closure fails to parse at the call site

```python
def counter():
    n = 0
    def bump():
        nonlocal n
        n += 1
        return n
    return bump
bp = counter()
print(bp())          # pascal26:9: error: unexpected token  (near: bp)
                     # CPython: 1
```

A compile error, not a wrong value — so this is the good failure mode, and it is
filed separately from
[[bug-nilpy-escaping-closure-captures-unbound-unless-arity-is-one]] (now fixed),
which was the silent one.

## Boundary

The same closure WITHOUT `nonlocal` parses and now runs correctly at every
arity. Called while the parent frame is still alive, the `nonlocal` form also
works — `return bump()` inside `counter` yields 1. It is specifically
`nonlocal` + escaping that fails, and it fails at the CALL site (`bp()`), not at
the def.

## Likely cause

`nonlocal x` makes that capture a BY-REF trailing parameter, so the write lands
in the enclosing frame (`pyparser.inc`, PyParseDefHeader:
`if PyBodyDeclaresNonlocal(...) then Procs[procIdx].Params[nOwn + j].IsRef := True`).
The value-closure path has no way to bind a by-ref parameter — `pyboundfn_bind`
stores a word, `pyboundfn_bind_var` a heap Variant slot, and the new
`pyboundfn_bind_obj` a retained object, none of which is "the address of the
enclosing local". Something in that mismatch leaves the resulting value typed
such that `bp()` no longer parses as a call.

Worth confirming with `PXXDBG=n.caps` and by dumping the type the name `bp`
ends up with, rather than assuming — the parse error is a symptom several
layers from whatever the real cause is.

## Note on semantics

Even once it parses, `nonlocal` through an escaped closure needs the captured
cell to OUTLIVE the enclosing frame — CPython gives every closure over the same
frame a shared cell, so two calls to `bump()` return 1 then 2, and two separate
`counter()` results have independent cells. Binding the enclosing local's
ADDRESS would dangle exactly the way the class capture did before
`pyboundfn_bind_obj`. The fix probably wants a heap cell per captured
`nonlocal`, bound like `pyboundfn_bind_var` already does, with the body's
by-ref parameter pointed at it.

## Gate

`make test-nilpy` + self-host byte-identical, plus the counter above and a
two-instance case (`c1 = counter(); c2 = counter()`) diffed against CPython.
The non-`nonlocal` shapes are already covered by
`test/test_nilpy_escaping_closure.npy` and must stay green.
