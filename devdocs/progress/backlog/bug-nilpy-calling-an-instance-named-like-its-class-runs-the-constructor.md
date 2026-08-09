---
prio: 55
track: N
type: bug
blocked-by: []
---

# Calling an instance whose NAME matches a class runs the CONSTRUCTOR

- **Type:** bug (NilPy, **silent wrong value**) — **Track N**; the fix site is
  `compiler/parser.inc`, so it carries Track A file ownership and the sole-A guard
- **Found:** 2026-08-09 by a differential sweep of the class-protocol surface.
- **Owner:** —

```python
class Parser:
    def __init__(self, n):
        self.n = n
    def __call__(self, a):
        return self.n + a

parser = Parser(1)
print(parser.run())      # fine — method calls are unaffected
print(parser(2))         # CPython 3     pxx 131405738672336
```

The result is the instance POINTER printed as a number: `parser(2)` built a
**new `Parser`** instead of invoking `__call__` on the existing one.

## Why this is prio 55

`parser = Parser(...)`, `widget = Widget()`, `p = P(3)` is how Python code is
normally written — the instance takes the class's name in lower case. Any such
object that is CALLABLE silently returns a fresh instance's pointer instead of
its `__call__` result. Method calls on the same object are fine, so a file can
be almost entirely correct and wrong on one line.

It also constructs an object nobody asked for, so a class counting its instances
(or doing anything in `__init__`) is silently off — that is how this surfaced: a
`P.count` class attribute read 3 where CPython said 2.

## Cause — one condition, precisely located

`compiler/parser.inc` ~9060:

```pascal
  if PyExprMode and (CurTok.Kind = tkIdent) and
     (FindUClassNonRecord(CurTok.SVal) >= 0) and
     (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) then
  begin
    CurASTNode := PyClassCreateExpr;
```

`FindUClassNonRecord` is **case-insensitive**, so the identifier `parser`
matches the class `Parser` and any `<ident>(` becomes a construction. Nothing
checks whether the name is already bound as a VALUE.

Same family as the recorded
[[bug-nilpy-a-local-named-like-a-class-is-typed-as-that-class]], which was fixed
for the VALUE position by making that lookup case-sensitive. **The call position
is a separate site and did not get the same treatment** — worth grepping for
other `FindUClass*` uses in decision positions while fixing this, since a third
site is likely.

## Shape of a fix

Stand the intercept down when the name is bound as a value in scope — Python
scoping says a local/parameter/global shadows a class of the same name, which is
the same rule the value-position fix restored. `FindSym(CurTok.SVal) >= 0` is
the direct test; an exact-case class match is the weaker alternative and still
leaves `P = P(3)`-style exact collisions wrong.

Careful with the legitimate case the site exists for: a genuine
`Word("x")` / `tk.Canvas(root)` construction where the name is NOT bound as a
value must keep working, and the comment above it records that reading it as a
record typecast was a previous bug. So the guard is "bound as a value wins",
not "never construct".

## Gate
`.npy` diffed against CPython: an instance named like its class in lower case,
in the SAME case, and one named differently (control); `__call__` and a method
call on each; a class-attribute instance counter proving no extra construction
happens; and a genuine construction of an unbound class name still working.
