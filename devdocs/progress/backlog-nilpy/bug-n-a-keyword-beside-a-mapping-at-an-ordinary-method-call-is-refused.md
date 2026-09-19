---
slug: bug-n-a-keyword-beside-a-mapping-at-an-ordinary-method-call-is-refused
title: A keyword beside a **mapping at an ordinary method call is refused
track: N
type: bug
prio: 40
status: backlog
owner: ""
created: 2026-09-19
found-by: frankH
tags: [nilpy, kwargs, call]
blocked-by: []
summary: "MECHANISM: at a method with no `*args`/`**kwargs` (the arity-driven call paths, five sites that divert a starred argument into PyStarExpandCallArgs), a `name=value` argument is bound through PyKwArgIndex BEFORE the `**mapping` is seen, and the mapping then fills a contiguous run of slots from the positional count on. So a keyword and a mapping in one call collide: `o.m(1, b=2, **d)` is refused as 'positional argument after keyword argument', and `o.m(**d, a=1, b=2)` as 'got multiple values for parameter a'. Loud refusals, never a wrong value. The constructor and the **kwargs-collecting method paths already fold the whole keyword tail into one mapping (PyParseKwTailIntoMapping + PyStarFillFromMapping, switched at the first keyword when PyDStarAheadInArgs); the fix is the same switch at these sites."
---

# Repro (CPython prints 129 for every line)

```python
class O:
    def m(self, a: int, b: int, c: int = 3) -> str:
        return str(a) + str(b) + str(c)


o = O()
d = {"c": 9}
print(o.m(1, 2, **d))        # works
print(o.m(1, b=2, **d))      # refused: positional argument after keyword argument
print(o.m(**d, a=1, b=2))    # refused: got multiple values for parameter 'a'
print(O().m(1, b=2, **d))    # refused, fresh-receiver site
```

Measured 2026-09-19 at pxx f646378ff plus the constructor fold, compiler
4dbf05fb027e, oracle CPython 3.14.4.

# What is already done beside it

`Engine(key=k, **d)` (a constructor) and `o.k(1, b=5, **d)` into
`def k(self, a, b=2, **kw)` both work. See
`test_nilpy_keywords_and_a_mapping_bind_by_name_at_a_construction`. The
helpers are shared and take any callee, so this is wiring, not design.

Not on That Space Program's path: it spells this shape only at a constructor.
