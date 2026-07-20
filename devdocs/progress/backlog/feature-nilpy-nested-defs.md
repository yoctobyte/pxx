---
track: N
prio: 70
type: feature
---

# NilPy: nested `def`

Characterised 2026-07-20. Fails to parse — loudly.

```python
def outer(n: int) -> int:
    def inner(m: int) -> int:
        return m * 2
    return inner(n) + 1
```
```
error: expected expression   near:  int >>> inner
```

## Why the priority

**214 nested defs in uforth.py.** It is not an occasional idiom there — the
word-registration functions define their natives inline, which is the whole
structure of the file's second half. Counted with `ast.walk` over each
module-level FunctionDef, so class methods are not included in that number.

## What makes it tractable

The shared codegen already HAS nested routines — Pascal has had them for a
while, including access to the enclosing frame's locals, which is exactly what
a Python closure needs for read access. So this is a frontend change:
`PyParseStatement` needs a `tkFunction` case that parses a def in a nested
scope rather than only at top level, and the local-typing pre-pass has to skip
the nested body the way it already skips a def at module scope.

## Watch for

- The typing pre-pass (`PyCollectLocalsAST`) trial-parses the enclosing body.
  A nested def inside it must not be registered twice — the same
  BodyAddr-is-set guard `PyParseDef` uses for redefinition applies.
- `PyRegisterDefShells` deliberately only registers depth-0 defs. A nested def
  is not visible outside its parent, so that stays right — but forward calls
  BETWEEN siblings inside the same parent will not work until the nested case
  gets its own shell pass.
- Closures that WRITE an enclosing local need `nonlocal`, which is separate
  (1 uforth site).

## Gate

`test-nilpy` green with a `.npy` case diffed against CPython — nested call,
reading an enclosing local, and two siblings — + `--tier quick` + self-host
byte-identical + `make fpc-check`.
