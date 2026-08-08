---
prio: 30
track: N
type: bug
blocked-by: []
status: done
owner: claude-AN
---

# `del obj[k]` does not dispatch `__delitem__`

- **Type:** bug / missing protocol (NilPy) — **Track N**
- **Split out of** [[bug-nilpy-unsupported-protocols-repr-iter-getattr-delitem-hash]] 2026-08-09
- **Loud:** a compile error, not a wrong answer.

```python
class C:
    def __delitem__(self, k):
        print("DELITEM", k)

c = C()
del c[3]        # CPython: DELITEM 3
```

```
pascal26:5: error: Nil Python: del is supported on a dict subscript or a list slice
```

Re-measured at HEAD 2026-08-09: unchanged.

## Why this is the smallest of the three siblings

`del` already lowers a dict subscript and a list slice, and the error message
above enumerates exactly the arms that exist. This is one more arm on a
construct that is already there — a user class whose class declares
`__delitem__` — not new machinery.

Its siblings `__getitem__`/`__setitem__` are already dispatched
(`test_nilpy_dunder_getitem_setitem.npy`), so `__delitem__` is the odd one
missing out of the three-member subscript protocol. Follow that test's lowering.

## Gate

`.npy` diffed against CPython: `del c[k]` on a class declaring `__delitem__`,
a class declaring `__getitem__` but NOT `__delitem__` (must raise TypeError, as
CPython does, not compute), and controls that `del d[k]` on a dict and
`del xs[i:j]` on a list are unchanged.

## Fixed (2026-08-09, claude-AN)

`del c[k]` dispatches `__delitem__`. The subscript protocol's three members are
now all wired.

### TWO node shapes, and testing one hides the other

The subscript arm in `parser.inc` only claims a class that declares
`__getitem__`, so what reaches the `del` handler differs:

| the class declares | the read lowered to | del rewrite reads |
| --- | --- | --- |
| `__getitem__` **and** `__delitem__` | a CALL of `__getitem__` | receiver and key = its two arguments |
| only `__delitem__` | a generic `AN_INDEX` | `ASTLeft` / `ASTRight` |

The delitem-only shape is not exotic — it is what a class supporting removal
but not reading looks like, and CPython accepts it. Both are in the test
(`Store` and `OnlyDel`).

### Read back, not re-parsed

Both shapes are read off the node the grammar already built. Re-parsing the base
and subscript would mean re-implementing the postfix grammar — the duplication
this frontend keeps getting bitten by, and `del vm.handles[fid]` has a field
base. It also keeps the key expression evaluated **exactly once**, which
`del s[which()]` asserts: a rewrite that rebuilt the subscript would call
`which()` twice, and "key evaluated" appearing twice is the failure that catches.

### No shared-file edit

Done entirely in `pyparser.inc` (Track N's own file) plus a `PyNoDelitemError`
in `pylib.pas`. The tempting version — teaching `parser.inc`'s subscript arm
about `__delitem__` — would have touched Track A's shared parser for no gain,
since the node it produces is enough to rewrite from.

A class with no `__delitem__` raises a runtime `TypeError` rather than a compile
error, so `try/except TypeError` around it still builds — the same rule
`PyNoSetitemError` follows on the assignment arm.

### Verification

`test/test_nilpy_delitem_dunder.{npy,expected}` (`.expected` from CPython):
both node shapes, single key evaluation, the no-`__delitem__` TypeError, and
controls that `del d[k]` / `del l[i]` / `del l[a:b]` are unchanged.
`test_nilpy_{dunder_getitem_setitem,del_list_index,dict_pop,dict,list,
list_pop_at_index_keeps_the_rest}` re-diffed against CPython: match.
`tools/gate.sh quick` GREEN.

### Noticed, not fixed
A subscript READ on a class declaring `__setitem__`/`__delitem__` but NOT
`__getitem__` still falls through to the generic index node and yields a silent
wrong value — filed as [[bug-nilpy-subscript-read-without-getitem-yields-garbage]].

## Log
- 2026-08-09 — resolved, commit 58256d364.
