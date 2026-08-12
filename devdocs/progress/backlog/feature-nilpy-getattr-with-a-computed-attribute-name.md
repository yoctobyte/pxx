---
track: N
prio: 45
type: feature
blocked-by: []
summary: "`getattr(self, 'do_' + verb)` — a COMPUTED attribute name — is refused with 'hasattr/getattr needs a literal attribute name'. That is the whole point of getattr: a command dispatcher, a plugin table, a serializer walking field names. The literal form works and the RTTI the dynamic form needs already exists (PyFindDunder dispatches by name at run time)"
---

# `getattr` / `hasattr` with a COMPUTED attribute name

- **Type:** feature (NilPy) — **Track N**
- **Found:** 2026-08-12, differential bug hunting — a command dispatcher, which
  is the canonical use of `getattr`.
- **Loud:** a clean diagnostic, not a wrong value.

```python
class Game:
    def do_look(self, arg): ...
    def do_go(self, arg): ...

    def dispatch(self, line):
        verb = line.split(" ")[0]
        name = "do_" + verb
        if hasattr(self, name):        # error: needs a literal attribute name
            return getattr(self, name)("")
        return "unknown verb"
```

> `pascal26: error: Nil Python: hasattr/getattr needs a literal attribute name`

The literal spellings (`getattr(obj, "field")`, `hasattr(obj, "field")`) work
today. It is specifically a name computed at run time — which is the only
reason to call `getattr` at all rather than writing `obj.field`.

## Why it is worth doing, and probably not large

Name-driven dispatch is everywhere in ordinary Python: a REPL or command
handler (`do_<verb>`), a plugin/registry table, `to_dict()` walking a field
list, a test runner collecting `test_*`. Each needs the same one thing: look a
method or field up by a string at run time.

The machinery already exists on the other side of the frontend — the runtime
dunder dispatch resolves methods by NAME at run time
([[project_nilpy_runtime_dunder_dispatch_via_pyfinddunder]]), and the RTTI
method table is what the class-as-a-value work reflects through. So this is
plausibly a matter of routing the non-literal case to a runtime lookup instead
of erroring, with the literal case keeping its fast path.

Decide with it: what a miss does (`getattr(o, n)` raises AttributeError in
CPython; the 3-argument `getattr(o, n, default)` returns the default), and
whether a returned method is a bound value — NilPy already has the bound-method
representation, and `PyMethodUsedAsValue` normalisation would have to see these
call sites.

## Gate

A `.npy` diffed against CPython: the dispatcher above, `getattr` with a default
(present and missing), `hasattr` true and false for a computed name, a computed
FIELD name (not just a method), the AttributeError from the 2-argument miss,
and the literal forms still on their fast path.
