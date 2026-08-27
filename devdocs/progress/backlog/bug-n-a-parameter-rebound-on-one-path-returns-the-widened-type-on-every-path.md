---
track: N
prio: 58
type: bug
owner: unassigned
blocked-by: []
summary: "`def f(x: int, go): if go: x /= 2; return x` returns 5.0 for the UNTAKEN branch where CPython returns 5. The private slot is correctly a variant carrying VT_INT, but the def's inferred RETURN type is the widened double, so the int is coerced on the way out. The return-type inference is a token scan and does not read the constraint table."
---

# A parameter rebound on one path returns the widened type on every path

- **Type:** bug (Track N) — wrong VALUE (an int comes back as a float).
- **Found:** 2026-08-27, the one row left red by
  [[bug-n-augmented-true-division-does-not-widen-an-annotated-int-parameter]].
- **Measured on:** HEAD. **Improved but not fixed** by that ticket — see below.

## Repro

```python
def branch(x: int, go: int):
    if go:
        x /= 2
    return x
print(branch(5, 1), branch(5, 0))
```

| | taken | untaken |
| --- | --- | --- |
| CPython | `2.5` | `5` |
| pxx **v383** | `4.612811918334231e+18` | `5.0` |
| pxx **HEAD** | `2.5` | `5.0` |

So the sibling fix turned the taken branch from garbage into the right answer
and left the untaken one returning a float.

## Cause — measured

```
$ PXXDBG=n.locals,n.ret ./compiler/pascal26 br.npy br
PXXDBG n.ret    def@0 branch tk=19 rec=0 sawNone=0 trial=0
PXXDBG n.locals branch x tk=19 rec=-1 | sym=471 symtk=22 symrec=0 kind=0
```

`symtk=22` is **tyVariant**: the private slot the sibling fix creates is right,
and on the untaken path it holds `VT_INT 5`. But `n.ret tk=19` — the def's
registered RETURN type is **tyDouble**, so the variant is coerced on the way
out and the int becomes 5.0.

The return-type inference is a separate token scan; it sees `x /= 2` and answers
double without consulting the constraint table, which is why fixing the slot did
not fix this. Note the constraint table ALSO still says `tk=19` for `x` while
the symbol says 22 — two records of one answer, disagreeing, which is the
smell to fix rather than to route around.

## Shape of the fix

Make the return-type inference read the same answer the slot does. Whether that
means having the token scan consult `PyLocals`/the symbol, or having the private
slot write its type back into the constraint after the second
`PyCollectLocalsAST` pass, is the thing to measure. The second is a one-line
change and may be enough; confirm which record the return scan actually reads
before assuming.

## Gate

Both rows above match CPython, plus a three-way branch, plus the control that a
def whose parameter is rebound on EVERY path still returns the widened type.
