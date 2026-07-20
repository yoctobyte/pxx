---
track: N
prio: 55
type: feature
---

# NilPy: default arguments as explicit by-value capture

Split out of [[decide-nilpy-closure-model]]'s measurement 2026-07-20. This is
Python's own workaround for late binding, and uforth uses it wherever it
genuinely closes over something:

```python
def w_field_colon(vm: VM) -> None:
    offset = _align_cell(vm.pop())
    def _field(v, _offset=offset):      # captured HERE, by value
        vm.push(v + _offset)
    vm.define_word(name, native=_field)
```

## Why it is its own ticket

It looks like a closure but is not: the default is evaluated at DEFINITION time
and stored on the function, so no cell, no capture set, no escape analysis. With
[[feature-nilpy-function-values]] in place this is a value baked into the
closure-free function record.

Parameter defaults already parse for plain defs (`PyParamDefaultAt`,
`ProcParamDefaultVal`); what is missing is a default whose value is a runtime
EXPRESSION of an enclosing local rather than a constant — today's table stores a
folded ordinal or a string literal.

## Gate

`test-nilpy` green with a `.npy` case diffed against CPython — the shape above,
two functions made in sequence capturing different values, and the captured
value surviving after the enclosing def returns — plus `--tier quick` +
self-host byte-identical.
