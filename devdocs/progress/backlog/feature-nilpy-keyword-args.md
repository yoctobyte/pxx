---
track: N
prio: 65
type: feature
---

# NilPy: keyword arguments at call sites

Split out of [[decide-nilpy-closure-model]]'s measurement 2026-07-20.
**196 uforth sites**, all of one shape:

```python
vm.define_word("+", native=w_plus)
```

Parameter DEFAULTS already exist (`PyHdrDefHas` and the ProcParamDefault*
tables), so the callee side is done; what is missing is binding an argument by
NAME at the call site.

## Shape

At the call site, `name=expr` binds to the parameter of that name rather than by
position: resolve the name against `Procs[cpi].Params[i].Name`, fill the
remaining positions from the defaults that already exist, and error on a
duplicate or unknown name. Interacts with overload matching — a keyword form
should resolve after positional matching fails, not before.

Note the same syntax is a NilPy method call (`vm.define_word(...)`), so it must
work on the method path too, not only plain defs.

## Gate

`test-nilpy` green with a `.npy` case diffed against CPython — keyword after
positional, keyword filling a defaulted parameter, keyword out of declaration
order, on both a def and a method, and the error cases (unknown name, duplicate)
— plus `--tier quick` + self-host byte-identical.
