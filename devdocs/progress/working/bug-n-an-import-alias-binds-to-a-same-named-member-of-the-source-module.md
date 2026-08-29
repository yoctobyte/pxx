---
track: N
prio: 85
type: bug
blocked-by: [decide-how-a-compiled-def-carries-its-signature-when-boxed]
summary: "RE-SCOPED: not about import aliases. A name that names a `def` is resolved to that def at EVERY call site and any later rebinding is ignored — `def a…; def b…; b = a; b(1,5)` answers 18 (the original b) where CPython answers 5, with no import anywhere. The alias spelling is one way to rebind. Blocked: the correct destination is the dynamic call path, which cannot yet carry defaults (see the decision ticket)."
status: working
owner: frankA
---

# An import alias binds to a same-named member of the SOURCE module

- **Type:** bug (name binding) — **Track N** (Nil-Python frontend)
- **Found:** 2026-08-18 by frank2-7e while reproducing
  [[bug-n-a-default-argument-is-dropped-on-every-cross-module-call]]; the
  defaults-free row was pointed out by the coordinator and re-measured here.
- **Measured at:** HEAD, self-host fixedpoint build, differential against
  CPython running the same file unmodified.

## Repro — no defaults involved

`mmod.py`:

```python
def f(a, lo=7):        return lo
def g(a, lo=3, hi=13): return lo + hi
class C:
    def m(self, a, lo=7): return lo
```

```python
from mmod import f as g
print(g(1, 5))      # pxx prints 18   -- CPython prints 5
```

**Every argument is supplied.** No default applies. `18` is `5 + 13`, i.e.
`mmod.g(1, 5)` — the alias bound to the module's own `g` instead of to `f`.

| call | pxx | CPython | |
| --- | --- | --- | --- |
| `from mmod import f as g; g(1, 5)` | **18** | 5 | **DIVERGES — no defaults involved** |
| `from mmod import f as g; g(1)` | **16** | 7 | DIVERGES |
| `from mmod import f as zz; zz(1, 5)` | 5 | 5 | ok — fresh alias name |
| `from mmod import f as C; C(1, 5)` | **a C instance** | 5 | **DIVERGES — constructs M's class** |

The last row is the worst shape: aliasing to a name that is a CLASS in the
source module silently **constructs that class** instead of calling `f`.

## Why this is filed separately from the p90 defaults bug

It is **not** a symptom of
[[bug-n-a-default-argument-is-dropped-on-every-cross-module-call]], and the
top row proves it: all arguments supplied, no default path reached, still
wrong. The two were entangled because the alias ticket's original repro
omitted a default, so both defects fired at once and the crash was read as a
dereferenced dropped default. It is really a call landing on a **different
function with a different signature**.

Filed BEFORE the defaults fix lands, deliberately: once that lands the
fresh-name alias row goes correct while the colliding row stays wrong, and a
reader seeing a half-fixed alias ticket at that moment would mis-diagnose it.

This also means the defaults fix will **not** retire
[[bug-n-calling-through-a-function-alias-with-a-default-omitted-segfaults]] —
that ticket's repro uses a colliding alias name, so its crash is this bug.

## What to check when fixing

`from X import a as b` must bind `b` in the IMPORTING module's namespace only,
to whatever `a` names in X. The alias name must never be looked up as a member
of X. Verify by value against CPython for: an alias colliding with a function
in X, with a class in X, with a variable in X, an alias that shadows a name in
the importing module, and two aliases crossing over
(`from X import a as b, b as a`).

## RE-SCOPED AND BLOCKED 2026-08-18 (frank2-7e)

Measured at HEAD `4e823d0d2`, self-host fixedpoint, differential against CPython.

### It is not about import aliases

The same failure appears with no import anywhere — a plain **same-file**
rebinding of one `def` name to another function:

```python
def a(x, lo=7):        return lo
def b(x, lo=3, hi=13): return lo + hi
b = a
print(b(1, 5))        # pxx 18 (the ORIGINAL b) -- CPython 5
```

| shape | pxx | CPython |
| --- | --- | --- |
| `from M import f as g; g(1,5)` | 18 | 5 |
| `from M import f, g` then `g = f; g(1,5)` | 18 | 5 |
| **`def a…; def b…; b = a; b(1,5)`** (no import at all) | **18** | 5 |

So the rule is: **a name that names a `def` is resolved to that `def` at every
call site, and any later rebinding of the name is ignored.** An import alias is
one way to rebind a name; it is not the cause. In Python a `def` binds a name in
a namespace and assignment replaces the binding, which is what makes decorators,
monkey-patching and swap-in test doubles work.

The class row from the original report is the same rule seen through a class:
`from M import f as C` leaves `C` naming M's class, so `C(1,5)` constructs it.

### BLOCKED on the callable-signature decision — measured, not assumed

The correct destination for a rebound name is the **dynamic call path**
(`pyvar_callv<n>`), which is what already makes a fresh alias `zz = f; zz(1,5)`
answer 5 correctly. But that path is exactly the one diagnosed in
[[bug-n-calling-through-a-function-alias-with-a-default-omitted-segfaults]]:

```
from M import f as zz;  zz(1)   ->  empty, exit 0    (CPython 7)
handlers[0](1) / d["x"](1) / fn(1) / bound method   ->  SIGSEGV
```

So routing rebound names through it *today* would fix the all-arguments-supplied
rows and turn the omitted-default rows from a wrong value into **a wrong value or
a crash** — a regression in kind, and precisely the "green test certifying a
hole" shape this campaign has now hit twice.

**Therefore this ticket is blocked on
[[decide-how-a-compiled-def-carries-its-signature-when-boxed]]** (U, p88). Once a
callable value carries its signature, routing a rebound name through the dynamic
path becomes correct and this becomes a tractable frontend change.

### What the fix looks like once unblocked

A pre-pass fact, not a call-site guess: record module-level names that name a
`def` **and** appear as an assignment target anywhere in the module; resolve calls
to those names through the variable rather than to the proc. Names never rebound
keep today's direct call, so the common path costs nothing. NilPy already runs
pre-passes over its own token span (`ParsePyUnit`), which is where the fact
belongs.

Not attempted: it would be built on a dynamic path that cannot yet carry
defaults, and the whole point of the decision above is which representation fixes
that.

### Retitling

The title names the alias shape, which is one instance rather than the rule. Left
to whoever takes it, same convention as the other two tickets re-scoped today.


---

**Unblocked and moved to `backlog/` by the coordinator, 2026-08-28.** Its declared
`blocked-by` names a ticket that has since been resolved, so this was sitting in `blocked/` —
which `ready`/`next` never scan — while it was actually rankable. Nothing about the work
changed; only the record was stale. Found by a sweep (see
`chore-t-nothing-re-checks-a-blocked-by-edge-after-its-blocker-closes`); 14 tickets repo-wide
carry at least one `blocked-by` naming a closed ticket, five of them fully unblocked.

**SUPERSEDED 2026-08-29 — Track N IS being dispatched again.** The paragraph below
was correct when written and is kept so a reader meets it where it was relied on.

> ~~**Track N is NOT being dispatched** (owner deprioritized it and reserved the call, 2026-08-27).
> This ticket is rankable again and correctly filed, but do not auto-claim it on a cold-start
> "take the global top" — ask the owner first.~~

The owner lifted it, 2026-08-29, verbatim: *"track A+C+P+N is highest prio at all
times and the hardest to parallelize. having track A idling is a waste of time and
tokens."* N is named explicitly in the highest-priority set, and the statement is
two days newer than the reservation it replaces. **Claim it normally.**

Recorded by the coordinator rather than left in message traffic: the reservation
was durable prose on master and its lifting has to be too, or the next agent
re-reads the ticket and re-refuses. frankA declined this dispatch on the strength
of the old paragraph and was right to — the paragraph was the only thing on master
that spoke to it.

## MEASURED AT HEAD 2026-08-29 — the 2026-08-18 re-scoping is STALE, the TITLE was right

Re-measured against CPython before touching anything. Two premises above no
longer hold, and both would have sent the next reader the wrong way.

**1. The re-scoping is stale.** The section above says the failure "appears with
no import anywhere" and gives `def a…; def b…; b = a; b(1,5)`. That case
**passes at HEAD** — pxx 5, CPython 5. Locally-`def`'d names now rebind
correctly. So the defect really is the import one the TITLE names, and the
generalisation to "a name that names a `def` is resolved at every call site"
is no longer the rule.

**2. `blocked-by` is satisfied and its stated reason is gone.** The block was
that the dynamic call path "cannot yet carry defaults", evidenced by
`from M import f as zz; zz(1)` printing empty. At HEAD that prints **7**, which
is CPython's answer. The decision ticket is in `decided/` and the measurement
that motivated the block no longer reproduces.

### The table, re-measured, before -> after

| shape | before | after | CPython |
| --- | --- | --- | --- |
| `from M import f as g; g(1,5)` | 18 | **5** | 5 |
| `from M import f as g; g(1)` | 16 | **7** | 7 |
| `from M import f as g, g as f` | `5 5` | **`5 18`** | `5 18` |
| `from M import f as C; C(1,5)` | a C instance | **5** | 5 |
| `from M import f as zz; zz(1,5)` | 5 | 5 | 5 |
| `from M import f, g` (plain) | 5, 18 | 5, 18 | 5, 18 |
| **`from M import f, g; g = f; g(1,5)`** | 18 | **18** | 5 |

Three defects, not one — which is why the first fix could not close it:

- **the call site** preferred an imported proc over a module-level binding;
- **the import parser** resolved an alias's SOURCE name with a flat lookup, so
  `g as f` found the `g` that `f as g` had allocated an instant earlier
  (CPython binds every name of one from-import from the source module
  simultaneously);
- **the constructor path** is a SECOND mechanism for one concept —
  `PyIsExactCtorName` decides `Name(` is a construction without consulting any
  binding, so `f as C` constructed M's class. Fixing the call site alone leaves
  this one live, and it looks fixed from the ticket's first row.

### STILL OPEN — one row, and it is not dropped

`from M import f, g` then `g = f` still answers 18. Catching it needs a
module-level assignment scan keyed by NAME, which is `PyDefRebindTok`'s job in
`compiler/symtab.inc` — **Track A's file, held by another agent**, so it was not
taken. Filed here rather than silently omitted: the table is the only record
anyone rereads, and a row removed from it reads as passing.

### A regression I caused, and the reason it is recorded here

The first fix (`15335c82c`) broke `test_nilpy_fallback_import_try_wins` and was
repaired in `46b2439c4`. The rule was "a module-level var declared in this unit
beats a proc from another unit" — true for a **rebinding**, false for a **plain
import**, because an optional (`try:`) import allocates a module-level var for
the plain spelling too, so a real import binding was shadowed by None.

**Every one of this ticket's seven rows still passed. The eighth shape, the one
not in the table, is what broke.** That is a scope error, not a reasoning error,
and the table looked complete — which is the same failure as reading a sample as
a census. An enumeration treated as exhaustive and a sample treated as a census
are one defect wearing two hats: *the instrument's scope is invisible in its own
output, and the scope is exactly where the next defect lives.*

The practical consequence for whoever takes the remaining row: **the table above
is not the specification.** Before landing a change to name binding, check at
least one shape that is not in it — an optional import, a conditional import, a
name bound by both a def and an import.

## WARNING for the remaining 2 shapes: the first 5 broke fallback-import, and it is not obvious why

`15335c82c` fixed 5 of the 7 divergent shapes here and, in doing so, regressed
`test_nilpy_fallback_import` and `test_nilpy_fallback_import_try_wins`. Bisected
on host `seven` 2026-08-29, self-hosted compiler rebuilt at each sha (`converged
after 2 round(s)` throughout), running the recipe's own `-Futest/nilpy_units`:

| sha | result |
| --- | --- |
| `7b8f0afc5` (parent) | `hello fallback` / `hello try branch` |
| **`15335c82c`** | `TypeError: object is not callable — the name is None` |
| `2d65e9c45` (HEAD, after the follow-up fix) | `hello fallback` / `hello try branch` — **repaired** |

Both regressions are closed; this note is not about them. It is about the
**sixth shape**, which the precedence rule has now demonstrably reached once:

`try: import X / except ImportError:` selects its branch at **compile** time
(`Makefile:1127`). So the except branch's module-level assignment and the
imported name **share a spelling by construction** — that is what the feature
IS (`done/feature-nilpy-fallback-import`). Any rule deciding "module-level
binding vs imported name of the same name" therefore governs fallback-import
whether or not it was written with that case in mind, and the failure it
produces is silent: the name binds to `None` and the program dies later at the
call site, naming neither the import nor the rule.

**Before finishing shapes 6 and 7, run those two tests with
`-Futest/nilpy_units`.** They are the cheapest available oracle for this rule's
blast radius, they are not in the quick tier, and a bare invocation without that
flag reports a *different* failure (`import: no unit named pkgprobe_sub`) that
looks like an unrelated resolution bug — which is how it first got mis-recorded.

Recorded by the Track T agent on `seven` under the provenance rule: my box's
sweep produced the regression, so the narrowing is mine to leave behind. The
rule itself is Track N's.
