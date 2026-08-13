---
summary: "nilpy: *args / **kwargs in a def signature"
type: feature
track: N
prio: 50
owner: claude-A-N
---

# nilpy: `*args` / `**kwargs` parameters

- **Type:** feature (Nil-Python frontend) — **Track N**
- **Status:** done
- **Opened:** 2026-07-26 — probing songformatter under nilpy
  ([[feature-demo-songformatter-pxx-target]]).

## Repro

```python
def f(a, b=2, *args, **kw):
    return a + b + len(args) + len(kw)
```
-> `error: Nil Python: expected parameter name near: a b *args`

Keyword arguments at the CALL site already work (`f(1, b=5)` returns 6), and
`print(..., sep=)`-style kwargs are handled ([[feature-nilpy-print-kwargs]], done)
— this is the callee side.

## Why it matters

songformatter's settings helpers forward through `getF(*args, **kwargs)` /
`getI(*args, **kwargs)` to `get()`, which is the standard thin-wrapper idiom. A
GUI façade over `tk.pas` will want it too: tkinter's whole API is kwargs.

## Shape

`*args` as a tuple/list parameter, `**kwargs` as a dict; forwarding a
`*args`/`**kwargs` on to another call is the case songformatter actually needs, so
the unpacking side at the call site belongs here as well.

## Gate

`make test-nilpy` green with a `.npy` case covering collection AND forwarding,
diffed against CPython, + `--tier quick` + self-host byte-identical.

## Update (2026-07-26) — this is what blocks the tkinter façade, measured

The façade in [[feature-nilpy-tkinter-facade]] cannot be written without it, and the
reason is sharper than "tkinter uses kwargs". Two measurements:

1. **Keyword arguments must fill a contiguous PREFIX of the parameters.** Skipping
   an optional fails:

```python
class W:
    def __init__(self, master: str, width: int = 0, text: str = "") -> None: ...
W("root", width=7, text="hi")     # works
W("root", text="skipped-width")   # error: W() needs a value for every field
                                  #        before the last one given
```

   So a façade CANNOT just declare the ~40 tkinter option names as optional
   parameters and let callers pick a few — which was the obvious way to avoid
   needing `**kwargs` at all. Every real call skips most options
   (`tk.Canvas(self, highlightthickness=0)`, `tk.Label(self.content, text=k,
   anchor="e")`).

2. `__init__` must be annotated `-> None` or the class is rejected. Unrelated to
   kwargs, and a fine rule, but worth knowing when writing shim classes.

Fixing the prefix restriction alone (bind keyword arguments by NAME, leaving
unmentioned optionals at their defaults) would unblock a declared-parameter façade
without needing `**kwargs` at all, and is a smaller change. Real `**kwargs` is
still wanted for forwarding wrappers (songformatter's `getF(*args, **kwargs)`), but
the tkinter path only needs by-name binding.

Recommended split: (a) keyword arguments bind by name, any subset — small, unblocks
the façade; (b) `*args`/`**kwargs` collection and forwarding — the original scope.

## Update (2026-07-26, later) — now blocks TWO modules, and splits into three rungs

After the field-inference and method-default fixes, `convertrawtext.py` cleared its
whole 1600-line FormatText class and stops at line 59; `settings.py` stops at line
102. Both on this. It is the single highest-value item left on
[[feature-demo-songformatter-pxx-target]] because it is the only one that pays off
twice.

The two real use sites need DIFFERENT machinery, and the difference is the whole
design question:

```python
def debug(*args):            # convertrawtext.py:59
    ...
    print(*args)             # unpack into PRINT

def getF(*args, **kwargs):   # settings.py:102
    return float(get(*args, **kwargs))   # forward into FIXED parameters
```

**Rung 1 — collection (easy).** `*args` is one TPyList parameter; each call site
collects its surplus positional arguments into a list literal, which is machinery
that already exists (PyMakeTupleFrom does exactly this shape). `**kwargs` is one
TPyDict built the same way from the keyword arguments.

**Rung 2 — `print(*args)` (easy, special case).** print already takes a variable
argument list; unpacking a TPyList into it means printing the elements
space-separated, which the print path can do directly without a general mechanism.
That alone unblocks convertrawtext.py.

**Rung 3 — forwarding into FIXED parameters (the hard one).** `get(*args,
**kwargs)` where `get(section, option, default=None)` has ordinary parameters
requires binding a RUNTIME-length list and dict onto a compile-time parameter list.
There is no static answer: the arity is only known at run time. Options, in
increasing cost — (a) accept it only when the callee ALSO takes `*args/**kwargs`,
i.e. pass the containers straight through, which does NOT cover settings.py;
(b) emit a small dispatch that switches on `len(args)` and calls the fixed-arity
callee for each supported count, which does cover it and is bounded by the callee's
parameter count; (c) a general dynamic-call path, which overlaps
[[feature-lib-pyexec]].

Option (b) is the pragmatic one: `getF(*args, **kwargs)` becomes a switch over the
argument count against `get`'s 2-or-3 parameters. Worth writing down that it is a
DESUGARING, not a runtime feature, so it fails loudly when the callee's arity is
unknown rather than guessing.

## Rungs 1 and 2 LANDED (2026-07-27)

`test/test_nilpy_star_args.npy`, every expectation diffed against CPython's own
output for the same file.

**Rung 1 — collection.** `*args` is one TPyList parameter, `**kwargs` one TPyDict,
so the body indexes, slices, iterates and `len()`s them with the machinery lists
and dicts already have. The call site packs: surplus positional arguments become
`append` calls on a hidden list temp, keyword arguments that match no declared
parameter become `setitem` on a hidden dict temp, and both containers are ALWAYS
passed (empty when nothing was collected), which is what keeps the callee's arity
fixed. Pieces: `PyHdrStarIdx`/`PyHdrKwIdx` in the one header grammar,
`ProcPyStarIdx`/`ProcPyKwIdx` per proc, `PyPackStarArgs` run just before
`PyBindKwArgs` at the two function-call sites. An unmatched keyword name is
carried from `PyKwArgIndex` to the packer as a NEGATIVE `ASTIVal` encoding the key
literal's node index, because the key must survive until the whole list is parsed.

**Rung 2 — `print(*args)`.** pylib's `pyprint_star(list, leadSep)` renders the
unpacked run as one string, separators included. The separator lives in the helper
rather than being injected at the call site so that `print("a", *[])` prints `a`
and not `a ` — an empty list must contribute no space. A positional argument AFTER
a starred one is REFUSED, not approximated: whether a separator belongs between
them is a run-time fact, and printing a stray one is silently wrong output.

**Not covered, deliberately:**
- **Rung 3 (forwarding into fixed parameters)** — unchanged, still the open scope.
  `getF(*args, **kwargs)` in settings.py still needs the arity dispatch.
- **METHOD parameters.** Method headers do not go through `PyParseDefHeader` (they
  have their own parse in `PyRegisterClassMembers`/`PyParseMethod`), so `def
  m(self, *args)` is still refused. The tkinter façade wants it; it is a separate,
  mechanical extension.
- **Call-site unpacking into a non-star callee** (`f(*xs)` where `f` has ordinary
  parameters) — that IS rung 3.

**Walls moved.** `convertrawtext.py` cleared `def debug(*args)` + `print(*args)`
and now stops at `import tempfile` (line 64). `settings.py` cleared `getF`/`getI`
and now stops at `import tkinter as tk` (line 2, the module body — the def-shell
pre-pass used to fail before the body was ever reached), i.e. `import X as Y`
aliasing is its next wall, ahead of the façade itself.

## Measured satisfied 2026-08-09 (by Track B, pinned v252)

```python
def f(*args):      -> f(1,2,3) == 3
def f(**kw):       -> f(a=1,b=2) == 2, and kw["x"] reads by name
def f(a, *rest):   -> f(1,2,3) == "1:2"    (mixed positional + *args)
```
All accepted and correct. Evidence only — Track N owns closing this. Found
sweeping Track B's blocked tickets; [[feature-nilpy-tkinter-facade]] listed this
as its blocker.

## Re-measured 2026-08-10 at HEAD (b17cf2621) — three of the four open items are CLOSED

Probed against CPython rather than read from the notes above. Scope left is much
smaller than this ticket claims:

| shape | this ticket says | measured at HEAD |
| --- | --- | --- |
| `def f(*args)` / `def f(**kw)` / `def f(a, *rest)` | satisfied (v252) | still correct |
| `def m(self, *args)` in a class | "still refused" | **works** — `c.m(1,2,3)` == 3 |
| `fixed(*xs)` into ordinary params (rung 3) | "still the open scope" | **works** — `fixed(*[1,2,3])` == 6 |
| `target(*args, **kwargs)` forwarding | rung 3 | **positional half works** (`fwd(1,2,3)` == 123) |
| `target(*args, **kwargs)` with a KEYWORD arg | rung 3 | **the only remaining gap** |

The one live failure:

```python
def target(a, b, c): return a*100 + b*10 + c
def fwd(*args, **kwargs): return target(*args, **kwargs)
fwd(1, 2, 3)      # 123 — correct
fwd(1, 2, c=9)    # CPython 129; pxx: TypeError: forwarded call got 2 arguments, expected 3 to 3
```

So `**kwargs` is collected correctly at the callee but **not re-expanded into
named parameters at a forwarded call site** — the keywords are dropped and only
the positional count is passed on. Note this fails LOUDLY (a runtime TypeError,
not a wrong answer), which is the right failure mode and part of why the
priority need not rise.

Retitle-worthy: the remaining work is "`**kwargs` re-expansion at a forwarded
call site", not "star-args/kwargs".

## DONE 2026-08-13 — the last live failure closed

`fwd(1, 2, c=9)` answers 129. The 2026-08-10 re-measurement had narrowed this
ticket to exactly one row — `**kwargs` re-expansion at a forwarded call site —
and that row is now correct in every shape swept: keywords filling the tail,
mixed positional-and-keyword, all-keyword, a callee with DEFAULTS, and string
parameters.

### What made it more than plumbing

The forwarding is a DESUGARING, not a runtime feature: the argument count is
only known at run time, so it was a dispatch on `len(args)` over the arities the
callee accepts. **Keywords break that shape at the root** — with keywords the
argument COUNT no longer says WHICH parameters are filled. `dflt(1, c=9)` with
`def dflt(a, b=5, c=6)` supplies two arguments and fills a and c, skipping b; a
count-dispatch calls `dflt(a, b)` and puts 9 in b. That row is in the test for
that reason, and it is the one that fails under any count-based scheme.

So when a kwargs dict is forwarded there is no dispatch at all: the widest
arity is built once and every slot asks `pystar_has(args, kwargs, k, '<name>')`
— supplied positionally at k, or present by name? — falling back to
`DefaultArgValueNode` when it was not. The parameter NAMES are the thing the
frontend has and the runtime does not, so they travel as literals.

The arity guard counts both halves (`pystar_check_arity_kw`), and
`pystar_no_kwargs` — the refusal this ticket was about — is gone from this path.

### A keyword the callee does not declare

Raises, and the reasoning is worth keeping: the slot reads are EAGER (every
slot the widest arity could use is read before any arm is chosen), so a slot
past the supplied count is a defaulted parameter and must answer None rather
than raise. Within the supplied count it is a real error — that many arguments
arrived and this parameter got none of them, so one of the keywords went
nowhere. That is CPython's "unexpected keyword argument", caught at the only
point it is detectable here.

### Left open, and now the only rung above this

Forwarding into a callee that ITSELF takes `*args`/`**kwargs` —
`def outer(*a, **k): return fwd(*a, **k)` — does not parse (`expected
expression`). Recorded in the test's header; it is a separate shape (the callee
has no fixed parameter list to bind against at all) and nothing measured here
depends on it.

Test `test/test_nilpy_kwargs_forwarded.{npy,expected}` (`.expected` from
CPython), wired into `test-nilpy`; the four existing star/kwargs tests re-run
unchanged. Gate: self-host fixedpoint + `gate.sh quick` GREEN.

## Log
- 2026-08-13 — resolved, commit 3b7aae09c.
