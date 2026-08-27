---
track: N
prio: 58
type: bug
blocked-by: []
summary: "`def f(x: int, go): if go: x /= 2; return x` returns 5.0 for the UNTAKEN branch where CPython returns 5. The private slot is correctly a variant carrying VT_INT, but the def's RETURN type is the widened double and coerces it. Re-measured: the return scan runs at the def HEADER, before both the constraint table and the slot exist, so it reads neither — three options weighed in the ticket, none of them one line."
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

## Shape of the fix — RE-MEASURED 2026-08-27, it is not a one-line change

The paragraph that stood here guessed at two one-line fixes and told the next
reader to confirm which record the return scan reads before assuming. Confirmed:
**neither**. `PyInferDefRetType` is called from the def HEADER
(`compiler/pyparser.inc:28493`, and again at :28510 for the `-> None`-that-lies
case) — before the body is parsed, before `PyCollectLocalsAST`, and therefore
before either the constraint table or the private slot exists. Writing the slot
type back into `PyLocals` would change a record nothing reads.

The registered return type is also not adjustable afterwards: it is the
signature, and the comment at that site says the header and the member pre-pass
"MUST agree, since the pre-pass decides the signature and this decides the
frame, and a disagreement is a silent ABI mismatch."

So the honest options, none of them one line:

1. **Answer `tyVariant` for `return <name>` when the name is a parameter the
   body rebinds.** Purely token-level (`PyParamRebound` already exists), and
   correct for every rebind — the variant carries `VT_INT` on the untaken path
   and `VT_DOUBLE` on the taken one. The cost is that it also fires for
   `def f(n: int): n = n + 1; return n`, which is very common and would return a
   variant where an Int64 does today. **Measure that cost, and check it does not
   disturb the promo-accumulator rule, before taking it.**
2. **Teach the header scan to type the rebinding.** Narrower — `/=` yields a
   float syntactically, so no inference is needed for THIS shape — but it grows
   a second miniature type-inferencer inside a token scan, which is the split
   `devdocs/dev/normalise-dont-special-case.md` warns about, and it is the same
   knowledge `PyCollectLocalsAST` already computes properly.
3. **Give the def's return type a deferral**, so the signature is fixed after
   the body pre-pass rather than at the header. The real fix and the largest —
   and it would also settle option 1's cost, since the answer would be the
   measured type rather than a blanket variant.

Option 1 is the one to try first; option 3 is what the file actually wants.
Do not take option 2.

## Gate

Both rows above match CPython, plus a three-way branch, plus the control that a
def whose parameter is rebound on EVERY path still returns the widened type.
