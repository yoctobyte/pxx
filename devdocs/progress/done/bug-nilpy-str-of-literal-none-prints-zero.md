---
track: N
prio: 65
type: bug
---

# `str(None)` prints `0`, but `str(x)` with `x = None` prints `None`

```python
x = None
print(str(None))        # CPython: None    pxx: 0
print(str(x))           # CPython: None    pxx: None      <- correct
print("v=" + str(None)) # CPython: v=None  pxx: v=0
print(None)             # CPython: None    pxx: None      <- correct
```

A LITERAL `None` handed to `str()` is typed as integer 0 and formatted as such.
Bound to a name first it is a variant carrying the None sentinel and formats
correctly, and bare `print(None)` is correct too — so only the
literal-straight-into-`str()` route is wrong.

Silent: a `"prefix" + str(None)` in a message produces `prefix0`, which reads
like data rather than like a bug.

This is the literal end of the None-representation family
([[project_nilpy_none_routes_sentinels.md]]): the sentinel is right everywhere
it flows through a variant, and wrong where a literal is typed directly.

Found by sweeping builtins over argument types against CPython.

## Located 2026-07-30 — and why it was PARKED rather than fixed

The None literal is built in `ParseFactor` (parser.inc, the `tkNil` arm):

```pascal
    tkNil:
    begin
      node := AllocNode(AN_INT_LIT); ASTIVal[node] := 0;
      ASTTk[node] := Ord(tyPointer); CurASTNode := node; Next;
      LastExprTk := tyPointer;
    end;
```

So a bare `None` is the integer 0, and `str()`'s overload set picks the numeric
member. Everywhere None already behaves correctly, a caller special-cases the
token FIRST and substitutes `PyMakeNone` — the tuple-element path
(pyparser.inc ~6669), the keyword-argument path (~7130), `print` (~7749) and
several more. `str()`'s argument is simply not one of those sites.

The tempting fix — make the `tkNil` arm yield `PyMakeNone` under PyExprMode, so
every position gets it for free — is NOT safe as a drive-by. Several paths
depend on the literal being a SCALAR: ir.inc's class-rebind ARC arm fires on
`d = None` precisely because the right-hand side's type kind is in the scalar
set, and `Optional[int]` deliberately maps None to a 0 sentinel
([[bug-nilpy-none-equals-zero-is-true]] documents that trade). Turning the
literal into a variant everywhere changes all of them at once, at the far end
of a 20-minute gate.

Two honest options for whoever picks this up:

1. **Narrow**: substitute `PyMakeNone` at the call-argument site only, next to
   the sites that already do it. Fixes `str(None)` and `f(None)` generally,
   touches nothing else.
2. **Blanket**: change the `tkNil` arm, and audit every consumer that reads
   `ASTTk` of a None right-hand side — the ARC rebind arm, `Optional[int]`
   widening, and the `is None` comparisons — in one deliberate pass. This is
   the better end state and is really the same question as
   [[bug-nilpy-none-equals-zero-is-true]]; do them together.

## Gate

`make test-nilpy` + self-host byte-identical, plus a regression covering
`str(None)`, `str(x)`, `"" + str(None)` and f-string/`%` interpolation of a
literal None.

## Log
- 2026-07-30 — resolved, commit d68612d6e.
