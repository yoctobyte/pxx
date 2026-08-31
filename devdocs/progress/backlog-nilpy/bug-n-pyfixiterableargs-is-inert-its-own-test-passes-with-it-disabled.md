---
slug: bug-n-pyfixiterableargs-is-inert-its-own-test-passes-with-it-disabled
track: N
prio: 45
type: bug
status: new
owner: ""
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
