---
track: U
prio: 40
type: decision
---

# decide: should NilPy's `and` / `or` return an OPERAND, as Python does?

Characterised 2026-07-20.

```python
a = 5
b = 0
print(a and b)     # CPython 0      pxx False
print(a or b)      # CPython 5      pxx True
```

Python's `and`/`or` are not boolean operators — they return one of the
OPERANDS. NilPy returns a Boolean.

## Why this is a decision and not a bug

Truthiness is preserved, so every CONDITION context agrees: `if a and b:`,
`while x or y:`, and the boolean-valued uses are all correct today. Every one
of uforth's `and`/`or` uses is a condition, so the corpus is unaffected.

What differs is the VALUE, which matters only for the idiom
`x = a or default` — and that idiom needs a common type for both operands,
which a statically-typed dialect does not have in general. `5 or "text"` has
no NilPy type.

## The fork

1. **Leave it.** Document that NilPy's `and`/`or` are boolean operators.
   Cheap, honest, and diverges from Python in a way that is invisible in
   conditions.
2. **Return the operand when both sides share a type**, boolean otherwise.
   Covers `x = a or 0` and `name = given or "anon"`, still rejects the
   mixed-type case. More machinery, partial fidelity.
3. **Return a variant** so any operand pair works. Full fidelity, but it
   makes every `and`/`or` a variant-producing expression, which drags in the
   variant-as-scalar problem
   ([[bug-a-nilpy-variant-element-not-usable-as-scalar]]) for a construct
   that is overwhelmingly used in conditions.

## Recommendation (superseded — see Decision)

**1, with a note in the docs.** The value form is absent from the corpus, the
cost of 2 is real, and 3 makes the common case worse to serve the rare one.
Worth revisiting only if a corpus actually uses `x = a or default`.

## DECIDED 2026-07-20: option 3, refined — return the OPERAND

This is a core Python language feature, not a corner: `x = a or "default"` is
everyday idiom, and silently returning a Boolean would break it for every user
who writes normal Python. We mimic official behaviour.

The cost that made option 3 look expensive largely evaporates once you split on
**how the result is consumed**, not on the operand types:

- **Condition context** (`if a and b:`, `while x or y:`, `not (a or b)`) — the
  value is discarded; only truthiness is used. Pure control flow: no result
  temp, no variant, *regardless of operand types*. This is the overwhelming
  majority of real uses and covers 100% of the uforth corpus, so the
  variant-as-scalar problem ([[bug-a-nilpy-variant-element-not-usable-as-scalar]])
  is never reached by the common case.
- **Value context**, both sides same static type `T` → result is `T`. No
  variant. Covers `x = a or 0`, `name = given or "anon"`.
- **Value context**, mixed but variant-promotable → variant.
- **Not variant-promotable** (records, classes, dynamic arrays) → reject at
  compile time with a clear diagnostic. This is already NilPy's documented
  posture for incompatible variant assignments; no new policy needed.

So the tiering is: **control flow → typed → variant → diagnostic**, and variant
is reached only by genuinely mixed-type value uses.

### Implementation notes

- `not` is the exception and always yields a real Boolean. Do not unify it with
  `and`/`or`.
- Make truthiness its own IR op (`IsTrue`). Specialise statically: int/float
  `<> 0`, string/list/dict length test, pointer `<> nil`; only variant goes
  through runtime dispatch. One op so the backend can fold it in conditions.
- **Do not widen mixed numerics.** `1 or 2.5` is `1` in CPython, not `1.0`.
  Joining int|float to float silently changes observable output — use a variant
  or reject; never widen.
- Int operands depend on the new int representation:
  [[feature-a-promotable-int]]. Land that first.

### Truthiness protocol — DECIDED 2026-07-20: follow CPython exactly

Accepted with its overhead. `IsTrue(x)` resolves in CPython's order:

1. type defines `__bool__` → call it (result must be a bool);
2. else type defines `__len__` → truthy iff length ≠ 0;
3. else → always truthy.

Builtin falsy set: `None`, `False`, `0`, `0.0`, `""`, `()`, `[]`, `{}`, `set()`,
`range(0)`. A promotable int is falsy iff its **value** is zero in either storage
tier — the heap tier must not read as truthy merely because a pointer is non-nil.

The overhead is mostly avoidable in practice: when the operand's class is known
statically (the common case), `__bool__`/`__len__` resolution happens at
**compile time** and lowers to a direct call or an inlined length test. Only
genuinely dynamic operands (variant) need a runtime lookup — so "follow Python
even if it costs" mainly costs on paths that were already dynamic.

## Log
- 2026-07-20 — resolved, commit 5287bdd7.
