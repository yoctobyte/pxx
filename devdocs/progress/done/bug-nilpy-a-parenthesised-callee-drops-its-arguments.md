---
track: N
prio: 60
type: bug
summary: "`x = (expr)(args)` parses as just `(expr)` — the argument list is DISCARDED with no diagnostic, so `(add)(4, 5)` answers a raw code address instead of 9. Silent wrong value on a form CPython accepts."
status: done
owner: claude-an-1
---

# A parenthesised callee on an assignment RHS drops its arguments

```python
def add(a, b):
    return a + b

x = (3 + 4)(1)      # pxx: 7          CPython: TypeError: 'int' object is not callable
y = (add)(4, 5)     # pxx: 5810900    CPython: 9
n = 7
z = (n)(1)          # pxx: 7          CPython: TypeError
s = "ab"
w = (s)(1)          # pxx: "ab"       CPython: TypeError
```

Every one of these compiles clean and prints the value of the **parenthesised
group**, with the argument list silently thrown away. `(add)(4, 5)` is the one
that hurts: it is ordinary working Python, and the answer is a raw code address
formatted as an integer.

## Why it is a distinct defect from the callable tag

Found while landing `feature-nilpy-a-callable-value-needs-its-own-variant-tag`,
whose whole subject is `(3 + 4)(x)`. It turns out that spelling never reaches
the callee guard at all on an assignment RHS — the call is gone before lowering,
so no runtime tag test can see it. The two are independent:

| spelling | before | after the tag |
| --- | --- | --- |
| `get(1)(3)` (call result as callee) | SEGFAULT | TypeError ✓ |
| `x = (3 + 4)(1)` (paren group as callee) | answers 7 | answers 7 — untouched |

## The boundary, measured

- **Assignment RHS** — arguments dropped, silent. All four receiver shapes above.
- **Call-argument position** — WORKS: `print((f)(1, 2))` prints 3.
- **Bare statement inside an indented block** — a parse ERROR, not a wrong
  value: `pascal26: error: Nil Python: expected newline after statement`.

So one construct takes three different paths and only one of them is right —
the "member access has TWO parsers by receiver shape" shape again.

## Where to look

`ParseFactor`'s parenthesised-group arm in `parser.inc` (~10360-10420 region,
the `if PyExprMode and (CurTok.Kind = tkLParen)` after `Expect(tkRParen, ')')`).
It calls `PyBoxCallableValue` so an immediately-invoked LAMBDA works
(`bug-nilpy-immediately-invoked-lambda-is-not-callable`), and that boxing is a
no-op for anything else — but nothing then consumes the `(` as a CALL. The
postfix loop right below it handles `^`, `.` and `[` and deliberately stands
down for Python; `(` was never added to either.

## Gate

`make test-nilpy` + self-host byte-identical. CPython-diffed over the four
receiver shapes above in all three positions (RHS, argument, bare statement),
and a working `(add)(4, 5)` == 9.

---

## Root cause: a one-token gate, and the boundary was narrower than filed

The ticket said "assignment RHS drops the arguments, argument position works".
That framing was wrong — position has nothing to do with it. Varying the
RECEIVER instead of the position gives the real rule:

```python
f = add
(f)(4, 5)        # 9    — works
(g)(3, 4)        # 12   — works (g = lambda)
(k.m)(1)         # 2    — works
(lst[0])(1, 1)   # 2    — works
(add)(4, 5)      # 5831005 — a raw code address
(3 + 4)(1)       # 7
(n)(1)           # 7
```

Every working case is **tyVariant**; every broken one is not. `parser.inc`'s
dynamic-call loop was gated `IntToTypeKind(ASTTk[CurASTNode]) = tyVariant`, so a
non-variant factor fell out of the loop with the `(` unclaimed — and nothing
downstream claimed it either, so the argument list was **discarded** and the
expression evaluated to the callee. The two "positions" in the original ticket
were just two receivers: `(f)` in an argument (variant, worked) versus `(add)`
on an RHS (a bare proc name, tyPointer, dropped).

## The fix

Widen the gate to everything except a user-class instance, which the loop right
below claims for the `__call__` protocol (it needs the receiver, not a boxed
handle). A pylib CONTAINER stays in — that is how `(1, 2)(3)` becomes CPython's
TypeError instead of printing the tuple.

No boxing code was needed: `pyvar_callv<n>` declares `const cb: Variant`, so the
ordinary argument coercion boxes the callee.

**This is only safe because of the tag that landed an hour earlier.** Widening
this loop routes a non-variant callee through the runtime guard, and until
`feature-nilpy-a-callable-value-needs-its-own-variant-tag` a boxed code address
and a boxed integer both wore VT_INT64 — so the guard would have had to let
`(3 + 4)(1)` through to an indirect jump to address 7. The wrong answer would
have changed from "silently 7" to "segfault". With VT_CALLABLE the two are
distinguishable, so a real callable dispatches and everything else raises.

Filed as N; the edit is in the SHARED `parser.inc`, so it carries Track A
file-ownership (sole-A confirmed for this session). It is gated on `PyExprMode`
throughout, so Pascal and C are untouched by construction.

## Verification

`test_nilpy_postfix_after_parens` extended rather than a new file — it is the
sibling that already covered the two grouped-callable cases that WORKED
(`(lambda ...)(9, 4)` and `(f)(9, 4)`), which is exactly why the gap was
invisible: the test proved the variant arm and nothing else.

Added: a bare proc name, a doubly-parenthesised one, a bound method, a list
element, a dict value, a `__call__` instance — and eight non-callable arms
(int expression, int variable, str, list, tuple, dict, float, an instance
WITHOUT `__call__`) each asserting CPython's TypeError.

- Byte-identical to CPython's own stdout for the whole file.
- On `pinned` it does not even COMPILE (`(add)(4, 5)` inside a `print` is
  "unexpected token" there), so the test cannot pass by accident.
- `tools/gate.sh quick` GREEN, self-host fixedpoint, `make test-nilpy` green.

## Log
- 2026-08-11 — resolved, commit PENDING-COMMIT.
