---
prio: 68
track: N
type: feature
blocked-by: []
summary: "A user-defined decorator — the ordinary `@wrap` over a `def`, not one of the four recognised names — is refused at parse time: \"unsupported decorator (only @dataclass and @overload)\". The decorator list is a NAME whitelist, so nothing a program declares itself can appear in it."
status: working
owner: frankwasm
---

# A decorator that is not one of the recognised names is refused

```python
def deco(f):
    def w():
        return "wrapped:" + f()
    return w

@deco
def g():
    return "g"

print(g())          # CPython: wrapped:g
```

```
pascal26:9: error: Nil Python: unsupported decorator (only @dataclass and @overload)
  near:   w    >>> deco
```

Found 2026-08-15 while gating [[bug-nilpy-matmul-operator-does-not-parse]] —
the first draft of that test used an ordinary decorator as its "decorator `@`
still parses" control and could not compile. `@property`,
`@staticmethod`/`@classmethod`, `@dataclass` and `@overload` all work; the
message names only two because the other two are recognised elsewhere.

## Why it is a whitelist

Every decorator site in `pyparser.inc` matches on the NAME after the `@`
(`'property'`, `'dataclass'`, …) and rewrites the def accordingly. There is no
general path, so a decorator that is an ordinary callable has nowhere to go.

## What the general form needs

`@d` over `def g(...)` is exactly `g = d(g)` after the def — that is the whole
semantics, including stacking (bottom-up) and `@d(arg)` where the decorator
expression is itself a call. So the shape is a desugaring, not new machinery:
declare the function, then rebind the name to the call result. The two catches:

- **The name's TYPE changes.** After decoration `g` holds whatever `d` returned
  — in the example a closure, not the original function — so the binding has to
  become a callable VALUE, which is the ground
  [[project_nilpy_callable_has_three_representations]] warns about: crossing the
  three callable representations writes a variant tag into a pointer slot.
  Whether the rebind can use the existing closure representation is the first
  thing to measure, not to assume.
- **The recognised four must keep their current lowering.** `@dataclass` and
  `@property` are not `f = dataclass(f)` here — they rewrite the declaration.
  So the general path is a FALLBACK for unrecognised names, and the whitelist
  stays as the fast path rather than being replaced.

## Prio

**68** (frontmatter). This section used to argue for 30 and was left behind by
`ab584382e`, "apply the approved re-triage", which raised it 30 -> 68
deliberately. The frontmatter is what the ranker reads and 68 is the approved
value; the paragraph below is kept as the ORIGINAL reasoning, not as a live
claim, because half of it has since been measured false (see the next section).

> 30. Loud, not silent, and the decorator idiom is common enough in ordinary
> Python (`@functools.wraps`, test registries, memoisation) that a real corpus
> will hit it — but no corpus in this repo is waiting on it today, and the
> callable-representation question above means it is not a small change.

## MEASURED 2026-08-30 (frankwasm): the callable-representation worry does not apply

The "first thing to measure, not to assume" above is measured, and the answer
de-risks this ticket substantially: **the desugaring target already works
today, name-rebind included.**

```python
def deco(f):
    def w():
        return "wrapped:" + f()
    return w
def g():
    return "g"
g = deco(g)          # rebinding the def's OWN name
print(g())           # wrapped:g   — matches CPython
```

`h = deco(g)` under a fresh name works too. So crossing the three callable
representations is not a barrier here: the parser already turns a def name that
is reassigned into a variant global holding the callable, and calling through it
works. `PXXDBG=a.ast` on the working form gives the exact target shape:

```
AN_ASSIGN
  AN_IDENT  ival=475 tk=22        <- g, a VARIANT global (not the proc)
  AN_CALL   ival=1859 tk=22       <- deco
    AN_ARG
      AN_IDENT ival=475 tk=22     <- g again
```

Note `g` is a variant symbol on BOTH sides — by the time the assignment is
built, `g` is no longer the proc. That is the machinery to reuse, not to
rebuild.

**This makes the feature a parse-level desugaring, as the ticket's "What the
general form needs" section hoped, rather than the callable-representation work
it feared.** Remaining unknown: which routine performs that def-name -> variant
conversion, so the decorator path can invoke it rather than duplicate it.

## The implementation template is `PyEvalParamDefault` (pyparser.inc:6899)

It already does the hard part of what a decorator needs — park the cursor, jump
to a saved token range, parse an expression there, and put the cursor back —
and its header documents the two traps:

- restore with `TokPos := savedTok - 1; Next;`, **never** by restoring a saved
  copy of `CurTok`: `Next` does `SetLength(CurTok.SVal, ...)` in place, so a
  record copy taken beforehand comes back holding whatever token the detour
  stopped on. That is a compiler segfault, not a wrong type.
- swap `PyHoistHead` out around the detour, or hoisted setup statements (list
  literals, f-strings, comprehensions) are discarded and the value is silently
  never built.

Token SPLICING is not an option and should not be attempted: statement identity
in this parser is keyed on token INDEX (see the `PyImpAliasStmt` note in
`PyParseImportRun`), so inserting tokens shifts identities the parser relies on.

## Sites

Two module-level decorator sites refuse it — `pyparser.inc:37494` and `:37909`
— plus the in-class set at `:36006`/`:36014`/`:36029`, which have their own
message and their own whitelist (`@property`, `@staticmethod`, `@classmethod`).
A general fallback has to land at each, or they diverge.

## Gate

`.npy` diffed against CPython: a plain decorator, a stacked pair (applied
bottom-up), a decorator taking arguments, a decorated METHOD, and the four
recognised names still lowering exactly as they do now.
