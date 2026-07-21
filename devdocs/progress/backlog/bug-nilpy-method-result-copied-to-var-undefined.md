---
track: N
prio: 60
type: bug
---

# NilPy: `x = obj.method()` immediately followed by `y = x` leaves x undefined

## Symptom

A local assigned from a class-returning METHOD CALL, then copied to another
variable, fails to compile — the second statement reports `undefined variable`
for the first local:

```python
class A:
    def __init__(self) -> None:
        self.x: int = 0
    def mk(self) -> "A":
        return A()
a = A()
raw = a.mk()      # method call returning a class
zz = raw          # error: undefined variable (raw)
```

`raw = a.mk()` followed by `print(raw.n)` WORKS (raw resolves as a method
receiver). Only `zz = raw` — a bare class-typed ident as the whole RHS of a new
assignment — fails. Ctor results (`a = A(); b = a`) work; list/bytes-literal
results (`raw = [1]; zz = raw`) work. The failure is specific to a
**method-call result** copied by a plain `y = x`.

## Root cause (narrowed, not yet fixed)

Instrumentation shows the statement `raw = a.mk()` NEVER reaches
`PyParseStatement`'s statement-start — the previous statement's parse
over-consumes the token cursor past `raw`, so `raw` is never AllocVar'd, and
`zz = raw` then can't resolve it. The over-consumption happens only when the
RHS is a class-returning method call whose result is stored to a fresh local
and a further statement follows. Reproduces during the PyCollectLocalsAST
typing pre-pass (round 1). Cursor mis-tracking in the assignment-of-method-call
path, likely a missing newline/statement-terminator after a class-typed
method-call RHS.

## Impact

Blocks uforth's file-word conformance (filetest.fth): `w_read_line` does
`raw = entry["file"].readline()` then slices/copies `raw`. The file I/O itself
is DONE (TPyFile raw syscalls, open(path,mode), read/readline/write/seek/…);
only this copy-of-method-result typing bug stops READ-LINE. core.fr /
coreplus / coreext / block / double / exception / facility all pass; the file
set is the first blocked by this.

## Repro

`/tmp/w79.npy` (6 lines above). `./compiler/pascal26 repro.npy /tmp/out` →
`error: undefined variable (raw)`.
