---
track: N
prio: 45
type: bug
summary: "A lambda with 2+ parameters still lowers to a pyeval SOURCE closure and is re-walked per call — the lift is gated on nParams <= 1 because the bound-fn bridge passes one argument. Correct answers, ~7x the per-call cost."
status: done
owner: claude-A
---

# Multi-parameter lambdas are still interpreted

- **Type:** bug (performance) — **Track N** (`pyparser.inc`, `PyParseLambdaStub`)
- **Filed:** 2026-08-10, as the recorded remainder of
  [[bug-nilpy-every-lambda-is-interpreted-instead-of-compiled]], which fixed the
  1-parameter case.

## Measured

```python
f = lambda a, b: a + b        # 7   — correct
g = lambda a, b, c: a * b + c # 10  — correct
```

Answers match CPython. But the bodies are still shipped as source text and run
by the tree-walker:

```
strings <bin> | grep -c '^return '   ->  2      (one per lambda)
```

Zero for a 1-parameter lambda since the parent fix. Expect the same ~6.9 µs vs
1.0 µs per-call gap measured there.

## Why it is gated

`PyParseLambdaStub`'s lift is guarded by `nParams <= 1`. The reason is the
bridge: `pyboundfn_callv(objptr, a0, res)` passes exactly **one** argument, and
a lifted proc reserves parameter 0 for the lambda's own argument with every
capture bound after it. A second own parameter has nowhere to ride.

`pyboundfn_callvn(objptr, a0, a1, a2, ...)` already exists — the multi-argument
bridge is there. What is missing is the lowering choosing it and the capture
layout reserving N own slots instead of 1.

## Why the priority is only 45

Every `key=` / `map` / `filter` / `sorted` callback is **1-parameter**, and that
is the overwhelming majority of lambdas in real Python — which is why the parent
fix took that case first. Multi-parameter lambdas show up in `reduce`, custom
comparators, and callback APIs that pass several values, so this is real but far
less hot.

## Fix direction

Reserve `nParams` own slots at the head of the lifted parameter list rather than
exactly one, bind captures after them, and route the call through
`pyboundfn_callvn`. The existing zero-parameter case (a dummy `$lamarg0` absorbs
the bridge's single argument) shows the slot bookkeeping is already
parameterised in shape, just not in count.

Watch `PY_MAX_CAPS`: own parameters and captures share the bound-slot budget, so
N own parameters reduce the captures a lambda can hold.

## Gate

The two lambdas above compiled (`strings ... | grep -c '^return '` = 0), answers
still matching CPython, the NilPy suite green, and self-host fixedpoint.

---

## STILL LIVE — an output diff cannot see this one (verified 2026-08-11, claude-an-1)

`f = lambda a, b: a + b` and `g = lambda a, b, c: a * b + c` both return the
RIGHT VALUES on `pinned` and HEAD, so a CPython output diff shows no difference
and this ticket looks stale in an automated sweep. It is not: the claim is about
HOW they run, not what they answer.

The tell (per [[project_nilpy_every_lambda_is_an_interpreted_source_closure]])
is the lambda's SOURCE TEXT embedded in the binary:

```
$ strings ./prog | grep -c 'a + b\|a \* b + c'
2
```

Still 2 at HEAD — both lambdas are still interpreted pyeval source closures.
Ticket stands.

## Resolution (2026-08-11)

The runtime was already parameterised in own-argument count and nobody had told
it: `pyboundfn_callvn` carries `a0/a1/a2` and places `NOwn` of them ahead of the
bound slots, and `pyboundfn_setown` exists precisely to set `NOwn`. Only this
lowering hard-coded one own slot. So the fix is the ticket's own direction, with
no runtime work at all:

- reserve `nParams` own slots (a dummy `$lamarg0` still absorbs the bridge's
  argument for a zero-parameter lambda);
- `nBound` becomes `lamN - lamOwn`;
- chain `pyboundfn_setown(fn, lamOwn)` when it is not 1;
- gate at `nParams <= 3`, which is what the bridge carries.

**The bug the first attempt introduced is the part worth remembering:** the
capture-bind loop ran `for j := 1 to lamN - 1`, so with two own parameters it
bound the lambda's own `b` as bound slot 0 — over `lamSyms[1] = -1`, because an
own parameter binds no enclosing symbol. That built an `AN_IDENT` on symbol -1
and the IR came out with a garbage type kind: `invalid type kind in IR node`,
pointing at the end of the file. The loop now starts at `lamOwn`. Same hardcoded
1 in the defaults' `varMask` scan, fixed with it.

Verified: `strings <bin> | grep -c` on the lambda bodies is **0** where it was 2,
answers matching CPython for 2- and 3-parameter lambdas with and without a
capture, a lambda passed as a value and called through a parameter, `key=`, and
the 0- and 1-parameter cases that already lifted. `make test-nilpy` EXIT=0,
`gate.sh quick` GREEN.

Two adjacent findings, both PRE-EXISTING on `pinned` and neither caused here:

- **A 4+-parameter lambda SEGFAULTS when called.** It keeps the interpreted
  fallback (the bridge carries three), and that path crashes on valid Python.
  Filed as `bug-nilpy-a-four-parameter-lambda-segfaults-when-called` (prio 50 —
  a crash outranks this ticket's performance concern), with both candidate
  fixes weighed there.
- `lambda x, y=3:` — a default whose value is a LITERAL rather than a name — is
  refused by the existing default-capture parser. Recorded here rather than
  filed, since the diagnostic is honest and names the restriction.

## Log
- 2026-08-11 — resolved, commit PENDING-COMMIT.
