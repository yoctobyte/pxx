---
track: N
prio: 85
type: bug
blocked-by: [decide-how-a-compiled-def-carries-its-signature-when-boxed]
summary: "RE-SCOPED: not about import aliases. A name that names a `def` is resolved to that def at EVERY call site and any later rebinding is ignored — `def a…; def b…; b = a; b(1,5)` answers 18 (the original b) where CPython answers 5, with no import anywhere. The alias spelling is one way to rebind. Blocked: the correct destination is the dynamic call path, which cannot yet carry defaults (see the decision ticket)."
status: blocked
owner: unassigned
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
