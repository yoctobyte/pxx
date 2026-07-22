---
track: N
prio: 65
type: bug
---

# NilPy: storing a class value into a variant-typed local mis-tags it VT_INT64

## Repro (4 lines, no file I/O)

```python
x = None            # x inferred tyVariant
b = bytes([1, 2, 3])
x = b               # class (TPyBytes) stored into the variant local x
print(x[0])         # runtime: TypeError: object is not subscriptable
```

`b = bytes([...]); x = b; print(x[0])` (no `x = None` first) WORKS — there x is
inferred TPyBytes, and `x[0]` is a direct bytes getitem. The failure needs x to
be a VARIANT local (forced by the earlier `x = None`, which widens
None ⊕ bytes → variant).

## Root cause

`x = b` where x is tyVariant and b is tyClass should lower to
`IR_VAR_STORE(..., Ord(tyClass))`, which codegen tags **VT_OBJECT** (7). At
runtime the slot is tagged **VT_INT64** (2) instead, so `pyvar_getitem` /
`pyvar_slice` see a non-container and raise. Instrumentation shows the
`x = b` assignment does NOT reach the variant-target store branch
(ir.inc:6170) with an AN_IDENT rhs, so a class-typed ident RHS into a variant
IDENT lvalue is taking some other path that stores the raw pointer with the
scalar/int tag. Needs tracing which AN_ASSIGN arm handles it (the
variant-target class-source boxing at ir.inc:6196 IS correct; something
upstream diverts).

## Impact

Blocks uforth READ-LINE (`remainder = d["rem"]` variant, then
`remainder = raw` bytes, then `remainder[:u1]`) — the last file-word blocker.
Also the general Python idiom `x = None; ...; x = <container>` any time the
None forces x to variant. File I/O itself (TPyFile, raw syscalls) is done and
CREATE/WRITE/CLOSE verified. Related: the module-scope half was fixed in
5d4a1c49; this is the container-identity-through-variant half.
