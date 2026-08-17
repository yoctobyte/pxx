---
track: N
prio: 40
type: bug
blocked-by: [bug-a-nilpy-leading-double-star-in-a-call-is-not-detected]
summary: "`f(**d)` — unpacking a dict into a call — is a PARSE error (\"expected expression\") for every callee shape: a plain def, a **kwargs def, a method, a constructor. Only the forwarding shape `f(*args, **kwargs)` inside a def that declares them works."
status: unfinished
owner: —  # handed off: the fix is in parser.inc (Track A)
---

# A dict cannot be unpacked into a call

Found 2026-08-16 by a `tools/pydiff.py` sweep, not by a report.

## Measured — the boundary is "is it the enclosing def's own star pair"

```python
def f(a=1, b=2): return (a, b)
d = {"a": 5, "b": 6}
f(**d)                     # pascal26: error: expected expression   near: f >>> d

def g(**kw): return kw
g(**d)                     # same

class C:
    def __init__(self, **kw): self.n = len(kw)
C(**d)                     # same
C().m(**d)                 # same

def fwd(*args, **kwargs):
    return f(*args, **kwargs)   # WORKS — the one supported shape
```

So the star pair is only understood when it names the enclosing def's own
collectors, which is what `PyStarForwardCall` was built for. An ordinary dict
is not accepted anywhere.

## Why it matters

`f(**opts)` is one of Python's core call forms — config dicts, argparse
namespaces, `dict(**base, extra=1)`, every wrapper that passes options
through. And the failure is a PARSE error naming neither the star nor the
callee, so it reads as a syntax problem in the user's code.

## Design — the callee's parameters are known, so this can be a desugar

The machinery is nearly all there. `PyStarForwardCall` already desugars
`f(*args)` into a dispatch over the arities the callee accepts, and refuses
keyword forwarding with the comment *"binding a runtime dict onto named
parameters needs a call protocol NilPy does not have"*. That is true of the
GENERAL case and not of this one: at a call site the callee is known, so its
parameter names are known, and `f(**d)` can lower to

```
    pystar_check_kwnames(d, "a", "b", ...)      (hoisted; refuses an unknown key
                                                 exactly as CPython's TypeError does)
    f(a := d.get("a", <default a>), b := d.get("b", <default b>), ...)
```

with a required parameter's missing key raising rather than defaulting. That is
the same shape the positional forwarder uses, one level simpler because there
is no arity dispatch — the slot count is fixed.

Mixed `f(x, **d)` and `f(**d, y=1)` fall out of the same lowering: the
explicitly-written arguments win their slots and the dict fills the rest.

The genuinely hard case stays refused: a callee that is a VALUE (a variable
holding a function) has no known parameter list, so `cb(**d)` there needs the
runtime protocol and should say so by name.

## Gate

A `.npy` diffed against CPython covering: a plain def, a defaulted def with a
partial dict, a `**kwargs` def, a method, a constructor, the mixed forms, an
unknown key (TypeError), and a missing required key (TypeError). Plus the
per-fix loop.

---

## MEASURED 2026-08-17 (frank2, Track N) — the filed diagnosis is wrong in three places, and the real defect is ~5 lines in a file Track N may not edit

Measured against `compiler/pascal26` at HEAD, CPython as the oracle. **Do not
build the desugar this ticket designs — almost all of it already exists and
works.**

### Correction 1: `**` is NOT a parse error for every callee

`dict(**d)` compiles and runs, including the mixed forms:

| | pxx | CPython |
| --- | --- | --- |
| `dict(**d)` | `{'a': 5}` | `{'a': 5}` |
| `dict(d, **{"b":6})` | `{'a': 5, 'b': 6}` | same |
| `dict(**d, b=6)` | `{'a': 5, 'b': 6}` | same |

### Correction 2: the boundary is NOT "the enclosing def's own collectors"

`f(*lst)` and `f(*t)` with an ordinary list/tuple — nothing to do with any
enclosing def — both work and match CPython. Positional unpacking is general
already.

### Correction 3: the keyword machinery is BUILT, and correct

`PyStarForwardCall(procIdx, listNode, dictNode)` already takes a dict, and it
already binds keys onto named slots while preserving defaults. Proof, today, on
the unmodified compiler:

```python
def f(a=1, b=2): return a + b * 10
d = {"a": 5, "b": 6}
print(f(*[], **d))          # pxx 65   CPython 65
print(f(*[], **{"b": 9}))   # pxx 91   CPython 91   <- default for `a` preserved
```

So the desugar this ticket proposes designing — `pystar_check_kwnames` plus
per-slot `d.get(name, default)` — is **already implemented**. Writing it again
would be a second mechanism for one concept
(`devdocs/dev/normalise-dont-special-case.md`).

### The actual defect: a leading `**` consumes one star and then parses `*d`

`compiler/parser.inc:15874-15878`:

```pascal
else if isNilPy and (CurTok.Kind = tkStar) and (ProcPyStarIdx[procIdx] < 0) and
        not PyStarIsIterableForm(name) then
begin
  Next;                          { the '*' }
  ParseArgExpr;                  { <-- CurTok is the SECOND '*' of a `**` }
```

`**` is two `tkStar` — the trailing branch twelve lines below says exactly that
(`if CurTok.Kind = tkStar then Next;   { '**' is two tkStar }`) — but the entry
test only checks for one and never looks ahead. So `f(**d)` enters the branch,
eats one star, and `ParseArgExpr` fails on `*d` with "expected expression",
which is the reported symptom and names neither the star nor the callee.

**The fix is to give the leading position the look-ahead the trailing position
already has**: on entry, if the next token is also `tkStar`, consume both, parse
the dict into `fwdDict`, and synthesise an empty list literal for `fwdList` —
i.e. lower `f(**d)` to the `f(*[], **d)` that already works. No new runtime, no
new protocol, no change to `PyStarForwardCall`.

### THIS IS A TRACK A CHANGE — filed, not fixed

`compiler/parser.inc` is shared (A/P). Per CLAUDE.md, Track N files and hands
off; the coordinator session holds the A/P slot. Filed as
[[bug-a-nilpy-leading-double-star-in-a-call-is-not-detected]]. This ticket is
`blocked-by` it and moves to `unfinished/`.

### Three FURTHER gaps this exposed — separate tickets, not part of the above

Fixing the parse only reaches what `f(*[], **d)` reaches today, which is
free functions with ordinary parameters. Measured with the working proxy:

| callee | result today | |
| --- | --- | --- |
| `def f(a=1, b=2)` | **works**, defaults preserved | ✅ |
| `def g(**kw)` | run-time `TypeError: forwarded call got 2 arguments, expected 1 to 1` | ✗ |
| `C.__init__(self, **kw)` | compile error: *"C(*xs) where the constructor itself takes \*args or \*\*kwargs is not supported yet"* | ✗ |
| `C.m(self, a=0, b=0)` | compile error: *"\*unpacking into C.m is not supported — it has parameters with defaults"* | ✗ |

The last two already refuse by name with their own diagnostics, so they are
known gaps rather than discoveries; the `**kwargs` callee failing at RUN TIME
with a misleading arity message is the one worth its own ticket. All three are
independent of the parse defect and none of them should be bundled into it —
the parse fix is small and shippable on its own, and stapling them together is
what would turn a five-line change into a project.

### Method note

The ticket's design section is careful and plausible and was written without
running `f(*[], **d)`. One command would have shown the machinery already
existed. Same failure as `frank2-search-done-before-designing`, one level in:
grep the tree for the capability before designing it, and when a ticket says
"the machinery is nearly all there", check whether it is in fact all there.
