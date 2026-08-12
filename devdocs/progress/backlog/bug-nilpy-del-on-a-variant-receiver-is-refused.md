---
track: N
prio: 48
type: bug
blocked-by: []
summary: "`del d[k]` inside a def whose parameter `d` is unannotated is refused at compile time — the receiver is a variant, and the del lowering only knows statically-typed dicts/lists. The same statement at module level, on a name the pre-pass typed, compiles. Passing a dict to a helper that removes a key is ordinary Python and cannot be written"
---

# `del d[k]` on a VARIANT receiver is refused

- **Type:** bug (compile error on ordinary code) — **Track N**
- **Found:** 2026-08-12, differential bug hunting — a recursion guard
  (`seen[name] = True` … `del seen[name]`), which is the standard shape.

```python
def visit(node, seen):
    seen[node] = True
    ...
    del seen[node]        # <-- error
```

> `pascal26: error: Nil Python: del is supported on a dict subscript, a list
> index, a list slice, or a class with __delitem__ (del d[k], del l[i],
> del l[a:b], del c[k])`

The message lists exactly the form being used, which makes it read as a parser
bug rather than what it is: an **unannotated parameter is a variant**, and the
`del` lowering dispatches on the receiver's STATIC type, so a variant matches
none of its arms.

| shape | result |
| --- | --- |
| `del d[k]` where `d` is an unannotated PARAMETER | **error** |
| `del n[k]` at module level, `n = {...}` above | fine |
| the same inside a def, on a LOCAL dict literal | fine |

## Why it matters

Handing a dict or list to a helper that mutates it is everyday Python — a
memo, a visited-set, a cache, a queue. `d[k] = v` and `d.pop(k)` on the same
variant receiver both work, so `del` is the odd one out, and the workaround
(`d.pop(k)`) is only discoverable if you already know the cause.

## Where to look

The `del` statement's lowering in `pyparser.inc`, next to the arms it already
has. Every sibling operation on a variant receiver already resolves at run time
through the variant helpers — [[project_nilpy_static_vs_variant_operand_paths_diverge]]
is this exact split, and `del` is a case where only the static path was built.
Route the variant receiver to the runtime dict/list delete (the same one
`__delitem__` dispatch uses) rather than adding a fourth static arm.

## Gate

A `.npy` diffed against CPython: `del` on a dict and a list through an
unannotated parameter, an annotated one (`d: dict`), a variant local, a
class-attribute receiver, a chained receiver (`del obj.d[k]`), the KeyError /
IndexError a missing key raises, and the existing static forms still working.
