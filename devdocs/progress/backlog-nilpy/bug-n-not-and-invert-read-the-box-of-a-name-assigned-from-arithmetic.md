---
slug: bug-n-not-and-invert-read-the-box-of-a-name-assigned-from-arithmetic
title: "NilPy: `not v` and `~v` are wrong for any name assigned from arithmetic — `if not a:` takes the wrong branch"
track: N
prio: 70
type: bug
blocked-by: []
status: open
owner: ""
created: 2026-08-31
summary: "a = x + 1 then `not a` is True and `~a` is 4, where CPython says False and -1026. It is not about the operator on the right: +, -, *, >> all trigger it, and so does a later reassignment from a plain literal. `int(1025)` does NOT. Some spellings return a 62-bit value with a tag in the high nibble (0x3000000000000004), so `~` is complementing a BOX rather than the integer it holds. It changes CONTROL FLOW: `if not a:` takes the wrong branch, silently."
---

# Repro

```python
x = 1024
a = x + 1
print(~a)            # pxx 4        CPython -1026
print(not a)         # pxx True     CPython False
if not a:
    print("branch: falsy")     # pxx takes THIS one
else:
    print("branch: truthy")    # CPython takes this one
```

# What varies, measured

| spelling | `not v` | `~v` | CPython |
| --- | --- | --- | --- |
| `x = 1024; a = x + 1` | **True** | **4** | False / -1026 |
| same, then `a = 1025` (plain literal) | **True** | **3458764513820540932** | False / -1026 |
| `b = (1024) + 1` (literal binop) | **True** | **8070450532247928836** | False / -1026 |
| `c = int(1025)` (a call) | False | -1026 | **agrees** |
| `y = 128` (a literal, never arithmetic) | False | -129 | **agrees** |
| inside a `def`, same shapes | same as above | same | — |

`+`, `-`, `*` and `>>` all trigger it, so it is not the operator. A name that has
EVER been assigned from a binop stays broken even after a later assignment from
a bare literal, which points at the name's inferred type rather than at the
value flowing through it.

`0x3000000000000004` and `0x7000000000000004` are a tag in the high nibble over
a small payload — so `~` is complementing a BOX (variant / promo-int handle),
not the integer inside it. `~a` = 4 in the first row is the same shape with the
tag cleared: whatever it reads, it is not 1025.

`not` returning True for every one of them is consistent with reading the same
non-integer and finding it falsy — and `not 128` and `not y` are both correct,
so the truthiness path itself is fine.

# Why prio 70

It is silent and it moves control flow. `if not count:` and `if not (mask >> k):`
are ordinary Python; both take the wrong branch here with nothing printed. CPython
compatibility is one-directional (`nilpy-semantics-divergences.md`) and this is
the direction that is a defect: working CPython code runs wrong.

# Suspected site

`pyparser.inc`'s `opIsArith` decision (around the `notOp := Integer(ASTIVal[left])`
block) chooses bitwise-vs-logical `not` from the operator id of the operand node.
When the operand is a NAME rather than a binop, `ASTIVal[left]` is not an operator
id at all — it is whatever that node kind keeps there — so the branch is taken on
a field that means something else. That is a guess from reading and it is the
thing to disprove first; the boxed-value tags above may point somewhere lower.

# Found

2026-08-31, while verifying that the tkIdent -> tkShrLogical rename
(bug-a-shr-reaches-the-ir-spelled-as-tkident) had not disturbed that
`opIsArith` line. It had not — the pinned compiler produces byte-identical
wrong answers, so this predates the rename entirely. It is unrelated to the
shift work except that a `>>` probe is what put it on screen.
