---
track: N
prio: 35
type: bug
blocked-by: []
summary: "pyeval refuses a host method with three user parameters — `pyeval: int-return arity 3 unsupported for put` — with all-positional args, so ordinary reflected calls of arity 3 cannot be made from inside exec()"
status: backlog
---

# pyeval cannot call a host method with three user parameters

- **Type:** bug (loud refusal, not a crash) — **Track N** (pyeval)

## Repro

```python
class C:
    def put(self, index, chars, tag):
        print(str(index) + "/" + str(chars) + "/" + str(tag))

c = C()
env = {"c": c}
ns = {}
exec("def __body__():\n    c.put('A', 'B', 'T')\n", env, ns)
ns["__body__"]()
```

CPython: `A/B/T`.
pxx at pin **v292** (and earlier — reproduced on `stable_linux_amd64/default/pinned`):

```
pyeval: int-return arity 3 unsupported for put
```

**All-positional**, so this is not about keyword binding
(`bug-nilpy-pyeval-fallback-still-binds-host-kwargs-by-position`, which is
fixed); it is the marshaller's shape coverage. Found while building the
headless repro for that ticket.

## Cause

`PyHostCall` (`compiler/builtin/pyeval.pas`) marshals by enumerating concrete
signature FAMILIES — `TVFn0..TVFn5`, `TPFn0..TPFn5`, `TSFn*`, `TIFn0..TIFn2`,
and so on — and picks one from the return kind plus the param kinds. The
diagnostic names the family it landed in (`int-return`) and the arity it could
not serve, so the gap is a missing arm rather than a missing capability: the
sibling families already go to arity 5.

Note the classification is also worth checking. `put` is a **procedure**, so
`RetKind` should be 0 and it should never have reached an "int-return" arm at
all. Whether the real defect is the missing arity-3 arm or the wrong family
choice is the first thing to measure — a method that returns nothing being
marshalled as int-returning would be its own bug, and possibly the one that
matters.

## Fix

Measure which family it selects and why, then either add the missing arms or
fix the selection. Prefer whatever reduces the number of hand-written families:
the table is already long and each new one is another place a shape can be
missed silently.

## Gate

`make compiler/pascal26` + the repro + `tools/gate.sh quick`, plus the uforth
corpus (its `vm` methods are the densest real users of this trampoline). A pin,
since `compiler/builtin/pyeval.pas` changes.
