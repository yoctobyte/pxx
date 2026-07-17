---
summary: "NilPy: support break / continue in while (and for) loops — v1 subset lacks them"
type: feature
prio: 40
---

# NilPy `break` / `continue`

- **Type:** feature (Track N — Nil-Python frontend; `pyparser.inc` loop lowering).
- **Status:** backlog
- **Found:** 2026-07-17, building the NilPy Tk poll loop for the IDE demo — a natural
  `while ...: if ...: break` did not compile.
- **Owner:** —

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
