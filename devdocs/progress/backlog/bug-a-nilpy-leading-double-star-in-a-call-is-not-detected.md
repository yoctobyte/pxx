---
track: A
prio: 40
type: bug
blocked-by: []
summary: "`f(**d)` fails with \"expected expression\" because parser.inc:15874 enters the NilPy star-forwarding branch on a single tkStar, consumes one, and then tries to parse `*d` as an expression. `**` is two tkStar and the TRAILING position twelve lines below already knows that; the leading position never looks ahead. ~5 lines. The runtime already works — `f(*[], **d)` compiles and matches CPython today."
status: working
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

## RE-MEASURED 2026-08-17 (frank2, Track A) — half of this is already fixed; the other half is NOT ~5 lines

Claimed, re-measured, returned **unstarted**. No code touched. The estimate and
the "every callee shape fails the same way" claim are both wrong at HEAD, in
opposite directions.

### Measured at HEAD, per callee shape, against CPython

| shape | pxx | CPython |
| --- | --- | --- |
| `f(**d)`, plain def | **65** | 65 |
| `f(**d)`, `**kwargs` def | **605** | 605 |
| `f(*[7], **{...})` | **87** | 87 |
| `C().m(**d)` | **`expected expression`** | 60005 |
| `C(**d)` | **`expected expression`** | 6005 |

So the free-function arm **is already fixed** — `parser.inc:15875` carries the
lowering and cites this ticket by slug. What is left is methods and
constructors only.

### The remaining half has a different, deeper cause than this ticket states

This ticket blames one lookahead at a single site. That was true of the
free-function arm. For methods it is not the cause, and the giveaway is that
the plain single-star form fails too:

    C().m(*[5, 6])
      -> Nil Python: *unpacking into C.m is not supported — it has parameters
         with defaults, whose values a compile-time expansion cannot preserve

**Free functions and methods do not share a mechanism.** Free functions got
`PyStarForwardCall` — a RUN-TIME arity dispatch, which is exactly what
preserves defaults. Methods route to a COMPILE-TIME expansion
(`pyparser.inc:13176`) that explicitly refuses any callee with defaults. So
`C().m(**d)` cannot be made to work by fixing a lookahead: there is no
forwarding path on the method side to lower into.

Correct scope for the remainder: **give methods and constructors the run-time
forwarding dispatch free functions already have**, so one concept has one
mechanism (`normalise-dont-special-case` — and the free-function fix's own
comment makes the same argument about not building a second path). That is a
feature-sized change in `pyparser.inc` + `parser.inc`, not ~5 lines, and it
subsumes `C().m(*xs)` into defaults as well.

### Recommended re-title and re-file

The title names a lookahead that is no longer the problem. Suggest
"`*`/`**` unpacking into a method or constructor with defaults has no
forwarding path" — and note it is **not** blocking any corpus wall I measured
today, so it can be ranked on its own merits rather than as a quick win.

`PyStarArgAhead` (`pyparser.inc:13233`) deliberately returns False for `**`;
that is correct for what it is asked and is not the defect.

### One thing worth fixing cheaply, separately

`C().m(**d)` reports `expected expression`, which names neither the construct
nor the callee, while the single-star sibling gives a clear "not supported —
has parameters with defaults" message. Making the `**` method case reach that
same honest diagnostic is small and independent of the feature above. Left
undone here only because the check would land at three or four method
argument sites, and this file already warns that four sites asking one
question is the shape to avoid — so it wants the shared-helper treatment, not
a paste at each.
