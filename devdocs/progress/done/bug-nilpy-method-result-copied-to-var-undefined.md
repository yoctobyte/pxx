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

## 2026-07-22: FIRST HALF FIXED; a second file-set blocker remains

FIXED (the undefined-variable half): PyCollectModuleLocalsAST skipped a
module-level `x = obj.method()` assignment entirely (class methods aren't
registered during the token pre-scan), so `x` was never a symbol and a later
`y = x` in the same collect round failed. Now the skip still forgoes parsing
the RHS but records the target name (PyNoteLocalType + a scratch AllocVar so
the same round resolves it). `raw = a.mk(); zz = raw` compiles.

REMAINING (distinct, still open): a bytes value read from a dict-sourced
variant then sliced comes back mis-tagged. `remainder = d["rem"]` (variant,
None) then `remainder = raw` (raw = TPyBytes from readline) then
`remainder[:3]` → runtime `TypeError: object is not subscriptable`,
pyvar_slice sees tag=2 (VT_INT64) not 7 (VT_OBJECT). The class→variant store
tagged the bytes pointer VT_INT64 because `raw` itself was typed tyVariant (by
the collect-skip above) rather than TPyBytes, so `remainder = raw` is a
variant→variant 16-byte copy of a variant that was never boxed as VT_OBJECT.
Root: the collect-skip types method-call-result locals tyVariant, losing the
bytes class identity, and the subsequent variant-to-variant copy propagates a
mis-tagged slot. Fix needs the collect to recover the method result's class
(or the store to re-box). uforth READ-LINE is the only word blocked; file
create/write/close verified working.

## Log
- 2026-07-22 — resolved, commit 35103fd4.
