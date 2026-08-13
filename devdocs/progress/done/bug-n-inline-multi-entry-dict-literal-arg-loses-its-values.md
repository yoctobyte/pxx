---
track: N
prio: 55
type: bug
blocked-by: []
summary: "`c.update({\"x\": 5, \"y\": 0})` counts each KEY once and throws the values away (answers 1 1 where CPython answers 5 0). The SAME dict passed through a variable is correct, and a SINGLE-entry literal is correct — so it is the inline multi-entry `{...}` argument that is mislowered, most likely read as a set/iterable of keys rather than a mapping."
status: done
owner: claude-A-C-N
---

# An inline multi-entry dict literal passed as an argument loses its values

- **Type:** bug (silent wrong value) — **Track N** (Nil-Python frontend)
- **Found:** 2026-08-13, while writing the CPython-parity guard for
  [[bug-p-variant-to-int-and-char-conversion-diverges-from-fpc]].
- **Pre-existing** — reproduces identically on the PINNED compiler, so it is
  not from that change.
- CPython accepts and runs this, so it is a real N bug and not a
  laxer-than-CPython feature (`devdocs/dev/nilpy-semantics-divergences.md`).

```python
from collections import Counter

m = {"x": 5, "y": 0}
a = Counter(); a.update(m)
print("via var:", a["x"], a["y"])          # CPython 5 0 — pxx 5 0   OK

b = Counter(); b.update({"x": 5, "y": 0})
print("inline :", b["x"], b["y"])          # CPython 5 0 — pxx 1 1   WRONG

d = Counter(); d.update({"x": 5})
print("1 entry:", d["x"])                  # CPython 5 — pxx 5       OK
```

## The boundary, measured

Varying one dimension at a time — the counts below are `c["x"]` after the
update, CPython on the left:

| argument shape | CPython | pxx |
| --- | --- | --- |
| built in a loop, any size | 5 | 5 |
| named variable holding the dict | 5 | 5 |
| inline literal, ONE entry | 5 | 5 |
| inline literal, TWO+ entries | 5 | **1** (values dropped, each key +1) |

So it is neither the entry count as such (a loop-built 3-entry dict is fine)
nor `update` itself — it is specifically an inline `{...}` with 2+ entries in
ARGUMENT position. `1` is what you get from counting the KEYS, i.e. from
treating the literal as an iterable, which is exactly what `Counter.update`
does with a non-mapping.

## Where to look

Python's `{...}` is ambiguous between a dict display and a set display, and the
disambiguation is the `:`. A one-entry literal being right while a two-entry
one is wrong points at the ARGUMENT-position parse of the literal (a set-vs-dict
decision made on a token lookahead that only inspects the first element, or a
trial parse whose rewind loses the mapping shape — cf.
project_trial_parse_rewind_leaves_its_hoists_queued). Check what
`type()`/`len()` say about the argument as received, not what the call does
with it: `len(m)` is right for the variable form, so the object built OUTSIDE
the call is a proper dict.

Grep the sibling shapes before closing — an inline multi-entry dict literal
passed to any pylib routine that accepts "mapping OR iterable" is the same
question: `dict(...)`, `dict.update`, `Counter(...)`, `set(...)`, `**kwargs`
forwarding.

## Gate

`make test-nilpy` + self-host fixedpoint; a `.npy` test diffed against CPython
covering the four rows above.


## ROOT CAUSE — the argument COUNTER, not the dict literal (2026-08-13)

Fixed. The literal was never the problem, and neither was set-vs-dict
disambiguation: `PyDictLiteralAt` is correct, and a probe confirmed the object
reaching the callee is a proper 2-entry dict (iterating it yields both keys with
both values).

`CountCallArgsAhead` in the SHARED `parser.inc` — the counter that says how many
arguments a call was written with, which drives arity-based overload selection —
tracked nesting depth for `(`/`[` but **not for braces**. In Pascal an opening
brace is a comment and never reaches the token stream, so the omission was
invisible for the frontend the function was written for. In Nil Python a brace
is a dict or set literal, and every comma inside one was counted as an ARGUMENT
separator.

So `d.update({"x": 5, "y": 0})` was read as a **2-argument** call. No `update`
overload takes 2 explicit arguments, so `FindUMethOverloadAhead`'s arity-viable
candidate list came back EMPTY (measured: `nCand=0`, versus 3 for the variable
and one-entry forms), and it fell back to `FindUMethArity`, which answers the
FIRST-DECLARED overload — `update(TPyList)`. That arm read a TPyDict as a
TPyList: on a Counter it counted the KEYS (hence 1 1), on a plain dict it
segfaulted.

That single mechanism explains every row of the boundary table without needing a
second story: **one entry has no comma**, a variable has no comma, and a
loop-built dict has no comma in argument position.

### Why the measurement was needed

The first two hypotheses — a set-vs-dict misparse (the ticket's own guess) and a
type-kind-only overload score treating TPyList and TPyDict as a tie (a real,
documented landmine in this codebase) — were both wrong, and both were plausible
enough to have been written down as the cause. Probes settled it: the
tie-scoring path `PyPickOverloadByArgTypes` is **never reached** for this call
(no probe output at all), because an ident receiver resolves through
`parser.inc`'s `FindUMethOverloadAhead` instead. Three different method-call
paths exist by receiver shape; guessing which one runs is how this would have
been "fixed" in the wrong file.

### The sibling, found by grepping before closing

The same counter scored a **trailing comma** as an extra argument, so
`d.update(m, )` — no literal anywhere — miscounted and segfaulted identically.
Python allows trailing commas in call arguments and this parser accepts them, so
it is the same bug in a second spelling; fixed alongside, via `TrailingCommaAt`,
which also skips newlines so a multi-line call's trailing comma reads the same.

### Also found, filed separately

`set().update({...})` is refused outright ("TPyList has no method update") — the
`|=` spelling works and lowers to `TPyList.setupdate`, so only the method NAME
is unmapped. Not fixed here because it is not this bug and has a real design
question in it (a set and a list are the same class, and a list must keep
refusing `update`): [[bug-nilpy-set-update-method-is-not-mapped]].

### Verified

`test/test_nilpy_call_arg_count_braces_and_trailing_comma.npy`, expectations
generated from CPython, wired into `test-nilpy`: the reported Counter shape, the
segfaulting plain-dict shape, a literal in non-first argument position, a nested
literal, both trailing-comma spellings, a multi-entry literal into an ordinary
`def` and as a parameter default, a set literal, and four controls that always
worked (`get(k, d)`, `dict(literal)`, `len(literal)`, the variable form).

Gate: `make compiler/pascal26` fixedpoint + `gate.sh quick` + `make test-nilpy`.

## Log
- 2026-08-13 — resolved, commit 391c67c0d.
