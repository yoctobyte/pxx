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

## Repro

`examples/tk/callbacks.npy` with a lambda calling `canvas.configure(
scrollregion=...)`, or settings.py's `_build_layout` under Xvfb.
