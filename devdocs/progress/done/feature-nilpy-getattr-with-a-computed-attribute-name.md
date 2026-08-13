---
track: N
prio: 45
type: feature
blocked-by: []
summary: "`getattr(self, 'do_' + verb)` — a COMPUTED attribute name — is refused with 'hasattr/getattr needs a literal attribute name'. That is the whole point of getattr: a command dispatcher, a plugin table, a serializer walking field names. The literal form works and the RTTI the dynamic form needs already exists (PyFindDunder dispatches by name at run time)"
status: done
owner: claude-A-N
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

## DONE 2026-08-13

The dispatcher in this ticket's own repro runs and answers CPython's values, as
do a computed FIELD name, a computed method name with arguments, a name built in
a loop (the serializer shape), a dynamically-assigned attribute, both miss
behaviours (`AttributeError` from the 2-argument form, the default from the
3-argument one), and the literal spellings still on their compile-time path.

### The ticket's guess was right: the runtime already existed

`pydynattr_get_v` resolves a name at RUN time against the dynamic-attribute
store, the class's DECLARED fields (through RTTI) and its METHODS — handing back
a bound pair for the last — and raises CPython's AttributeError otherwise. It
exists for a VARIANT receiver whose class is only known at run time, which is
exactly the position a computed name puts every receiver in. So the parse
routes there instead of refusing, and the three-argument form is
`has ? get : default`.

### Two things were NOT free, and both are the interesting part

**1. `hasattr` needed a predicate that asks what the GETTER resolves.**
`pydynattr_has_v` answers the dynamic store only. That is correct for the
literal path, which asks the compile-time field check first and falls through —
but a computed name has no compile-time half, so the store alone reported False
for a method the very next `getattr` returned. `pydynattr_has_any_v` asks the
store, then declared fields, then methods, in the getter's own order.

**2. A method read by a name no TOKEN spells is invisible** to
`PyMethodUsedAsValue`, the scan that normalises a bound method to the
function-object ABI. Without that normalisation the pair is built and calling it
returns an empty value — not a crash, which is why the test asserts the
dispatcher's RESULT rather than just that it compiles. A module containing a
computed `getattr`/`hasattr` now normalises every method. Coarse deliberately,
in the same spirit as that function's own note: the cost is boxing, both passes
still agree, and only a module that actually dispatches by a runtime name pays
it.

### Telling a literal from a computed name

`"zz" + "z"` STARTS with a string token and is a computed name; reading it as
the literal choked on the `+`. The literal path is taken only when the argument
is a string token whose very next token closes or separates it — one rule,
used both by the parse and by the module scan that decides normalisation.

### Filed while here

`to_dict(o, names).items()` — a selector on a call returning a dict built in the
body — does not parse, identically on the pinned binary.
[[bug-nilpy-selector-on-a-call-returning-a-dict-does-not-parse]], same shape as
[[bug-nilpy-def-returning-a-precreated-global-has-no-return-type]] which was
closed earlier today. The test uses a local instead.

Test `test/test_nilpy_getattr_computed_name.{npy,expected}` (`.expected` from
CPython), wired into `test-nilpy`; the 72-file NilPy attr/method/callable/bound
test family re-run. Gate: self-host fixedpoint + `gate.sh quick` GREEN.

## Log
- 2026-08-13 — resolved, commit PENDING-COMMIT.
