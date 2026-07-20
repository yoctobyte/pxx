---
track: U
prio: 70
type: idea
---

# DECIDE: which closure model for NilPy?

Blocks [[feature-nilpy-nested-def-as-value]], which is the uforth blocker (52
inline calls vs ~197 value uses of inner defs). Nested defs already parse, nest,
and read enclosing locals when CALLED in place (5fd3762c, c02d2c98) — that
slice appends the captured values as extra ARGUMENTS at each call site, which
works only because every call is lexically inside the parent. A def that escapes
as a value has no such call site, so the captured state must travel with it.
Three ways to do that, and the choice is not mine to make: they differ in
observable SEMANTICS, not just in cost.

## Option A — closure record, capture by VALUE at definition time

A heap record `{code ptr, captured values}`; `f = inner` copies the current
values. Cheapest, no change to how the parent's locals are stored, and it
composes with the existing call path (call through pointer, captured slots
appended as trailing args).

**Wrong on late binding.** Python reads a closed-over name at CALL time:

```python
fs = []
for i in range(3):
    def g() -> int:
        return i
    fs.append(g)
print([f() for f in fs])     # CPython [2, 2, 2] — every closure sees the LAST i
```

Option A prints `[0, 1, 2]`. That is the famous Python surprise; code in the
wild sometimes RELIES on it (and the `i=i` default-argument idiom exists
precisely to opt out).

## Option B — cells (CPython's model)

A captured local is boxed into a heap cell at parent entry; parent and closure
both go through the cell. Correct late binding, and `nonlocal` writes fall out
for free. Costs: every access to a captured local in the PARENT becomes an
indirection, and the parent's local slots for captured names must be rewritten
at parse time — invasive in a frontend that types locals with a trial-parse
pre-pass, though the pre-pass does mean we know the capture set before laying
out the frame.

## Option C — A now, B later, behind the corpus

Ship A, get uforth running, and revisit if a corpus actually depends on late
binding. Risk: A's answer is SILENTLY different — a wrong number, not an error —
and "revisit later" on a semantics choice is how a dialect quietly diverges.
Mitigation: make the loop case a hard ERROR under A (a def that escapes AND
captures a name assigned in an enclosing loop), so the divergence is loud and
the corpus tells us whether B is needed.

## Recommendation

**C with the error, converging on B.** A alone is a semantics fork we would be
stuck with; B alone is a large change to land before knowing whether uforth even
needs it. C gets the corpus moving while keeping the divergence loud, and every
piece of A's machinery (the closure record, calling through it) is machinery B
needs too — the cell is a change to WHERE the value lives, not to the call path.

What I need from Track U: pick A, B, or C — and if C, confirm the
"escaping capture of a loop-assigned name is an error" rule is acceptable, since
it will reject some real Python that the by-value model would otherwise silently
mis-answer.
