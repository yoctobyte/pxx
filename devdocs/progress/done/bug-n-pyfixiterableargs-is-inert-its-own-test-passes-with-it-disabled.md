---
slug: bug-n-pyfixiterableargs-is-inert-its-own-test-passes-with-it-disabled
track: N
prio: 45
type: bug
status: done
owner: "claude-pxx"
blocked-by: []
summary: "MEASURED. `PyFixIterableArgs` (pyparser.inc:21694) can be disabled at its first line -- `Result := False; if True then Exit;` -- and `test/test_nilpy_user_iterable_in_builtins.npy`, the test that exists to cover it, emits a BYTE-IDENTICAL binary and identical 37-line output, still matching CPython. So does the rest of the NilPy corpus tried. Either the mechanism has been superseded by another path and is dead code, or it is entirely uncovered; both are defects and they need different fixes. Found while proving a DIFFERENT set of arms dead -- this one is a live call site whose removal nothing notices, which is the more dangerous shape."
---

# `PyFixIterableArgs` is inert: its own test passes with it disabled

- **Found:** 2026-08-31 by frankA (Track A), as the *negative* result of a
  positive control, while deleting the dead NilPy arms from the shared statement
  loop ([[bug-a-the-nilpy-arms-in-the-shared-call-loop-are-dead-and-guarded-by-the-wrong-flag]]).
- **Filed, not fixed:** the deletion decision is a behaviour-capable change in
  Track N's frontend and needs someone who knows whether the mechanism was
  superseded on purpose.

## The measurement

`compiler/pyparser.inc:21717`, the function's first lines, with a control
inserted:

```pascal
begin
  Result := False;
  if True then Exit;   { POSITIVE CONTROL }
  if not PyExprMode then Exit;
  ...
```

Rebuilt (`13ff03adbf6d` -> `1498ac818774`, so the artifact demonstrably changed),
then run against the test written for this exact mechanism:

```
test/test_nilpy_user_iterable_in_builtins.npy
  baseline vs control : IDENTICAL   (37 lines)
  baseline vs CPython : IDENTICAL
  emitted binaries    : identical
```

Byte-identical **emitted binaries**, not merely equal output — so the function
did not merely fail to change the answer, it did not change the AST at all on
the one input written to make it act.

Also unchanged with it disabled: `quick_canary_nilpy.npy`, and four scratch
probes covering `sum(bag)`, `len(list(Bag()))`, `sorted(..., key=int)` over a
class implementing `__iter__`/`__next__`, in both statement and expression
position.

## Why this is not the same finding as the ticket that produced it

That ticket deleted arms which **could not run** (wrong guard, unreachable
population). This is the opposite and worse shape: a call site that **does** run,
in the right frontend, on the right input, and removing it changes nothing. A
dead guard is visible to anyone who reads the condition; this is invisible to
reading and only a control finds it.

## What it does NOT establish

The corpus here is one suite file plus five hand-written probes. It shows the
mechanism is uncovered by the test that names it; it does not show no input
reaches it. **Before deleting, find an input that makes the control fire** — if
none exists, that is the answer.

The function's own header documents two halves (`procIdx >= 0` fixing a wrong
overload match, `procIdx < 0` draining so the match can be retried). If one half
was superseded and the other was not, the fix is narrowing, not deletion.

## Candidate explanation, unverified

`PyNodeIsUserIterable` gates every mutation in the body. If that predicate stopped
recognising the `__iter__`/`__next__` shape — a plausible casualty of the RTTI or
class-representation work — the function would go silently inert exactly like
this, and the test would keep passing because some *later* path now handles the
same programs correctly. **Check the predicate before the function.**

## Related

- [[bug-a-the-nilpy-arms-in-the-shared-call-loop-are-dead-and-guarded-by-the-wrong-flag]] — the work that surfaced this
- `bug-nilpy-builtins-over-a-user-iterable-answer-empty` — the bug the mechanism was written for
- [[a-gate-that-measures-as-no-change-is-a-finding]]

## Resolution (2026-11-20)

**Neither: half superseded, half never reachable, and the unreachable half
was a crash.** Traced on 0ab6ae5f65 by logging each arm.

- **Builtins (`list`, `tuple`, `sorted`, `sum`, `min`, `max`, `any`, `all`,
  `bytes`, `bytearray`): superseded.** Every call in
  `test_nilpy_user_iterable_in_builtins.npy` reaches the function with a match
  already made, and the matched parameter is a **Variant** (tk 22, rec 0). The
  Variant overloads walk a user iterator at run time, so neither the TPyList nor
  the TPyIter arm can fire there. That is why the control changed nothing.
- **A NilPy def's `xs: list` parameter: the arm the mechanism was for, and
  unreachable.** `PyApplyDefSignature` records a class rec id in
  `ProcParamRecId` only for `*args`/`**kwargs`. An annotated `xs: list` is
  tyClass with rec 0, so `pRec = TPyList` was never true. A Counter passed in
  was read through TPyList's layout: **segfault** (`total(Counter(4))`).
- Recording the rec id for every annotated class parameter fixes that, but it
  also makes overload matching refuse a duck-typed argument CPython accepts:
  `f(C())` into `def f(p: A)` became "no overload of f matches". It printed 3
  before. Rejected.

**Fix:** a NilPy-only parallel array `ProcParamPyListAnn` (defs.inc, allocated
and cleared in symtab.inc), written in `PyApplyDefSignature`. The procIdx >= 0
arm treats a flagged parameter as TPyList. Matching is unchanged.

**Known divergence, now instead of a crash:** the argument is drained into a
list, which agrees with CPython only when the callee iterates once. `len(xs)`,
`xs[i]`, or a second pass over a one-shot iterator answer where CPython raises
or yields nothing.

**Test:** `test_nilpy_a_user_iterator_passed_to_a_list_annotated_parameter_is_drained.py`
(test-nilpy row `listann26`). Old compiler: segfault. New: matches CPython,
including the duck-typed `f(C())` row.

**Not this ticket, filed:**
[[bug-n-a-user-iterator-into-some-shims-and-builtins-crashes-or-answers-wrong]]
(`itertools.islice`/`takewhile` segfault; `collections.Counter` empty;
`bytes`/`bytearray` refuse).
