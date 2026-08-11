---
track: N
prio: 60
type: bug
summary: "`x = (expr)(args)` parses as just `(expr)` — the argument list is DISCARDED with no diagnostic, so `(add)(4, 5)` answers a raw code address instead of 9. Silent wrong value on a form CPython accepts."
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
