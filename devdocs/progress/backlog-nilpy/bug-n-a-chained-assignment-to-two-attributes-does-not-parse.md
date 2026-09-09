---
track: N
prio: 45
type: bug
blocked-by: []
summary: "`self.a = self.b = n` -- a chained assignment whose targets are ATTRIBUTES -- does not parse: `expected newline after statement`, pointing at the second `=`. The module-level form `a = b = 3` parses and runs correctly, so the chain itself is understood; it is the attribute target that is not. Reproduces on the pin and at the tip. lekkerzeilen chart.py:184 (`self.width = self.height = max(1, int(pixels))`). Found once the field-inference blocker ahead of it was fixed, which is what made the line reachable."
status: backlog
owner: —
---

# A chained assignment to two attributes does not parse

## The repro

```python
class C:
    def __init__(self, n):
        self.a = self.b = n     # pascal26:3: expected newline after statement

c = C(4)
print(c.a)                      # CPython: 4
print(c.b)                      # CPython: 4
```

```
near: . width = self . height >>> = max (
```

## The control that says where the gap is

```python
a = b = 3
print(a)      # 3
print(b)      # 3
```

That compiles and prints `3 3`, on the pin and at the tip. So the chain is
parsed at module level and the statement parser knows the shape; the failure
is specific to a target that is an attribute reference rather than a name.

## Why it surfaced now

It sits at `chart.py:184`, behind `self.x0, self.z0 = cx - half, cz - half` at
:191 -- and the field-inference pre-pass runs BEFORE the statement parser, so
:191 was reported first and :184 was never reached. Fixing the pre-pass gap
(bug-n-a-field-assigned-from-a-bare-local-has-no-inferable-type) unmasked it.
The two are independent; neither is a cause of the other.

---

## Cause, measured 2026-09-09 — it is a STORE-PATH problem, not a chain problem

The chain itself is implemented and correct: `pyparser.inc` builds a hidden
temp, assigns the right-hand side to it ONCE, and stores it to each target left
to right — which is why `a = b = f()` calls `f` once, as CPython does. Its own
comment says what it covers and why:

> *"PLAIN NAME targets only. `d[k] = d2[k2] = f()` has targets with side effects
> of their own and is refused by name below rather than guessed at — the temp
> would be right for it too, but the STORE path for a subscript target is a
> different lowering and quietly getting it half-right is the failure mode this
> frontend is trying to avoid."*

An attribute target is the third such lowering, and there is not one of it:
`obj.x = ...` is reached from an expression-suffix parser with **three** store
arms — a declared field, an undeclared dynamic attribute (`PyMakeDynAttrSet`),
and a class-attribute override slot — chosen by what the receiver's class
declares. So the chain cannot simply "also accept `self.a`": it would have to
re-enter that dispatch per target.

**The fix is therefore one lvalue path, not a fourth arm on the chain** — the
NilPy analogue of `refactor-p-one-lvalue-path-for-statements-and-expressions`,
which is closed on the Pascal side. Filed alongside
`refactor-n-the-field-type-pre-pass-asks-one-question-in-six-places`: same rule
(`devdocs/dev/normalise-dont-special-case.md`), same evening, different
subsystem, and in both the path nobody extended is the one that stayed broken.

Deliberately NOT bundled into the inference-reader work: that commit changes
which TYPE a field is given and this one would change how a STORE is emitted.
