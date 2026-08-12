---
track: N
prio: 45
type: bug
blocked-by: []
summary: "`self.state = NEW` where NEW is a module-level constant is a compile error — 'cannot infer the type of field self.state'. Uniform across every global type (str/int/float/list/bool), so module-level constants, the most ordinary Python idiom there is, cannot reach a field without an annotation"
---

# A field assigned from a module global has no inferable type

- **Type:** bug / missing inference (NilPy) — **Track N**
- **Found:** 2026-08-12, differential bug hunting (an order state machine).
- **Loud:** a compile error, not a wrong value.

```python
NEW = "NEW"

class Order:
    def __init__(self, customer):
        self.customer = customer
        self.state = NEW          # <-- error
```

```
pascal26:6: error: Nil Python: cannot infer the type of field self.state
                   - annotate it (self.state: int = ...)
```

## Measured — it is UNIFORM, which is the useful fact

Every global type fails identically, so this is not about a particular kind:

| module global | field inference |
| --- | --- |
| `S = "NEW"` | error |
| `S = 7` | error |
| `S = 1.5` | error |
| `S = [1, 2]` | error |
| `S = True` | error |

A constructor PARAMETER (`self.customer = customer`) infers fine, and so does a
literal (`self.state = "NEW"`). It is specifically a bare ident naming a
**module global** that carries no type into the field.

## Why it matters

Module-level constants assigned to a field is one of the most ordinary shapes in
Python — a state machine's state names, a default mode, a sentinel, a config
default. The workaround (annotate the field, or inline the literal) is cheap and
the failure is loud, so this is not urgent; but it is a shape real code hits on
the first file, and it makes a class that CPython runs unmodified need edits.

## Almost certainly the same cause as the return-type sibling

[[bug-nilpy-def-returning-a-precreated-global-has-no-return-type]] is the same
fact one step over: a def whose body is `return g` has no return type for the
same reason. That ticket's 2026-08-09 diagnosis measured the constraint
directly — at the moment a def's signature is decided, **`PyFindConstraint` and
`PyProgSym` both answer −1 for the module global**; the type exists later
(`PXXDBG=n.locals` shows it), so it is a PASS-ORDERING problem, not a missing
lookup, and the obvious fallback compiles and never fires.

Field inference runs at the same point in the same pre-pass, so expect the same
answer and the same two routes recorded there:

1. re-infer in a later round of the `PyTypingChanged` fixpoint, once module
   globals are typed;
2. type module globals before defs are parsed, at least for the safe shapes.

**Do not re-derive that diagnosis** — read the sibling ticket first. The two
should very likely be fixed together, and route 1 there fixes both if the field
inference is re-asked in the same round.

## Not new
Identical on `stable_linux_amd64/default/pinned`.

## Gate

A `.npy` diffed against CPython: a field from a str / int / float / list / bool
module global, a field from a global holding a class instance, the annotated
form still working, and a control that a genuinely uninferable field still
produces the diagnostic (the message is useful and must not be traded away for
a silent Variant).
