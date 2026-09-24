---
track: N
prio: 30
type: compat
blocked-by: []
summary: "Two legal Python target spellings are REFUSED at compile time (loud, not wrong): an attribute as a for-loop target (`for b.s in range(3):` -> `expected 'in' before '.'`) and an attribute of a SUBSCRIPT inside an unpack target list (`xs[0].s, xs[1].s = 5, 6` -> `expected '=' before ','`). Both are rare spellings; the plain-name, attribute-of-name and subscript targets all work."
---

# Two attribute target spellings are refused

Found 2026-09-24 (frankb-12) varying the receiver shapes of the unpack/chain
store group. Measured at HEAD against CPython 3:

```python
def forloop(b):
    for b.s in range(3):      # pxx: expected 'in' before '.'
        pass
    print(b.s)                # CPython: 2

def inlist(xs):
    xs[0].s, xs[1].s = 5, 6   # pxx: expected '=' before ','
    print(xs[0].s, xs[1].s)   # CPython: 5 6
```

Loud refusals, so compat rather than a bug: nothing compiles wrong. Ranked on
how much real code uses them, which is little: measured 2026-09-24, ZERO
occurrences of either across 195 `.py` files (`/home/neo/lekkerzeilen` and
`/home/neo/projects/uforth`, line-grep for `for <name>.<attr>` and for
`<name>[...].<attr> , ... =`; a multi-line target list would escape the grep). The unpack target
parser already handles `name.attr` and `name[...]`; the second shape is the
composition of the two. The for-target parser takes names and nested groups only.
