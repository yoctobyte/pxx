---
track: A
prio: 40
type: bug
blocked-by: []
summary: "`f(**d)` fails with \"expected expression\" because parser.inc:15874 enters the NilPy star-forwarding branch on a single tkStar, consumes one, and then tries to parse `*d` as an expression. `**` is two tkStar and the TRAILING position twelve lines below already knows that; the leading position never looks ahead. ~5 lines. The runtime already works — `f(*[], **d)` compiles and matches CPython today."
---

# A leading `**` in a NilPy call is never detected

- **Type:** bug (parser) — **Track A** (`compiler/parser.inc`, shared A/P file).
- **Filed by:** frank2 on Track N, 2026-08-17, working
  [[bug-nilpy-a-dict-cannot-be-unpacked-into-a-call]]. Track N owns
  `pylexer.inc` / `pyparser.inc` / pylib and may not edit `parser.inc`, so this
  is filed and handed off per CLAUDE.md.

## Repro

```python
def f(a=1, b=2): return a + b * 10
d = {"a": 5, "b": 6}
print(f(**d))
```

```
pascal26:6: error: expected expression
  near:  print  f   >>>  d
```

CPython prints `65`. Every callee shape fails the same way (plain def,
`**kwargs` def, method, constructor) — because none of them get as far as the
callee.

## Root cause, exact

`compiler/parser.inc:15874-15878`:

```pascal
else if isNilPy and (CurTok.Kind = tkStar) and (ProcPyStarIdx[procIdx] < 0) and
        not PyStarIsIterableForm(name) then
begin
  Next;                          { the '*' }
  ParseArgExpr;                  { <-- CurTok is the SECOND '*' of a `**` }
```

`**` is lexed as two `tkStar`. The **trailing** star pair, twelve lines below in
the same branch, knows this and handles it:

```pascal
if CurTok.Kind = tkStar then Next;   { `**` is two tkStar }
```

The **leading** position has no such look-ahead. `f(**d)` therefore enters the
branch, eats one star, and `ParseArgExpr` fails on `*d`. The error names neither
the star nor the callee, which is why it reads as a syntax error in user code.

## The fix, and why it is small

On entry, look ahead exactly as the trailing position does: if the next token is
also `tkStar`, consume both, parse the dict into `fwdDict`, and synthesise an
**empty list literal** for `fwdList`. That lowers `f(**d)` to `f(*[], **d)`.

**No runtime change is needed, because that form already works.** Measured on
`compiler/pascal26` at HEAD:

```python
def f(a=1, b=2): return a + b * 10
d = {"a": 5, "b": 6}
print(f(*[], **d))          # pxx 65   CPython 65
print(f(*[], **{"b": 9}))   # pxx 91   CPython 91   <- default for `a` preserved
```

`PyStarForwardCall(procIdx, listNode, dictNode)` already accepts the dict and
already binds keys onto named slots preserving defaults. Do **not** write a
second keyword-binding desugar; the originating ticket designed one before
discovering this, and a second mechanism for one concept is the smell
`devdocs/dev/normalise-dont-special-case.md` names.

## Scope — deliberately just the parse

After this fix, `f(**d)` reaches exactly what `f(*[], **d)` reaches today:
free functions with ordinary parameters, defaults preserved. Three callee
shapes stay broken and are **out of scope**, each already refusing by name:

- `def g(**kw)` — run-time `TypeError: forwarded call got 2 arguments,
  expected 1 to 1`
- a constructor whose `__init__` takes `**kwargs` — compile error, "not
  supported yet"
- a method with defaulted parameters — compile error, "it has parameters with
  defaults"

Bundling those in turns a five-line parser fix into a project. They belong in
Track N tickets against `PyStarForwardCall` and the constructor path.

## Gate

`make compiler/pascal26` + a `.npy` diffed against CPython covering `f(**d)`
full, `f(**d)` partial (defaults preserved), `f(x, **d)` mixed, and
`dict(**d)` still working, then `tools/gate.sh quick`.

Note `dict(**d)` and `f(*lst)` both work **today** and must keep working —
they go through different paths and are the regression risk.
