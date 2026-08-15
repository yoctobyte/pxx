---
track: N
prio: 20
type: bug
blocked-by: []
summary: "`sum(*[xs])` is refused at compile time — the run-time *args forwarder rejects any callee parameter it cannot coerce a Variant to, and pylib's `sum(l: TPyList)` is one. Loud, but it refuses a valid CPython program."
---

# The star forwarder refuses a container-typed parameter

```python
print(sum(*[[1, 2]]))     # CPython 3
                          # pascal26:1: error: Nil Python: cannot forward *args into
                          #   sum — parameter l has a type no runtime argument can be
                          #   coerced to
```

Measured 2026-08-15, left behind by
[[bug-nilpy-star-unpack-into-a-fixed-arity-builtin]], which fixed the zip and
max/min halves of the same sweep.

Loud, and the message is accurate about the mechanism — but the program is
valid CPython, so this is a refusal of working code, the one direction NilPy's
upward-compatibility rule does not allow (`devdocs/dev/nilpy-semantics-divergences.md`).

## Cause

`PyStarForwardCall` reads each argument slot out of the forwarded list as a
Variant (`pystar_arg`) and binds it to the callee's parameter. A parameter whose
type has no coercion from a Variant — a `TPyList`, a `TPyDict`, any pylib
container — is refused rather than mis-bound, which was the right call when the
check was written.

The missing step is UNBOXING, which pylib already has: a Variant holding an
object is `pyvarobj` plus a class cast, exactly what `PyStarOperandAsList` does
for a star OPERAND. The forwarder wants the same conversion on the receiving
side, per parameter, driven by the parameter's declared class.

Worth checking at the same time whether a `str`-typed or `Integer`-typed
parameter takes the same path, and whether the refusal is reachable for a USER
def (it is written for pylib signatures, but nothing restricts it to them).

## Gate

`.npy` diffed against CPython: `sum(*[xs])`; `sorted(*[xs])`; a user def taking
a list, forwarded; a callee with a container parameter AND a scalar one; and a
control that the refusal still fires for a genuinely unbindable parameter rather
than mis-binding it.
