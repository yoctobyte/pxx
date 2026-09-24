---
track: N
prio: 80
type: bug
blocked-by: []
summary: "MECHANISM: a class field's type is joined only from stores through `self` inside the class's own methods (the class pre-pass, PyWidenBinding over `self.<f> = ...`). A store through ANY other receiver -- a parameter, a local, a module name, a tuple or chain target -- is never seen by that join, so the field keeps its first type and the value is written into it unconverted. A float-typed value into an int field lands as its IEEE BITS (`b.s = y` with y = 1.5 prints 4609434218613702656); a float LITERAL is truncated instead (prints 1), which is also wrong; an int into a float field prints `3.0` where CPython prints `3`. Silent, exit 0, every receiver kind except self. Springs whenever code outside a class rebinds a field to a type its own methods never store."
---

# A store through a non-self receiver never widens the field

Found 2026-09-24 (frankb-12) while working the parameter-receiver unpack ticket,
whose own store was already fixed: the variations put a DIFFERENT TYPE through
the same receivers and every one of them came back wrong, including the plain
single statement, so this is not an unpack defect.

## Measured at HEAD, x86-64, against CPython 3 on the same file

```python
class A:
    def __init__(self):
        self.s = 0
        self.f = 0.5

def var_into_int(b):   y = 1.5; b.s = y;  print(b.s)   # CPython 1.5  pxx 4609434218613702656
def field_into_int(b): b.s = b.f;         print(b.s)   # CPython 0.5  pxx 4602678819172646912
def int_into_float(b): b.f = 3;           print(b.f)   # CPython 3    pxx 3.0
def local_recv():      a = A(); y = 2.5; a.s = y; print(a.s)   # CPython 2.5  pxx 4612811918334230528
def literal(b):        b.s = 1.5;         print(b.s)   # CPython 1.5  pxx 1   (truncated)
```

The same through a tuple target (`b.s, x = 1.5, 2`) and a chain target
(`b.s = b.u = 33`) behaves identically: they reach the field through
`PyMakeAttrStore`, which assigns the value node straight into the `AN_FIELD`.

## Why it is the field join and not the store

The `self` case was fixed in
[[bug-n-a-fields-type-is-fixed-by-its-first-assignment-and-never-widened]]: the
class pre-pass now joins every `self.<f> = <expr>` with PyWidenBinding, the same
join locals use. It is token-driven and runs BEFORE any body is typed, so it can
recognise `self` and nothing else -- `b.s = ...` names a receiver whose class is
not known until the def is parsed. By then the layout is fixed.

## What a fix has to do, and what it must not

- **Not** a coercion at the store. Converting float-into-int would make the
  bits case agree with the literal case, and both are wrong: in Python the
  field BECOMES a float.
- **Not** a refusal either, as a first move: it would turn working programs
  whose bad path never runs into programs that do not compile. Worth having
  only as the fallback for a receiver whose class cannot be determined.
- The shape of a real fix: let the typing rounds note "field f of class C
  receives type T" at every static-field store (the trial parse already
  iterates to a fixpoint for locals via PyTypingChanged), and re-lay-out the
  class when that widens a field. A field widened to variant is what
  PyWidenBinding already answers for the int/float rebind.

Would retire this: the five rows above printing CPython's answers.
