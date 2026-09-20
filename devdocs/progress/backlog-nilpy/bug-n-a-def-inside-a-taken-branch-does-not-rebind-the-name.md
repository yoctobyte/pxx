---
track: N
prio: 65
type: bug
blocked-by: []
summary: "RE-RANKED 45 -> 65 2026-09-20 ON A SECOND OBSERVABLE THAT REFUTES THIS TICKET'S OWN by-design ESCAPE: a conditional def with NO PRIOR DEFINITION is not a rebinding question -- there is nothing to displace -- and it is REFUSED outright, `error: unresolved forward: <name>`. That makes the standard pure-Python fallback `try: from x import f / except ImportError: def f(...)` fail, which is HALF OF PYTHON'S ONLY #ifdef: pxx supports the conditional IMPORT (the owner ruled that idiom by design, 2026-09-20) and not the conditional DEFINITION. It is NOT if-specific -- `if`/`for`/`try`/`finally` all refuse -- and NOT a visibility problem, because a call from INSIDE the same block fails identically. Original observable: `def g(): return 1` followed by `if True: def g(): return 2` still calls the FIRST g. Split out of bug-n-a-module-level-rebinding-still-loses-to-a-def-of-the-same-name when that one was fixed: it is a different mechanism — the def side, not the assignment side. A nested def has a position, but PyRegisterDefShells only walks module-level defs at DEPTH 0, so a def inside a branch never gets one."
---

# A `def` inside a taken branch does not rebind the name

```python
def g():
    return 1
if True:
    def g():
        return 2
print(g())           # CPython 2, pxx 1
```

Measured at `e8b72f8afeb6` (the fixedpoint carrying the module-rebinding fix)
and unchanged by it.

## Why it is a different mechanism from the ticket it was split from

[[bug-n-a-module-level-rebinding-still-loses-to-a-def-of-the-same-name]] was the
**assignment** side of "which binding ran last" having no position. This is the
**def** side, and a def does have `ProcPyDefTok` — so the comparison would work
if the position existed.

It does not, because `PyRegisterDefShells` walks module-level defs at **depth 0**
only, and that restriction is load-bearing rather than incidental: its own
comment says registering unconditionally "is safe HERE and only here" precisely
because the pass visits each module-level def token exactly once. A def inside
an `if` suite is at depth 1, is never visited, and so never gets a shell, a
`ProcPyDefTok`, or a place in the ordering.

## Shape of the fix

The obvious move — walk deeper — has to answer what the depth-0 restriction is
protecting: a def inside a `class` suite is a METHOD and must not become a
module-level name, and a def inside another def is a nested def with its own
machinery. So "depth > 0" is not one case but at least three, and only the
`if` / `try` / `while` / `for` suites are module-level bindings that happen to be
conditional.

Note the asymmetry with the assignment side, which is deliberate and correct
there: `PyDefRebindTok` counts only depth-0 assignments, because a conditional
assignment must NOT displace a def (a `f = ...` under a branch that never runs is
legal CPython, and NilPy is upward compatible). A conditional **def** is the same
shape and would want the same answer — which suggests the honest fix may be that
both sides stay depth-0 and this ticket is closed as "conditional bindings are
not tracked, by design, in both directions". That is a Track U question if the
implementer disagrees rather than something to settle in passing.

## THE SECOND OBSERVABLE, AND IT REFUTES THE by-design ESCAPE ABOVE (frankb-8e, 2026-09-20)

The section above suggests the honest fix may be that both sides stay depth-0
and this closes as *"conditional bindings are not tracked, by design, in both
directions"*. **That reasoning holds only for a REBIND.** Measured at compiler
`a41d8ac34eb9`:

```python
if True:
    def pick():
        return 7
print(pick())          # CPython 7, pxx: error: unresolved forward: pick
```

**There is no prior definition to displace.** The upward-compatibility argument
that makes the assignment side correct — a `f = ...` under a branch that never
runs must not displace a def — has nothing to bite on: this def is the ONLY
definition, CPython makes it, and pxx refuses the program outright. So the
symmetry argument does not reach this case, and the ticket cannot close as
by-design without leaving a refusal behind.

**Not `if`-specific, and not a visibility problem.** Same `unresolved forward`
from `if`, `for`, `try` and `finally` suites — and a call from INSIDE the same
block fails identically, so the def is never registered at all rather than
registered somewhere the call cannot see:

```python
if True:
    def pick():
        return 7
    print(pick())      # error: unresolved forward: pick
```

Consistent with the named mechanism: `PyRegisterDefShells` tests
`(depth = 0) and (Tokens[i].Kind = tkFunction)`, so nothing at depth > 0 is
seen, whether or not a name already exists.

**One row that is NOT a divergence**, pinned so nobody "fixes" it: a `def`
inside `except ValueError:` whose handler never runs fails under CPython too
(`NameError`). Only the rows where CPython succeeds are defects.

### SCOPE ROW: this is MODULE level only — function-local defs ARE registered

Measured 2026-09-20 answering a scan question from tuxspaceprogram-c6, and
recorded here because "a def inside a compound statement" sounds like one
defect and is two:

| a `def` inside `if`/`for`/`try`, at | pxx |
| --- | --- |
| **module** level | REFUSED, `unresolved forward` (this ticket) |
| **function** level, single def | **works** — registered and callable |
| **function** level, two same-named defs in exclusive branches | compiles, **wrong value**, see below |

So the depth-0 walk in `PyRegisterDefShells` is a MODULE-level registrar and
the fix for this ticket must not be described as covering nested functions —
they go through different machinery and already work.

The function-level failure is a separate defect with its own mechanism and its
own ticket: [[bug-n-two-same-named-defs-in-exclusive-branches-of-one-function-collapse-silently]]
(two defs collapse to one, call resolves by position, last wins whatever ran).
**Conditional definition is therefore broken at both scopes by different
mechanisms**, and a fix for either leaves the other. Not merged, because one
ticket claiming both would mis-state at least one.

### Why this re-ranks it: it is half of Python's only `#ifdef`

`try: import X / except ImportError:` is the only conditional-compilation
mechanism Python has, and the owner ruled that idiom **by design** on
2026-09-20. Its direct companion is defining the fallback in the handler:

```python
try:
    from definitely_no_such_module import isqrt
except ImportError:
    def isqrt(n):
        r = 0
        while (r + 1) * (r + 1) <= n:
            r += 1
        return r

print(isqrt(17))       # CPython 4, pxx: error: unresolved forward: isqrt
```

So pxx supports the conditional IMPORT and not the conditional DEFINITION.

**AND IT PASSES EXACTLY WHEN THE FALLBACK IS UNUSED.** Write the same file
guarding on `math` — a module pxx HAS — and it compiles and prints 4, because
the guard resolves, the handler arm is dead, and the `def` in it is skipped
without ever needing a shell. **The idiom therefore works in the case where the
fallback is not taken and fails in the case where it is**, and under pxx the
failing case is the common one, since the reason to write a fallback at all is
a module pxx may lack.

That asymmetry is also why no fixture caught it: an author reaching for this
idiom naturally guards on something present.

**WHAT THE 45 -> 65 DOES NOT REST ON, stated because the obvious ground was
measured ABSENT the same day:** it does **not** rest on unblocking any demo.
Two independent scans, two seats, two codebases — lekkerzeilen and TSP — found
**zero** instances of this idiom at module level, and 7a supplies the
structural reason rather than the count: its only optional dependency is the
BACKEND, chosen by IMPORT rather than by DEFINITION. c6 reports TSP is
stdlib-only by constraint, so there is rarely an optional import to fall back
from at all.

The ranking rests entirely on: **a correct CPython program is refused, and this
ticket's own by-design escape cannot reach that case.** That is a
language-conformance defect ranked as one, with no application borrowing it
credibility — which makes the number more honest, not less. **If a later reader
finds this ticket ranked on a demo, that reader is reading something someone
added; it was not the basis.**

What would change it: real source that writes the module-level fallback idiom.
Neither application does today.

**Provenance:** found while fixing
[[bug-n-a-nested-import-guard-compiles-the-dead-arm]], in a probe aimed at
something else. Filed briefly as a separate ticket and folded here instead.

**And the reason that fold was not housekeeping is worth stating, because it is
a mechanism rather than a preference: WHERE A TICKET CARRIES A PROPOSED
by-design RESOLUTION, A SIBLING FILED ELSEWHERE IS HOW THAT RESOLUTION SURVIVES
ITS OWN COUNTEREXAMPLE.** This ticket argues toward closing as *"conditional
bindings are not tracked, by design, in both directions"*. Had the second
observable landed under its own slug, that argument would have stayed intact
here and this ticket could have been closed on it — by a reader who never saw
the case that defeats it, in a file that gave them no reason to look. A
duplicate does not merely split evidence between two slugs; it can leave the
original closable on reasoning the duplicate refutes. **The counterexample has
to live in the same file as the argument it defeats.**

## Gate

`g()` answers 2, and the `if False:` counterpart still answers 1.

**And the second observable's gate, which the first does not cover:** the
`isqrt` fallback above compiles and prints 4; the top-level-`def` control still
works; the `except ValueError:` row still matches CPython's `NameError` rather
than printing 7.
