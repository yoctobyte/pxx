---
track: N
summary: "NilPy: support break / continue in while (and for) loops — v1 subset lacks them"
type: feature
prio: 40
---

# NilPy `break` / `continue`

- **Type:** feature (Track N — Nil-Python frontend; `pyparser.inc` loop lowering).
- **Status:** done
- **Found:** 2026-07-17, building the NilPy Tk poll loop for the IDE demo — a natural
  `while ...: if ...: break` did not compile.
- **Owner:** claude-A-N

## Gap

`break` (and almost certainly `continue`) are not in the NilPy v1 subset:

```python
def main() -> None:
    i = 0
    while i < 10:
        if i == 3:
            break        # pascal26: error: expected expression
        i = i + 1
```

`break` → `pascal26:N: error: expected expression`. Both are core Python control flow;
their absence forces flag-variable workarounds (`running = 1; while running == 1: ...
running = 0`) that are un-Pythonic and error-prone.

## Scope

- Lower `break` / `continue` inside `while` and `for` to the IR's existing loop-exit /
  loop-continue targets (the Pascal frontend already has these — reuse the shared IR loop
  labels, no new IR op needed → pure Track N frontend work).
- Respect nesting: `break` targets the innermost loop only.
- Reject `break`/`continue` outside a loop with a clear diagnostic.

## Acceptance

- The snippet above compiles and prints `0 1 2` (loop exits at 3).
- `continue` skips to the next iteration.
- A `test/test_nilpy_break_continue.npy` regression; `make test-nilpy` green.

## Note

Found alongside a NilPy `str + str` concatenation gap (also rejected) — that likely
belongs to [[feature-nilpy-collections-and-string-methods]]; verify and fold there rather
than duplicating.

## Measured satisfied 2026-08-09 (by Track B, pinned v252)

```python
for i in range(5):          while i < 6:
    if i == 1: continue         i = i + 1
    if i == 3: break            if i == 2: continue
    print(i)                    if i == 5: break
                                n = n + i
```
Both loop kinds accept `break` and `continue` and produce CPython's answers
(`0`, and `n = 8`). Evidence only — Track N owns closing this. Found while
sweeping Track B's blocked tickets for stale blockers;
[[feature-demo-nilpy-ide]] listed this as a blocker.

## CLOSED 2026-08-13 — already implemented; the missing piece was the test

Nothing to build. `break` and `continue` work in both loop kinds, and the
ticket's other two scope lines hold too: nesting targets the innermost loop, and
outside a loop each is refused by name (`break outside loop` /
`continue outside loop`) rather than by a parse error.

Swept beyond the acceptance, all matching CPython: nested for and nested while,
break and continue inside a `def`, `while True` whose only exit is the break, an
exit crossing a `try`/`finally` (the finally still runs), `continue` inside
`try`/`except`, and **for/else** — where the else must run only when no break
fired, which is the row a naive lowering gets wrong.

`test/test_nilpy_break_continue.{npy,expected}` (`.expected` from CPython),
wired into `test-nilpy`, so a later loop-lowering change cannot quietly take
this away. Gate: self-host fixedpoint + `gate.sh quick` GREEN.

## Log
- 2026-08-13 — resolved, commit f1192065b.
