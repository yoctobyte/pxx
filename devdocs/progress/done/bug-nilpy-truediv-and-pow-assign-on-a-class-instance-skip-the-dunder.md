---
prio: 50
status: done
owner: claude-A-N
---

# bug(N): `obj /= n` and `obj **= n` on a class instance skip the dunder and raise "expected a number, got object"

- **Track:** N (Nil-Python frontend). Files: `compiler/pyparser.inc`.
- **Found:** 2026-08-06, grepping the bug CLASS after fixing
  `regression-test-core-test-nilpy-augmented-assign-class-dunder`.
- **Pre-existing** — reproduces identically on `stable_linux_amd64/default/pinned`,
  so this is NOT a regression from e8450c58d67e.

## Repro

```python
class D:
    def __init__(self, v: int):
        self.v = v
    def __itruediv__(self, o):
        return D(self.v // o)
    def __ipow__(self, o):
        return D(self.v ** o)

d = D(10)
d /= 2
print(d.v)      # CPython: 5
e = D(3)
e **= 2
print(e.v)      # CPython: 9
```

CPython prints `5` then `9`. pxx compiles the program and then dies at run time:

```
Unhandled exception: TypeError: expected a number, got object
```

## Root cause (measured, not reasoned)

`PyCollectModuleLocalsAST` has two module-scope token-shape arms that assert a
*type* from a token pair alone:

- the `tkTrueDivEq` arm notes `tyDouble` for the target
- the `tkPowEq` arm notes `tyVariant`

Neither is an int/float-only operator — `/=` and `**=` dispatch `__itruediv__` /
`__ipow__` (then the binary form + rebind) exactly as `+=` dispatches `__iadd__`.
For a class-typed target the notes join through `PyWiden`:

- `PyWiden(tyClass, tyDouble)` falls to the closing "two kinds that both BOX"
  rule and yields `tyVariant`
- `PyWiden(tyClass, tyVariant)` yields `tyVariant` directly

So the name becomes a **variant holding an object**, and augmented-assign
dispatch on a variant does not find the dunder — it takes the numeric path and
hits the runtime `TypeError`. Same family as
`bug-nilpy-eq-dunder-skipped-when-either-operand-is-a-variant`.

Why `+=` is already correct: its arm (the `tkPlusEq/tkMinusEq/tkStarEq/tkShlEq`
one) now notes `tyPromoInt64` **only when the target is already known to be an
integer**, deferring to a later fixpoint round otherwise — precisely so it
cannot assert a type it has not established. That guard is the shape the `/=`
and `**=` arms are missing.

## Fix sketch

Give both arms the same "already known to be numeric" guard the `+=` arm has:
look up `PyFindConstraint` (falling back to `PyProgSym`), and note the type only
when the target is a numeric/unknown-but-scalar kind — never over a `tyClass`.
Then the class-typed target keeps `tyClass` and reaches the dunder-dispatch path
that `+=` already takes correctly.

Note the *loud* failure mode here (a runtime `TypeError`, not a wrong value) is
why this stayed hidden rather than corrupting results — but a valid CPython
program not running is still an upward-compatibility break, so it is a bug and
not a divergence.

## Gate
`make compiler/pascal26` + the repro above diffing clean against CPython +
`tools/gate.sh quick`. Add the repro to `test/` with an inline Makefile
expectation, next to `test_nilpy_augmented_assign_class_dunder.npy`.

## 2026-08-07 — FIXED; the root cause was right, and it was HALF the bug

The fix sketch above is correct and was applied verbatim: both module-scope
token-shape arms now carry the same "already known to be numeric" guard the
`+=` arm has (`PyFindConstraint`, falling back to `PyProgSym`), so a
`tyClass` target keeps its class type instead of being widened to a variant by
`PyWiden(tyClass, tyDouble)` / `PyWiden(tyClass, tyVariant)`.

That fixed `/=`. **`**=` still raised**, and the reason was a second, unrelated
gap the ticket did not see: the `tkPowEq` branch in the augmented-assign
statement **Exits early**, straight into `PyMakePow`, so it never reached
`PyAugClassDunder` below it. The type was now right and the dispatch still did
not happen.

`**` has no binary TOKEN in this frontend — it lowers through `PyMakePow`, not
`AN_BINOP` — so `PyAugBinTok` has nothing to hand `PyAugDunderName`, which is
keyed on the binary token. `PyAugDunderName` now answers `__ipow__`/`__pow__`
for **`tkPowEq` itself**, the assignment token, with a note saying why this one
entry is keyed differently from the other eleven.

## The bug CLASS, since that is where this ticket came from

Augmented assignment has **three** target shapes here, each with its own code,
and `**` needs an explicit arm in every one of them for exactly the reason
above. Grepped rather than assumed:

| target | `**=` before | now |
| --- | --- | --- |
| bare name (`e **= 2`) | reached `PyMakePow`, skipped the dunder | dispatches |
| lhs expression (`h.d **= 2`) | **did not parse at all** — "unexpected token" | dispatches |
| subscript (`xs[0] **= 5`) | does not parse | still does not — filed |

The middle row was found by grepping and fixed here, since it is the direct
sibling of the line this ticket changed: the lhs-expression aug-assign site
keys entirely on `PyAugBinTok`, so `**=` fell off the end of it. Same
desugaring as the name twin, with `CloneAST` for the store target.

The third row is `parser.inc`'s `ParseLValueAST` (`augBin`/`augRead`) — a
different mechanism in the shared parser, and its index-evaluated-once
discipline is the interesting part — so it is
[[bug-nilpy-pow-assign-to-a-subscript-does-not-parse]] rather than folded in.
The test names it at the point where it would otherwise cover it.

**Verified**, self-hosted build at this commit, diffed byte-identical against
CPython: `test/test_nilpy_truediv_pow_assign_class_dunder.npy` — `/=` and `**=`
on a class instance at module scope and inside a def; a class declaring only the
BINARY dunder (`__truediv__`/`__pow__`), which Python falls back to and rebinds;
a class-typed FIELD target for both operators; the numeric targets the arms were
written for (`i /= 4` → 2.0, `n **= 10`, `m **= -1` → 0.5, `big **= 70` past
Int64, `xs[1] /= 3`); and a class with NEITHER dunder, which still raises
TypeError at run time so `try/except` compiles. The sibling
`test_nilpy_augmented_assign_class_dunder.npy` re-diffed against CPython too.
`tools/gate.sh quick` GREEN.

## Log
- 2026-08-07 — resolved, commit PENDING-COMMIT.
