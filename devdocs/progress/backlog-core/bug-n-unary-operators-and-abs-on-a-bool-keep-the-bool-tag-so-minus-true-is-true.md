---
slug: bug-n-unary-operators-and-abs-on-a-bool-keep-the-bool-tag-so-minus-true-is-true
title: "`-True` is `True` instead of `-1` — the unary operators and `abs()` hand back a bool where Python gives an int"
track: N
prio: 45
type: bug
status: backlog
owner: ""
created: 2026-09-22
found-by: franks-5b
blocked-by: []
summary: "MECHANISM: a unary operator applied to a VT_BOOL returns the operand's TAG rather than converting to int, so the result re-renders as a bool. It SPRINGS wherever a numeric operation's result is handed back through the operand's own variant tag instead of a numeric one. For NEGATION this is not a display defect but a WRONG VALUE -- `-True` answers True (i.e. 1) where CPython gives -1, so the sign is discarded silently. Four instances measured 2026-09-22: `-True` -> True (CPython -1), `+True` -> True (1), `abs(True)` -> True (1), `abs(False)` -> False (0). THE BINARY OPERATORS ARE ALL CORRECT, which is what hides it and what bounds the fix: True+1, True*2, True//1, min(True,5), max(True,0), sum([True,True]), int(True), divmod(True,1), pow(True,1) and round(True) every one matches CPython. So a bool is converted correctly everywhere EXCEPT where the operation is unary. Not caused by the Low(Int64) work landed the same day -- established by stash, rebuild and re-run, where these rows are unchanged and only the Low(Int64) row moved."
---

# `-True` is `True`, and that one is a wrong value

Python's `bool` is a subclass of `int`, so every arithmetic operation on it
yields an `int`. pxx agrees for binary operators and disagrees for unary ones.

## Repro

```python
print(-True)        # pxx: True    CPython: -1     <- WRONG VALUE
print(+True)        # pxx: True    CPython: 1
print(abs(True))    # pxx: True    CPython: 1
print(abs(False))   # pxx: False   CPython: 0
```

## What is CORRECT, which is both the camouflage and the bound on the fix

Measured in the same run, same binary, all matching CPython:

    True + 1      True * 2      True // 1     int(True)
    min(True, 5)  max(True, 0)  sum([T, T])   divmod(True, 1)
    pow(True, 1)  round(True)

**A bool converts correctly everywhere except where the operator is unary.**
That is why nothing has caught it: the spellings a program actually uses on a
flag — adding it, summing it, comparing it — are all right.

## Why the negation one is different in kind

`+True` and `abs(True)` are type-identity defects: the *value* is 1 either way,
and only `type()` or a print distinguishes them. **`-True` is a wrong number.**
Python gives -1; pxx gives a value that renders as `True` and reads as 1. A
counter doing `step = -flag` gets `+1` where it asked for `-1`, with no
diagnostic — the sign is simply gone.

That makes this a correctness ticket rather than a tidiness one, and it is the
reason the prio is not 15.

## Where to look

The unary path, not `pyabs_v`'s arms — `abs()` is one of the four and the other
three are operators, so a fix inside `abs()` would repair one instance and
leave the class. Find where a unary result takes its variant tag from its
operand and make a numeric operation yield a numeric tag. Confirm with
`PXXDBG=a.ast:<proc>` which path `-True` actually takes before editing; do not
assume it reaches the same helper `abs()` does (`abs(True)` may be folded in
the frontend and never reach `pyabs_v` at all — untested).

## Attribution

Found while closing
`bug-a-low-int64-renders-as-a-bare-minus-under-percent-d-and-abs-of-it-stays-negative`,
whose `abs()` fix is in the same function. **Not caused by it** — stashed that
change, rebuilt, re-ran: these four rows are byte-identical before and after,
and only the `Low(Int64)` row moved.
