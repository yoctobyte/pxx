---
track: N
prio: 35
type: bug
blocked-by: []
summary: "pyeval refuses a host method with three user parameters — `pyeval: int-return arity 3 unsupported for put` — with all-positional args, so ordinary reflected calls of arity 3 cannot be made from inside exec()"
status: done
owner: agent-AN
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

## Resolution (2026-08-15)

**The ticket's "first thing to measure" was the right question, and the answer
is: the family choice is correct, the arity was not.**

`put` returns nothing, but a NilPy `def` with no `return` is typed **Integer**,
not void — so `RetKind` really is 1 and the int-return arm really is where it
belongs. That typing is a known, separately tracked gap
(`feature-nilpy-none-variant`; see the resolved
`bug-nilpy-implicit-return-is-0-and-math-floor-returns-a-float`, which
explicitly parks the scalar-shaped-None half there). Confirmed outside exec too:
`print(c.put(...))` prints `0` where CPython prints `None`, with no exec
involved — so this ticket is not the place for it, and a comment at the arm now
records why an implicitly-returning method lands there.

What was genuinely missing is the arity, plus two whole return families:

- `TSFn*` and `TIFn*` stopped at 2 while `TVFn*`/`TVPr*` went to 5. Both now go
  to 5, so a three-, four- or five-parameter host method marshals like every
  other.
- **Double/Single return had no arm at all**, and neither did **class/pointer
  return** — both fell through to `unsupported host-call return kind`. Added,
  with the object arm boxing as VT_OBJECT and taking its own reference exactly
  as the no-argument fast path already does, so a reflected call can hand back
  an object the next call reaches.
- A `-> bool` return shares the int family's ABI but not Python's type, and
  printed `1` where CPython prints `True`. Re-boxed by the declared kind after
  the call, so one register-shaped family still serves all four kinds.

The refusal message on the remaining `else` arms is now the same
"host arity N too large" the Variant and void families already used — the old
per-family wording implied the family was the problem when the arity is.

**Gate:** `test/test_nilpy_pyeval_host_arity_and_returns.npy` (+`.expected`,
wired into the Makefile) — arities 3, 4 and 5 against void, int, str, float and
bool returns, all through `exec`. Byte-identical to CPython. The three existing
`test_nilpy_pyeval_*` tests re-diffed unchanged. `tools/gate.sh quick` GREEN,
self-host byte-identical.

## Log
- 2026-08-15 — resolved, commit 6a64afebd.
