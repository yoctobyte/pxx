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

## Recommendation

**1, with a note in the docs.** The value form is absent from the corpus, the
cost of 2 is real, and 3 makes the common case worse to serve the rare one.
Worth revisiting only if a corpus actually uses `x = a or default`.
