---
track: N
prio: 55
type: bug
blocked-by: []
summary: "`mk()[0].n` answers 7 for EVERY field — including a str field — where CPython answers 3. 7 is VT_OBJECT, the variant's TAG word: the attribute read off a subscript of a CALL RESULT yields the receiver's tag instead of reading the attribute. Binding the element to a name first is correct, and so is `[B(8)][0].n` on a literal list"
---

# An attribute off a subscript of a call result yields the variant TAG

- **Type:** bug (silent wrong value) — **Track N**
- **Found:** 2026-08-13, differential sweep against CPython.
- **Pre-existing:** identical on `stable_linux_amd64/default/pinned`.

```python
class B:
    def __init__(self, n):
        self.n = n
        self.m = "s"

def mk():
    return [B(3), B(1)]

print(mk()[0].n)     # pxx 7      CPython 3
print(mk()[0].m)     # pxx 7      CPython 's'
e = mk()[0]
print(e.n, e.m)      # pxx 3 s    CPython 3 s   — correct
```

**7 is the answer for every field, whatever its type**, which is what names the
cause: `VT_OBJECT` is tag 7, so the expression is yielding the receiver
variant's first word — its TAG — rather than performing an attribute read at
all.

## The boundary — measured

| expression | pxx | CPython |
| --- | --- | --- |
| `mk()[0].n` (call → subscript → attr) | **7** | 3 |
| `mk()[1].n` | **7** | 1 |
| `mk()[0].m` (a str field) | **7** | `'s'` |
| `d["k"][0].n` (dict → subscript → attr) | **7** | 7 — right by accident |
| `list(reversed([B(4), B(5)]))[0].n` | **7** | 5 |
| `[B(8)][0].n` (a LITERAL list) | 8 | 8 |
| `e = mk()[0]; e.n` | 3 | 3 |
| `xs = mk(); xs[0].n` | 3 | 3 |
| `mk()[0]` printed as an object | correct | correct |
| `type(mk()[0]).__name__` | `B` | `B` |
| `one().n` where `one()` returns a B | 5 | 5 |

So the subscript itself is right (the element prints, and its TYPE is right),
one call-result attribute is right, and only the CHAIN
call → subscript → attribute is wrong. The `d["k"][0].n` row is the dangerous
one: it happens to be right for the value 7 and would be wrong for any other.

## Where to look

The chained-selector path (`PyParseClassRecordSelectors` in pyparser.inc, the
NilPy copy). A subscript of a call result yields a VARIANT element; the
attribute after it must go through `pydynattr_get_v` (which works — the
bound-name rows prove it), and instead something is reading the variant slot's
first word. Suspect the static type carried out of the subscript: if the element
node is typed tyClass with a rec, the `.field` becomes an AN_FIELD at a computed
offset over a variant SLOT rather than over the object it holds.

Same family as [[project_nilpy_lvalue_vs_selector_path_must_both_know]] — member
access by RECEIVER SHAPE, where a bare name and a call result take different
parsers.

## Gate

A `.npy` diffed against CPython: every row of the table above, an int field, a
str field, a float field, a nested call (`mk()[0].inner.n`), a method call after
the subscript (`mk()[0].describe()`), and the bound-name controls kept in the
file.
