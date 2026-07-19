---
track: N
prio: 35
type: bug
---

# NilPy: cannot subscript a string LITERAL — `"abc"[1]`

Found 2026-07-19 alongside [[bug-nilpy-str-index-off-by-one]].

```python
print("abc"[1])
```
```
pascal26: error: unexpected token (   near: abc >>>
```

Same root shape as the str-method case: the subscript is parsed in
`ParseLValueAST`, and a literal is not an lvalue, so the `[` is never
consumed. An ident, field or call-result base is fine.

Fix shape: the `ParseFactor` wrapper added for str methods
([[feature-a-nilpy-str-method-parser-hook]]) is the natural home — give it a
subscript suffix alongside the `.method(` suffix, routed through
`PyMakeStrIndex` so it inherits the 0-based/negative semantics for free.

Low priority: rare in real code and in the uforth corpus (which indexes
variables, not literals).
