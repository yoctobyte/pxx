---
track: N
prio: 70
type: bug
blocked-by: []
commit: PENDING-COMMIT
claimed-by: frankonpiler-an
summary: "A variable holding a callable (a bound method, a lambda) loses to a module-level `def` of the same name: the call silently runs the WRONG function. Top wall of the third-party ladder — one root cause behind 12 of the 38 remaining failures."
status: unfinished
---

## 2026-08-19 — a duplicate folded in here, plus one disconfirmation worth keeping

Added by frank3-etree (Track B). **Not an edit to the diagnosis — frank2 owns
this ticket and reproduced the corpus diagnostic; this only carries in evidence
from a duplicate so it is not lost.**

[[bug-n-a-user-classs-decode-method-is-hijacked-losing-its-own-parameters]] was
filed separately against this same 12-file wall, as a `decode` **method-name
hijack** (a fourth sibling of the fixed `keys`/`items`/`values` dict-view bug).
It is now in `rejected/` as a duplicate of this ticket. The measurement that
killed that premise, in case it is ever proposed again:

- **20 builtin method names** — `decode encode keys items values append count
  index split join strip upper lower read write close get pop update copy` —
  declared on a user class and called with a keyword argument, through **both** a
  direct receiver and an untyped parameter: **all 20 dispatch correctly** on
  pinned v357. Nothing about the *name* `decode` is involved.
- `lib/rtl/mimic_codecs.pas` **does** exist and **is** bound (the compile prints
  `note: codecs -> mimic_codecs (shim, subset)`), so "nothing of ours supplies a
  competing signature" was not a safe assumption.

**And a separate real bug came out of it, which should not be closed with this
one:** [[bug-n-a-keyword-argument-through-a-callable-value-is-undefined]] —
`d = obj.meth; d("x", flag=True)` gives `undefined variable (flag)` with **no
name collision anywhere**. Different diagnostic, different cause. The two were
conflated for most of a day; what separated them was that the minimal repro
produced a different message from the corpus, and a different diagnostic means a
neighbour rather than the thing.

# A callable in a variable loses to a `def` of the same name

```python
def f(x):
    return "MOD"

class D:
    def f(self, x):
        return "METH"

def go(o):
    f = o.f          # rebind the name to a bound method
    return f("q")

print(go(D()))       # CPython: METH      pxx: MOD
```

**Silent.** No warning, no error — the wrong function runs and returns a
plausible value. It only becomes loud when the two arities disagree, which is
how it was found:

```
Nil Python: decode has no parameter named 'final'
```

## Why this is the top lever

Measured 2026-08-19 on the third-party ladder (`tools/nilpy_ladder.py`),
compiler binary `2b2374c38f2c7407…` self-hosted at `594bd3c8c`:

```
12  Nil Python: decode has no parameter named 'final'   <-- this bug
 4  missing module: xml_etree_elementtree
 3  Nil Python: unknown base class Mapping
 3  undefined variable (property)
 ...all remaining rows are 2 or 1
```

Twelve files, one root cause, and the next row is a third its size. Every one
of the 12 is blocked transitively by ONE occurrence — `webencodings/__init__.py`
line 219, inside `iter_decode`:

```python
def decode(input, fallback_encoding, errors='replace'):   # module level
    ...
def iter_decode(input, fallback_encoding, errors='replace'):
    decode = decoder.decode                                # <-- local rebinding
    ...
    output = decode(b'', final=True)                       # -> resolves to the MODULE def
```

The module-level `decode` has no `final` parameter, hence the message. Because
`webencodings` is imported by all of tinycss2 and much of html5lib, that single
line is the whole 12.

## The boundary (measured, not reasoned)

| shape | pxx | cpython |
| --- | --- | --- |
| local `f = o.f` shadowing module `def f` | `MOD` | `METH` |
| local `f = lambda x: ...` shadowing module `def f` | `MOD` | `LOCAL` |
| same, local renamed to `g` | `METH` | `METH` |
| module-level `f = o.f` after `def f` | `MOD` | `METH` |

So: **not** about bound methods (a lambda does it too), **not** about function
scope (module level does it too). It is purely the name collision. Rename either
side and it is correct.

## Root cause statement

In CPython a `def` is not a separate namespace — it is a name binding like any
other, and the last binding wins. NilPy resolves a bare-name call against
declared procedures FIRST and only falls back to variables, so a `def` outranks
every later rebinding of that name. This is the `normalise-dont-special-case`
shape: one concept (a name that denotes something callable) served by two
mechanisms, and the second one is the one that stays broken.

Related but distinct — both are the same family, neither is this:
[[bug-implicit-self-method-loses-to-unit-proc]] (a method losing to a unit proc,
Track A/Pascal) and [[bug-nilpy-a-nested-def-shadowed-by-an-outer-name-binds-to-None]]
(the def's VALUE going missing rather than the call misrouting).

## Gate

`make compiler/pascal26` + the probes above diffed against CPython +
`tools/gate.sh quick`.


---

## PARKED 2026-08-19 — diagnosis is complete, the fix is a mechanism not a patch

Root cause is fully located; no code was changed. Parking because the fix lands
in the single most precedence-dense site in the compiler, and the site itself
records that this exact class of change has already broken things a quick gate
does not catch. Banking so the next session starts here rather than at the ladder.

### Where it is decided

`compiler/parser.inc:13879-13960`, the bare-ident arm of `ParseFactorCore`:

```pascal
idx := FindSym(name);
if NilPyUserCode then procIdx := FindProcNilPyBound(name)
else procIdx := FindProcBound(name);
```

Both are resolved, and the ~80 lines that follow are a stack of precedence
rules, each citing the ticket that bought it (own-field-beats-unit-name, user
class beats pylib routine, case-exact class match, the late-`def` unbind...).
The one rule that is MISSING is "a variable binding beats a `def` of the same
name". Nothing there consults `idx` when deciding that a following `(` means a
call to `procIdx`.

### The warning that says this is not a patch

In `symtab.inc` above `MatchElig`, about the mirror-image change:

> Ranking inside FindProc's chain was tried and broke two things that
> `gate.sh quick` did not catch — the compiler's own self-compile (the parser
> reads the returned proc's SIGNATURE to decide whether `[...]` is an
> open-array constructor or a set) and the NilPy stdlib (`pyparser.inc` infers
> expression types from the returned proc's RetType, and `sum(range(i))`
> segfaulted far from the cause).

So: do NOT fix this by re-ranking `FindProc`. `FindProc` returns an overload-set
representative that callers read TYPES off; it is not a "what does this call
bind to" query. The change belongs at the decision site, gated on
`NilPyUserCode`, leaving Pascal untouched.

### The rule to implement, and why it is statically decidable

Measured against CPython:

```python
def f(x): return "MOD"
def go():
    print(f("early"))       # CPython: UnboundLocalError
    f = lambda x: "LOCAL"
    return f("late")
```

CPython's rule is **a name assigned anywhere in a function body is local for
the entire body** — which is what makes this decidable at compile time rather
than requiring flow analysis. So inside a def: if `name` is assigned anywhere in
this def, every call to `name` in it goes through the local, regardless of a
module-level `def name`. At module level the rule is positional, and
`PyDefBoundHere` / `ProcPyDefTok` already implement exactly that kind of
"is the binding in effect at this TokPos" test for the late-`def` case — that
is the model to copy.

pxx currently prints `MOD` for both lines. Note the first line is NilPy being
LAXER than CPython (we accept what CPython raises on), which per the track rules
is a feature, not a defect — reproducing `UnboundLocalError` is explicitly NOT
required. Only the second line must change.

### The consumer side already exists

No new lowering is needed. A callable held in a variant already has a call path:
`pyvar_callable_ptr` (pyparser.inc:23350) yields the payload, `PyStarDynCall`
(11894) handles `fn(*args)` through a value, and `PyWrapBoundDynCall` handles the
bound-method case. The work is entirely in routing the name to them.

### Suggested shape

At the decision site, when `NilPyUserCode and (qUnit < 0) and (procIdx >= 0) and
(idx >= 0)` and the symbol is a local/param/global variable of variant type and
the next token is `(`: clear `procIdx` and let the existing value-call path take
it. Then grep for the sibling arms — `normalise-dont-special-case` applies, and
the same collision must be checked on the statement path in `ParseStatementAST`
(the ticket for the own-field rule notes the expression and statement halves are
separate sites, so a fix to one arm alone will leave the other broken).

### Gate when resumed

`make compiler/pascal26` + the four probes above diffed against CPython +
`gate.sh quick`, and then the ladder — this is worth **12 of the 38** remaining
corpus failures, so `tools/nilpy_ladder.py` should move materially. Because the
site is shared with Pascal, a self-host fixedpoint is not optional and the FPC
seed canary must be watched.
