---
track: N
prio: 45
type: bug
blocked-by: []
summary: "`self.a = self.b = n` -- a chained assignment whose targets are ATTRIBUTES -- does not parse: `expected newline after statement`. RE-MEASURED 2026-09-10 and the 09-09 cause section below is STALE: it says the chain is \"plain NAME targets only\" and refuses `d[k] = d2[k2] = f()`, and that shape compiles, runs, and calls f exactly once. The real cause is the GUARD at pyparser.inc:28123, which admits the chain arm only for a literal `IDENT = IDENT =` token run -- so there is ONE chain implementation, it handles bare names, and every other shape falls through to the ordinary assignment path and is read as the NESTED `X = (Y = v)`. That reading is why subscript rows pass and attribute-after-first rows do not. AND IT CARRIES A SILENT DIVERGENCE NOTHING HAD REPORTED, which outranks the filed symptom: the nested reading stores RIGHT TO LEFT where CPython stores LEFT TO RIGHT. `l[idx(1)] = m[idx(2)] = 7` gives store order [2,1] against CPython's [1,2] while both print `7 7` -- the values agree and only the target subexpressions' side effects differ, so no value assertion can see it. A fix that clears the parse error without removing the nesting closes this ticket and leaves the silent half in place, so the ORDER probe must ship as a test alongside the parse repro."
status: working
owner: frankB
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

---

## RE-MEASURED 2026-09-10 (frankB) — the 09-09 cause is STALE, and there is a
## SILENT divergence underneath it that nothing had reported

The section above says the chain is *"PLAIN NAME targets only"* and that
`d[k] = d2[k2] = f()` is *"refused by name below"*. **Both are false at the tip.**
That shape compiles, runs, and calls `f` exactly once. So the write-up would
have sent an implementer looking for a refusal that is not there.

### The census that replaces it

Measured at the tip against the compiler on disk, one probe per cell:

| chain shape | outcome |
| --- | --- |
| `a = b = 3`, `a = b = c = 5` | OK |
| `l[0] = m[0] = 7` | OK |
| `a = l[0] = 7` | OK |
| `self.a = l[0] = 7` | OK |
| `self.a = self.b = n` | parse error |
| `a = self.b = n` | parse error |
| `l[0] = self.a = 7` | parse error |
| `self.a = b = 7` | `undefined variable (b)` |

The reported bug is the fifth row. The shape of the table is the finding: an
attribute is refused **in any position after the first**, and accepted first.

### One cause, and it is the GUARD, not the store lowering

`pyparser.inc:28123` admits the chain arm only for a literal
`IDENT = IDENT =` token run. Nothing else reaches it. So **there is exactly one
chain implementation and it handles bare names**; every other shape falls
through to the ordinary single-assignment path and is read as the NESTED
`X = (Y = v)`.

That reading is why some rows pass. A subscript or attribute store has an
expression form that yields its value, so the nesting happens to produce the
right values. A bare name has no such form, which is precisely the
`undefined variable (b)` this ticket's own history records being fixed for
`a = b = RHS` — it was never fixed for `self.a = b = RHS`, because that shape
never reaches the fix.

### The part nothing had reported, and it is worse than the parse error

**The nested reading stores RIGHT TO LEFT. CPython stores LEFT TO RIGHT.**

```python
order = []
def idx(tag):
    order.append(tag)
    return 0
l = [0, 0]; m = [0, 0]
l[idx(1)] = m[idx(2)] = 7
print(order)
```

| | |
| --- | --- |
| CPython | `[1, 2]` |
| pxx | `[2, 1]` |

Both print `7 7`. **The values agree and only the target subexpressions' side
effects differ**, so no value assertion can see it — which is why a row that
"works" has been working wrongly. `l[0] = m[0] = f()` calling `f` once is real
and was verified; single-evaluation was never the problem.

This outranks the filed symptom: a parse error is loud and this is not.

### What the fix has to be, and the earlier note was right for the wrong reason

The 09-09 entry concluded "one lvalue path, not a fourth arm on the chain", from
the premise that subscript targets are refused. The premise is stale and **the
conclusion survives it** — for a better reason. The chain arm must accept any
lvalue target and store to each left to right, which means re-entering the
store dispatch per target rather than matching a token shape. Capturing each
target's TOKEN SPAN and replaying it as a store against the hidden temp is the
tractable form; `TokPos` is already rewound that way elsewhere in this file.

Any fix must carry the ORDER probe above as a test, not only the parse repro.
Fixing the parse error while leaving the nesting in place would close this
ticket and leave the silent half exactly where it is.

### Scope note

`self.a = b = 7` also reaches the field-inference pre-pass
(`cannot infer the type of field self.a` when `b` is a known local), which is
[[refactor-n-the-field-type-pre-pass-asks-one-question-in-six-places]]'s
territory and is a second, independent wall behind this one. Not bundled.
