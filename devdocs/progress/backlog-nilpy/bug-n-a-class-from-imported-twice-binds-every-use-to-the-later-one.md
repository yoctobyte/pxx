---
slug: bug-n-a-class-from-imported-twice-binds-every-use-to-the-later-one
track: N
prio: 40
type: bug
status: backlog
owner: ""
created: 2026-11-20
found-by: recorded in bug-n-a-from-import-alias-resolves-its-source-through-flat-scope (2026-11-11), re-measured by rd
tags: [nilpy, import, classes, silent]
blocked-by: []
summary: "`from a import T`, use T, then `from b import T`, use T: both uses construct b's T (pxx `2 2`, CPython `1 2`). Class names bind statically, one answer per scope, so a rebinding import is not flow-sensitive. Silent wrong value."
---

# A class from-imported twice binds every use to the later one

```python
# a.py: class T: def v(self): return 1
# b.py: class T: def v(self): return 2
from a import T
x = T().v()
from b import T
y = T().v()
print(x, y)      # CPython: 1 2   pxx (62ae6a37cd + the residue-1 fix): 2 2
```

Split out of bug-n-a-from-import-alias-resolves-its-source-through-flat-scope
when its value residue was fixed. The value side is per-module now. Values
are bound per symbol, and a main-program rebinding of an imported VALUE is
already flow-correct. Classes resolve through the class table and its alias
rows (PyOwnScopeClassAlias, latest first, FindUClassImpl). That answer is
one per scope for the whole compile, so the later import wins at every use.

Rare in real code: importing two same-named classes into one module without
an alias is usually a mistake there too. That is why it ranks below the value
case it was split from.
