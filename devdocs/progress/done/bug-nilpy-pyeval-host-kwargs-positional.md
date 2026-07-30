---
track: N
prio: 60
type: bug
---

# pyeval passes a host method's KEYWORD arguments POSITIONALLY (silent wrong option)

A lambda body runs in pyeval, and a method call inside it reaches the compiled
object through `PyHostCall`. Keyword arguments are appended to the argument list
**in the order written** (`ParseArgs`, pyeval.pas: "uforth passes kwargs in the
method's declaration order … so positional order is correct"), because the
method RTTI carries param KINDS but no param NAMES (`EmitMethInfo`,
rtti_emit.inc — name, code, arity, retKind, paramKinds, flags).

That assumption does not hold for a façade whose whole surface is optional
keyword options. songformatter's settings.py writes

```python
self.content.bind("<Configure>",
    lambda event: self.canvas.configure(scrollregion=self.canvas.bbox("all")))
```

`Widget.configure(state, scrollregion, yscrollcommand, xscrollcommand, text,
background, width, height)` — so the scrollregion value is handed to `state`,
and Tk is told `-state {0 0 611 1330}`. Nothing errors: the widget is simply
configured wrong. That is the worst class of bug in this project's terms.

## Second, separate limit found with it

`PyHostCall`'s pointer-family trampoline is capped at **five user arguments**
(`ptrFamily := (n <= 5)`), because pxx passes up to six parameters in registers
and self takes one. A host method with more optional parameters — `configure`
has eight — fails at run time with

```
pyeval: host method configure has an unsupported param shape
```

A method whose params are all Variant hits the same cap (`TVFn5` is the widest).

## Fixes, in the order they are worth doing

1. **[[feature-nilpy-lambda-compiled-closure]] removes both problems** — a
   compiled lambda binds keyword arguments at COMPILE time, by name, against the
   real signature, and calls the method through the ordinary call path with no
   arity cap. This is the recommended route and it is already the filed
   direction.
2. If pyeval must keep calling host methods: emit param NAMES in the method RTTI
   (a Track A change to `EmitMethInfo` / the MethInfo record) and bind by name in
   `PyHostCall`; widen the trampoline past five args by declaring the wider
   function-pointer types (pxx's own all-stack convention applies on both sides
   for >6 params, so the extra cases are mechanical).
3. Until either lands, a kwarg to a host method whose name does not match its
   POSITION should FAIL rather than silently mis-bind — the project's own rule
   (fail loudly outside the subset).

## 2026-07-30 — fix 1 landed; the reported shape is CORRECT now

[[feature-nilpy-lambda-compiled-closure]] is in, and it does what this ticket
predicted it would. Measured, not assumed — the option is read back off the
widget rather than inferred from "no error":

```python
f = lambda event: cv.configure(scrollregion="0 0 42 24")
cv.bind("<Configure>", f)
...
print(cv.cget("scrollregion"))   # 0 0 42 24
print(cv.cget("state"))          # normal   <- untouched
```

Before, that value went to `state`. The five-argument trampoline cap is gone on
the same path for the same reason: `configure` has eight parameters and now
compiles and runs, because the lifted lambda calls it through the ordinary call
path with no arity cap.

The lifted path also REJECTS a name it cannot bind, which is the loud failure
option 3 asked for: `txt.insert(chars=..., index=...)` stops with
`Text.insert has no parameter named 'index'`.

## What is LEFT — the pyeval fallback still binds by position

A lambda the lifter refuses (more than one parameter, or a body that is not a
discardable call) still runs in pyeval, and that path is unchanged. Demonstrated:

```python
g = lambda a, b: txt.insert(chars="HELLO", index="end")
g(1, 2)                      # inserts NOTHING — bound as insert("HELLO", "end")
```

Written in the correct declaration order it inserts `HELLO`, which is exactly
the positional assumption this ticket was opened about. Filed as
[[bug-nilpy-pyeval-fallback-still-binds-host-kwargs-by-position]] with that
repro, so this ticket closes on the shape it was written for and the residual
keeps its own record. Fix 2 (param NAMES in the method RTTI) is the route for it.

## Repro

`examples/tk/callbacks.npy` with a lambda calling `canvas.configure(
scrollregion=...)`, or settings.py's `_build_layout` under Xvfb.

## Log
- 2026-07-30 — resolved, commit ac5ac0fbc.
