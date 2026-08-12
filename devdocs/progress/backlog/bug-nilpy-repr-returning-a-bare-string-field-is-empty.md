---
track: N
prio: 55
type: bug
blocked-by: []
summary: "A `__repr__` whose body is `return self.n` (a bare string field, directly or through a local) yields the EMPTY string — so `repr(obj)` prints nothing and `print([obj])` prints `[, ]`. `return self.n + \"\"`, a literal, or `str(self.k)` are all fine, and the identical body in a PLAIN method or in `__str__` is fine, so it is repr's dispatch path losing the string"
---

# `__repr__` returning a bare string field comes back empty

- **Type:** bug (silent wrong value) — **Track N**
- **Found:** 2026-08-12, differential bug hunting against CPython.

```python
class P:
    def __init__(self, n):
        self.n = n

    def __repr__(self):
        return self.n

    def plain(self):
        return self.n


p = P("x")
print(p.plain())     # x        — correct
print(str(p))        # x        — correct
print(repr(p))       #          — EMPTY, CPython says x
print([p])           # [, ]     — CPython says [x]
```

Printing a *container* of such objects is the common way to meet this: every
element renders as nothing, so a list of ten objects prints as `[, , , , , , , ,
, ]` — no error, no crash.

## The boundary — measured

| `__repr__` body | pxx `repr()` | CPython |
| --- | --- | --- |
| `return self.n` | **empty** | `x` |
| `s = self.n; return s` | **empty** | `x` |
| `return self.n + ""` | `x` | `x` |
| `return "lit"` | `lit` | `lit` |
| `return str(self.k)` (int field) | `5` | `5` |
| the same `return self.n` in a PLAIN method | `x` | `x` |
| the same `return self.n` in `__str__`, via `str(obj)` | `x` | `x` |

So the value, the field and the method body are all fine. What distinguishes
the failing rows is that the returned AnsiString is *the field's own string*,
handed back through the **repr** dispatch — concatenating anything onto it (or
building a fresh string) makes it work, which is the signature of a managed
string being released, cleared or not retained across that particular return.

`str()` on the same object taking the same body correctly is the useful control:
this is one of the [[project_nilpy_three_rendering_paths_print_str_fstring]]
sites, and repr is the one that is wrong.

## Where to look

The runtime dunder dispatch (`PyFindDunder` — note every dunder has two param
shapes) on the **repr** path, and what it does with an AnsiString Result whose
value is a field rather than a fresh allocation. `-dPXX_OBJTRACE` plus
`PXXDBG=n.locals` on the repr thunk, and a comparison against the `__str__`
path that works, is the shortest route — the difference between the two call
paths IS the bug.

## Gate

A `.npy` diffed against CPython: every row of the table above, plus `repr` of an
object inside a list / dict value / tuple, `"%r" % obj`, `f"{obj!r}"`, and a
`__repr__` returning a field of a subclass — with the `__str__` and plain-method
controls kept in the same file so a fix that breaks THEM is caught.
