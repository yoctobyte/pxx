---
track: N
prio: 35
type: bug
blocked-by: []
commit: 42ba5044e
summary: "`mk(5)[2]` on a class declaring __getitem__ printed the OBJECT POINTER, `C(5)[2]` did not parse, `mk()[k] = v` was refused, and a user object held in a VARIANT raised 'not subscriptable'. The subscript protocol was wired to one receiver shape — a named variable — out of four."
---

# A subscript sees `__getitem__` only through a named receiver

```python
class C:
    def __init__(self, v): self.v = v
    def __getitem__(self, i): return self.v + i

def mk(v): return C(v)

c = C(5); print(c[2])       # 7          — the shape that worked
print(mk(5)[2])             # CPython 7  — pxx printed 137517835747360
print(C(5)[2])              # CPython 7  — pxx: error: unexpected token
xs = [mk(1)]; print(xs[0][3])
                            # CPython 4  — pxx: TypeError: object is not subscriptable
```

Found 2026-08-15 by a CPython differential sweep of the dunder surface. The
first row is the bad one: a plausible large integer, printed where an element
was expected, with no diagnostic — `devdocs/dev/debugging-playbook.md`'s opening
failure class.

## One protocol, four receiver shapes, one of them wired

`ParseLValueAST`'s suffix loop has dispatched `__getitem__` since the protocol
landed. The other three paths had not:

| receiver | before |
| --- | --- |
| a NAME — `c[2]` | correct |
| a call result / chain — `mk(5)[2]`, `o.child()[k]` | raw AN_INDEX over the instance handle → **the pointer** |
| a CONSTRUCTION — `C(5)[2]` | parse error: the ctor arm applied no selectors |
| a VARIANT holding the object — `xs[0][3]`, a for-loop variable | run-time TypeError |

`PyParseClassRecordSelectors` — the chained loop — now dispatches both halves of
the protocol (read and, by peeking past the balanced brackets for a trailing
`=`, write), exactly as its default-property arm already did for Pascal; the
NilPy ctor arm hands a following `[` to that same loop, the way the Pascal cast
arm hands over its own result; and `pyvar_getitem` consults `__getitem__`
through `PyUserArithCall1` when the variant holds a user object, so the shape
with no static class agrees too. That function's header already records this
same "two parsers by receiver shape" failure twice for other members
(`project_nilpy_lvalue_vs_selector_path_must_both_know`).

A class declaring only `__setitem__` keeps the run-time TypeError on a READ, and
one declaring neither is untouched — the named path's trades, now shared.

## Not this bug, confirmed by measurement

`obj[2:3]` on a user class does not parse for a NAMED receiver either, so it is
not a receiver-shape gap: it needs `slice` objects, which this dialect does not
have ([[bug-nilpy-four-remaining-absent-builtins]]). `__delitem__` through a
variant likewise stays a loud refusal — it needs a 3-argument dispatcher that
does not exist, as `pyvar_delitem`'s own comment says.

## Gate

`test/test_nilpy_getitem_on_a_call_result.npy` (+`.expected`, in the Makefile),
byte-identical to CPython: a named receiver as the control; a call result, a
construction, a chained call, and a subscript whose KEY is itself a subscripted
call; two subscripted call results added together (so a re-evaluated receiver
would show); the object held in a list, in a dict value and as a for-loop
variable; and `__setitem__` through a name and through a call result.
`gate.sh quick` GREEN, pinned v330.
