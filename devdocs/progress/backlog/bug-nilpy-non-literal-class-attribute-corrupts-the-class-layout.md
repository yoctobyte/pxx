---
track: N
prio: 70
type: bug
summary: "A class attribute with a NON-LITERAL initialiser (`g = 2 + 3`) corrupts the class: a method returning a tuple of two OTHER class attributes then prints nothing or segfaults. Deleting the unused attribute fixes it"
---

# A non-literal class attribute corrupts the class layout

- **Type:** bug (NilPy class attributes — SEGFAULT or SILENT EMPTY) — **Track N**
- **Found:** 2026-08-02, while writing the regression test for
  [[bug-nilpy-annotated-class-attribute-fails-to-parse]]. **Pre-existing** —
  reproduced against a stashed baseline build, and on the unannotated spelling,
  so neither annotations nor that fix are involved.

## Repro — three lines apart

```python
class A:
    a = 0
    d = "hi"
    g = 2 + 3            # <-- never read by anything below
    def read(self):
        return self.a, self.d
print(A().read())        # CPython (0, 'hi')    pxx: prints nothing (or segfaults)
```

Delete the `g` line and it prints `(0, 'hi')` correctly. **`g` is never
referenced** — declaring it is enough.

`2 + 3` is only an example: what matters is that the initialiser is not a single
literal TOKEN, so it takes the non-literal path. `g = []`, `g = Inner()` and
`g = f()` are the same shape.

## Where to look, and why the two branches are the suspects

`PyRegisterClassMembers` registers class attributes in **two** branches that
each call `AddUField` and each advance `curOff` independently:

- the LITERAL branch — folds the constant, types the field from the literal
  token (`tkInteger` -> `tyInt64`, `tkString` -> `tyAnsiString`, ...)
- the NON-LITERAL branch — types the field `tyVariant` (or `tyClass` for
  `Name(...)`), and `PyParseClass` evaluates the expression once into a hidden
  `$clsattr.<Class>.<name>` global that construction copies in

A class holding BOTH kinds is exactly the case where those two could disagree
about offsets or sizes — a `tyVariant` field is 16 bytes against a scalar's 8 —
and a wrong offset for the STRING attribute is consistent with what is observed
(the managed field is read from the wrong place, so the tuple build walks a bad
handle). Dump the offsets before theorising: that is a measurement, not a guess.

## The failure mode is unstable — fix against the SILENT one

The same source, rebuilt, either segfaults or prints nothing and exits 0. The
empty-output mood is the dangerous one and is the shape to fix against; the
crash is the lucky case. `-dPXX_HEAP_DEBUG` (freed bytes become `$DD` rather
than a recycled neighbour's) and `-dPXX_OBJTRACE` before any print-bisecting —
this is the "plausible wrong value far from the cause" class the debugging
playbook exists for.

## Controls that PASS — the ingredients are individually fine

| shape | result |
| --- | --- |
| the same class WITHOUT the non-literal attribute | correct |
| non-literal attribute present, method returns only `self.g` | correct |
| non-literal + container attributes, each read on its own line | correct |
| seven scalar class attributes returned as a tuple, no non-literal | correct |
| two container class attributes, no tuple-returning method | correct |
| the same values as MODULE globals | correct |
| the same values set in `__init__` as instance fields | correct |

So it needs a non-literal class attribute to EXIST and another method to build a
tuple out of the class's other attributes.

## Impact

`g = 2 + 3`, `mode = Inner()` and `items = []` at class level are ordinary
Python, and the attribute that breaks the class need not be used at all — which
makes this very hard to attribute from the symptom. A program loses a whole
tuple's worth of output with no diagnostic.

## Gate

A `.npy` diffed against CPython: the repro above; a class mixing literal,
non-literal and container class attributes read every way (individually, as a
tuple, through a method and directly on the instance); the module-global and
instance-field arrangements as controls; and the existing class-attribute tests
still green.
