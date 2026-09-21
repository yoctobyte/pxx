---
slug: bug-n-a-def-returning-split-on-an-unannotated-receiver-is-typed-a-string
title: a def returning str.split on an UNANNOTATED receiver is typed a string
summary: >
  RESOLVED 2026-09-21 — FIXED, AND NOT BY THIS TICKET'S WORK. Verified at
  5d8a0a60b and under pin v415's binary, so the fix is carried by the pin and is
  not inert. Verified at the MECHANISM and not only the output: `PXXDBG=n.ret`
  now reports `tk=6 rec=50` for the UNANNOTATED `c_split`, which is exactly what
  this ticket records as the correct ANNOTATED value; it recorded `tk=23`. Closed
  with a regression guard, which is what was actually missing — the fix landed
  with no fixture, in
  test_nilpy_a_call_through_a_variant_receiver_dispatches_on_the_real_class.npy,
  alongside the two dyn-dispatch result-kind tickets this shares a cause shape
  with. ORIGINAL REPORT BELOW, unedited.
  `def f(label): return label.split(",")` declares an AnsiString result for a
  call that returns a TPyList, so the caller prints raw memory where CPython
  prints `['a', 'b', 'c']`. `PXXDBG=n.ret` says tk=23. ANNOTATE the parameter
  (`label: str`) and it is correct (tk=6, rec=50), which is the whole boundary.
  The str-method arm of the return scan declines deliberately for the four
  methods whose tabulated result is tyClass (split, rsplit, partition,
  splitlines) -- its own comment records that claiming them regressed the
  ANNOTATED rsplit row once -- and nothing else then types the call, so the
  result comes from the ARGUMENT literal. Pre-existing and NOT a regression:
  measured identically under pin v408's binary.
track: N
type: bug
prio: 45
owner: unassigned
status: done
---

## Measured 2026-09-13 (frankH), at ee5b6adc7 and under stable_pinned

Two defs, one file, nothing else in it:

```python
def c_rsplit(label: str):
    return label.rsplit(" ", 1)      # ['C', 'minor']   correct

def c_split(label):
    return label.split(",")          # raw memory; CPython ['a', 'b', 'c']
```

`PXXDBG=n.ret` on that file, both compilers:

| def | n.ret | run |
| --- | --- | --- |
| `c_rsplit(label: str)` | tk=22 then **tk=6 rec=50** | correct |
| `c_split(label)` | **tk=23** | garbage |

Same under `stable_linux_amd64/default/stable_pinned`, which predates this
week's work — so this is older than the fixes it was found beside.

## Where it is, and why the obvious widening is refused

`PyInferReturnType`'s method-call arm (compiler/pyparser.inc, the `PyRetMethodType`
block). Three sub-arms in an `else if` chain:

1. the receiver resolves to a user class → `PyRetMethodType` answers;
2. the receiver is a local the scan cannot type → tyVariant (added 2026-09-13
   for the ARGUMENT-decides family; see
   `test_nilpy_a_returned_method_call_takes_its_type_from_the_argument.npy`);
3. a str method on a receiver bound in this def → `PyStrMethodInfo`'s row,
   **but only when that row is a SCALAR.**

`split`/`rsplit`/`partition`/`splitlines` are tabulated as tyClass, and arm 3
pairs `cur := smRetTk` with `PyInferLastCi := -1` — right for a scalar, and for
a class it produces "a class result with no class", which is worse. The source
says so in its own words and names the regression it caused (`7ddcb9650`). So
the arm declines, `cur` keeps whatever `PyInferExprType` took from the argument
list, and `","` makes it a string.

**Do not just extend arm 3 to the class rows** — that is the change that was
reverted. Two candidate directions, unmeasured:

- give arm 3 the class IDENTITY for those four rows (`PyInferLastCi` := the
  TPyList ci), so the answer is tyClass WITH a class rather than without one;
- or answer tyVariant for them, which is what the run-time dispatch produces
  anyway and which needs no class identity at all.

The annotated row must stay tk=6 rec=50 either way, and it reaches that by a
different route (PyInferExprType can type an annotated `label`), so it is the
control.

## Also worth a look while in here

`c_rsplit` prints **two** n.ret lines with DIFFERENT kinds — tk=22 from one pass
and tk=6 rec=50 from the other. The routine's own comments call two passes
disagreeing "a silent ABI mismatch". It works today; nobody has established why.

## How it was found, and the warning in it

Reduced from lekkerzeilen. It was first measured as WORKING in a seven-def probe
and is broken when it is the only thing in the file — the contaminant was inside
the probe, in the right population, and honest. "Would this row still pass if it
were the ONLY thing in the run?" answers NO here, which is the question that
caught it.

## Log
- 2026-09-21 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit c63455470.
