---
track: N
prio: 45
type: bug
---

# The pyeval fallback still binds a host method's kwargs by POSITION

The residual of [[bug-nilpy-pyeval-host-kwargs-positional]], which closed
because the compiled-lambda lift fixed the shape it was reported on. A lambda
the lifter REFUSES — more than one parameter, or a body that is not a
discardable call — still runs in pyeval, and that path appends keyword arguments
in the order written.

```python
txt = tk.Text(root); txt.pack()
g = lambda a, b: txt.insert(chars="HELLO", index="end")
g(1, 2)
print("[" + txt.get("1.0", "end") + "]")     # [] — nothing inserted
```

Bound as `insert("HELLO", "end")`: "HELLO" is not a valid Tk index, so Tk
discards the call. Written in declaration order (`index=`, `chars=`) it inserts
correctly. No error either way — the silent-wrong-option class the parent ticket
was opened about, in the one path the lift does not cover.

The one-parameter form of the same lambda is fine: it lifts, binds by name, and
a name that does not exist is a compile error.

## Why it cannot be fixed where it happens

`ParseArgs` (pyeval.pas) has the kwarg NAME but nothing to match it against: the
method RTTI carries param kinds and arity, not param names (`EmitMethInfo`,
rtti_emit.inc). Two routes:

1. **Emit param names in the method RTTI** and bind by name in `PyHostCall`.
   A Track A change to the MethInfo record — note the stride landmine
   ([[project_rtti_method_table_multi_consumer_stride_landmine]]): three
   consumers read that table and must change together.
2. **Widen the lifter** so fewer lambdas fall back at all. Cheaper per step, but
   it narrows the hole rather than closing it — a def, not just a lambda, can
   reach a host method through pyeval.

Failing loudly instead is NOT free: uforth calls `define_word(name, native=_w)`
through this path and depends on the positional behaviour, so a blanket refusal
regresses a live corpus. Any fix has to bind correctly, not just reject.

## Gate

`make test-nilpy` plus a `.npy` calling a host method with kwargs in a
NON-declaration order through a lambda the lifter refuses, asserting the effect
(read the value back off the widget), and uforth still green.
