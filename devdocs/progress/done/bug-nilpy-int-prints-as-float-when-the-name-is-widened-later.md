---
track: N
prio: 50
type: bug
status: working
owner: claude-AN-night
---

# An int prints as `5.0` because the SAME NAME is assigned a float later in the file

```python
x = 5
print(x)          # CPython: 5      pxx: 5.0
x = 3.14
print(x)          # CPython: 3.14   pxx: 3.14
```

The first `print` runs before any float exists, and still renders `5.0`. A
later assignment retroactively changes how an earlier value is displayed.

Same inside a function body:

```python
def local() -> int:
    y = 7
    print(y)      # CPython: 7      pxx: 7.0
    y = 2.5
    print(y)
```

## How it was found, and why it survived

The suite's own `test/test_nilpy_widen_fix.npy` is exactly this program, and its
recorded expectation is pxx's output, not Python's:

```make
test "$$(/tmp/test_nilpy_widen_fix26)" = "$$(printf '5.0\n3.14\n7.0\n2.5')"
```

So the test passes while encoding the divergence — the same shape as
`test_nilpy_string_variant`, whose `x < a` expectation turned out to BE the bug.
Found by running all 230 `.npy` tests under CPython and diffing: 202 run
cleanly under CPython and only three diverge, this being the only genuine one
(one is a stdout-buffering artifact of the harness, one is the deliberate
`Optional[int] -> 0` sentinel).

## Cause

Rebinding a name across types widens its STATIC type to the join (int + float
-> float), which is what makes `x = 5` then `x = 3.14` legal at all — the name
has one slot. But the widened type is then used for every reference to the
name, including those lexically BEFORE the widening assignment, so the integer
is stored and rendered as a double.

CPython has no such constraint: a name is a reference, and each binding carries
its own type.

## Options

1. **Widen to VARIANT rather than to float.** The value then carries its own
   tag and renders per-binding, which is what the variant tier is for. Costs a
   boxed slot for any name that is rebound across numeric types.
2. **Split the binding.** Treat the pre-widening and post-widening regions as
   separate slots when the assignments are unambiguous — cheap where it
   applies, silent where it does not.
3. Accept and document. Weak: `5.0` for `5` is a wrong value in output, not
   just a representation nicety, and it appears in any script that reuses a
   loop or accumulator name for a float.

Recommendation: 1, since the variant path already exists and already renders
correctly for exactly this case (a value out of a heterogeneous container
prints correctly per element). Measure the cost before defaulting it on.

## Gate

`make test-nilpy` + self-host byte-identical. Note the expectation in the
Makefile for `test_nilpy_widen_fix` must be CORRECTED to CPython's
`5 / 3.14 / 7 / 2.5` as part of the fix — leaving it as-is would keep the bug
green.


## Resolved 2026-08-03 — option 1, but ONLY for the binding join

Widened to VARIANT as recommended, with the one distinction the options section
did not draw: **the join for a REBOUND NAME is not the join for an EXPRESSION.**
`1 + 2.5` really is a float and must stay one; `x = 5` then `x = 3.14` is two
bindings of one name.

`PyWiden` serves both, so redirecting it wholesale would have boxed every mixed
arithmetic expression in every NilPy program. The new `PyWidenBinding` wraps it
and redirects exactly one pair — int meets float — at the two local-collection
join sites (module scope and def scope). Everything else keeps `PyWiden`'s
answer: int-meets-int stays scalar so ordinary integer code boxes nothing, the
two string kinds keep their own rule (a variant scalar-loaded on `return` yields
its tag word — the reason that rule exists), and a promotable int keeps its own
join, whose float case is a deliberate honest error rather than a silent boxing.

The Makefile expectation for `test_nilpy_widen_fix` is corrected to CPython's
`5 / 3.14 / 7 / 2.5`, as the gate required — leaving it would have kept the bug
green, which is how it survived in the first place.

### Blast radius, measured against pinned rather than assumed

The obvious hazard was a widened local reaching a context that scalar-loads it.
Probed it directly. Two shapes still diverge from CPython, and **both are
IMPROVED by this change, neither is caused by it**:

| program | pinned | HEAD | CPython |
| --- | --- | --- | --- |
| `def g() -> int: v=1; v=2.5; return v` | 4612811918334230528 | 2 | 2.5 |
| `def k(): v=3; v=0.5; return v + 1` | 0 | 1 | 1.5 |

Pinned's `4612811918334230528` is the IEEE bit pattern of 2.5 read as an
integer. Those two are the def's RETURN coercing to its annotated or inferred
result type, which is a different defect — filed as
[[bug-nilpy-def-return-coerces-a-float-to-the-inferred-int-result]]. They are
deliberately NOT in this ticket's test: recording pxx's `2` as expected output
would be exactly the sin this ticket is about.

Returning the widened value ITSELF (`return v`) is correct, and arithmetic on
the widened binding at module level is correct — which is what makes the return
path the narrow suspect.

### Verified

`test/test_nilpy_widen_binding_variant.npy` (+ `.expected`, wired into
`make test-nilpy`), 11 lines byte-identical to CPython: the two repros; an
integer accumulator loop as the gate on ordinary integer code not being boxed;
a float-only and an int-only rebinding as the gate on a same-kind rebinding
staying scalar; and arithmetic on each binding of a widened name.

`gate.sh quick` GREEN, self-host fixedpoint byte-identical, FPC seed clean.

## Log
- 2026-08-03 — resolved.
