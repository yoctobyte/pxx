---
track: N
prio: 25
type: bug
blocked-by: []
summary: "A keyword argument on a run-time-dispatched call REFUSES when the name resolves to a CALLABLE FIELD rather than a method: `TypeError: zap() is dispatched at run time through a callable attribute, which takes positional arguments only`. CPython runs the same program. Method dispatch carries keywords correctly (pydyn_methkw binds by name against the RTTI's parameter names); the callable-field arm goes through pyvar_callv*, which takes POSITIONS and has no names, so the refusal is a deliberate choice of an error over a silent mis-binding. A NilPy def and lambda DO carry a signature at run time (feature-n-a-callable-value-carries-its-signature-type, pybound_new_sig), so the names may already be reachable from the callable's own value -- that is the thing to measure before designing anything."
status: open
owner: ""
---

# A keyword argument through a callable field is refused

## Repro

```python
class Holder:
    def go(self, x, mode=1):
        return x

def call(o):
    return o.zap(1, mode=2)

class Box:
    def __init__(self):
        self.v = 0

b = Box()
b.zap = lambda n, mode=0: n + mode
print(call(b))          # CPython: 3.  pxx: TypeError at run time.
```

`Holder.go` is there only to keep `zap` off every other path: no class declares
`zap`, so the call is dispatched on the receiver at run time.

`test/nilpy_open_world_kwarg_fail.npy` is this program and asserts the refusal,
so closing this ticket means changing that fixture from a refusal row to a
value row.

## Why it refuses

`PyDynMethN` looks the name up on the receiver's RTTI. A METHOD hit goes to
`PyHostCall`, which binds a `kwNames` list against the parameter names the RTTI
records — that path is correct and is what
`test_nilpy_open_world_keyword_dispatch.npy` asserts. A miss falls through to
`pydynattr_get` and then `pyvar_callv0..4`, which take positional slots only.
Binding `mode=2` to a slot there is the mis-binding
`bug-nilpy-pyeval-fallback-still-binds-host-kwargs-by-position` was filed
about, so it raises instead.

## The measurement to do first

Whether the callable's own value already carries its parameter names. A def and
a lambda are boxed by `pybound_new_sig` / `PyMakeFuncValueFor` and
`feature-n-a-callable-value-carries-its-signature-type` says a signature travels
with the value — if the NAMES are in it, this is a binder call and not a design
question. If only arity and defaults are there, it is a bigger job and should
be ranked on how much real code writes a keyword through a callable attribute,
which is not obviously much.
