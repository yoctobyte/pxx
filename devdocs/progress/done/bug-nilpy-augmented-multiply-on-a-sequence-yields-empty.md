---
track: N
prio: 40
type: bug
commit: 1ad845c6e
blocked-by: []
summary: "`xs *= 2` on a list and `s *= 2` on a str both produced an EMPTY value, silently. The three augmented-assignment sites build an arithmetic binop, while `x = x * n` is decided by three special arms in ParseTerm that none of them consulted."
---

# `*=` on a sequence yields empty

```python
xs = [1, 2]
xs *= 2
print(xs)            # CPython [1, 2, 1, 2]     pxx printed nothing at all

s = "ab"
s *= 3
print(s)             # CPython ababab           pxx printed an empty line
```

Silent. Found 2026-08-15 by a CPython differential sweep of slicing and
mutation. `xs = xs * 2` was correct all along, which is the tell.

## Cause

`x * n` on a sequence is not a multiply: `ParseTerm` decides it with three
special arms — `PyMakeListRepeat`, `PyMakeBytesRepeat`, and the str case, which
tags the binop `tyAnsiString` so the IR lowers it to `pystr_repeat`. The three
augmented-assignment sites (bare name, lhs-expression target, and the shared
dotted-target tail in `parser.inc`) build an `AN_BINOP` from the token
`PyAugBinTok` returns and consult none of them, so the sequence handle went into
an arithmetic multiply.

`PyAugMulNode` is that decision in one place, called from all three. It answers
-1 for a pair that really is arithmetic, so every other `*=` keeps its path.
This is the same shape as `|=` on a set, whose fix note two hundred lines away
says the same thing about the same three sites —
`devdocs/dev/normalise-dont-special-case.md`.

## Divergence recorded, not hidden

CPython's list `*=` MUTATES in place, so an alias taken beforehand sees the
repeat; this REBINDS. `+=` has the in-place form already (`TPyList.extend`) and
`*=` has no in-place primitive to call yet — filed as
[[bug-nilpy-augmented-sequence-repeat-rebinds-instead-of-mutating]]. An empty
list was the strictly worse answer, so the rebind lands now and the aliasing
half is its own ticket.

## Gate

`test/test_nilpy_augmented_sequence_repeat.npy` (+`.expected`, in the Makefile),
byte-identical to CPython: `*=` on a list, a str and bytes; the int and float
forms untouched; a FIELD target and a SUBSCRIPT target (the other two augmented
sites); a variable count; counts of 0 and 1; `x = x * n` still agreeing; and
`+=` on a list still being the in-place extend, alias included. `gate.sh quick`
GREEN. No pin — frontend-only.
