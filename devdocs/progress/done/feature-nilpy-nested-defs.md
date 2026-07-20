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

## Log

- 2026-07-20 — landed in two slices, both green against CPython:
  - 5fd3762c **structure**: a nested def registers a shell from its header (so
    the enclosing body's calls resolve), its body is skipped and queued, and
    PyParseDef compiles the queue after its own epilogue. The proc is registered
    QUALIFIED (`outer.inner`) and unqualified calls inside the parent are
    rewritten to it, walking outwards — without that, two parents each defining
    a `helper` would both bind to the first registered, since FindProc's hash
    chain is registration-ordered. Nesting is recursive to any depth.
  - c02d2c98 **capture (read)**: enclosing locals/params the body mentions become
    trailing by-value parameters filled in at each call site.
- Regression tests: `test/test_nilpy_nested_def.npy`,
  `test/test_nilpy_nested_def_capture.npy`, both in `make test-nilpy`.
- **Still open, deliberately:** `nonlocal` (a nested def WRITING an enclosing
  local — the write lands in the by-value copy and is lost) and taking a nested
  def as a VALUE (storing it, passing it, returning it). uforth registers its
  natives, so if that registration stores the inner function rather than calling
  it, this slice is not enough on its own — filed as
  [[feature-nilpy-nested-def-as-value]].
- 2026-07-20 — resolved, commit c02d2c98.
