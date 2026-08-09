---
track: N
prio: 55
type: bug
status: done
owner: agent-AN
---

# `return` inside a `with` does not run `__exit__`

```python
class C:
    def __init__(self, n):
        self.n = n
    def __enter__(self):
        return self
    def __exit__(self, a, b, c):
        print("exit", self.n)
        return False

def one():
    with C(1) as a:
        return a.n

print("ret", one())
```

```
CPython:  exit 1 / ret 1
pxx:      ret 1
```

`__exit__` never runs. **Silent** — the value returned is correct, so nothing
looks wrong; what is lost is the release. That is a lock never released, a
transaction never rolled back, a file never closed, all with no diagnostic, on
the single most common early-exit path there is.

Confirmed pre-existing (`stable_linux_amd64/default/pinned` behaves the same)
and NOT specific to multiple managers — a single-manager `with` does it too.

## The source says otherwise, which is the useful part

`PyParseWithTail`'s own comment reads:

> try/finally so `__exit__` runs on the exception path and on break/return too.

The exception path is correct — measured, an exception inside the body does run
`__exit__`, including for several managers in the right order. So the
`AN_TRY_FINALLY` lowering is right and `return` is the arm that escapes it: the
return presumably unwinds past the finally rather than through it. `break` and
`continue` out of a loop inside a `with` should be measured at the same time —
the comment claims them together and only one of the three was verified.

## Gate

`make test-nilpy` + self-host byte-identical, CPython-diffed over `return` from
inside a `with` (single and multiple managers), `break` and `continue` out of a
loop inside one, a bare fall-off-the-end, an exception (the case that already
works, as a control), and a `return` inside a `try` inside a `with`.

## FIXED 2026-08-09 — one line; the diagnosis is the part worth keeping

### The boundary is wider than reported

Measured first, and `return` was not alone:

| way out of the `with` body | `__exit__` ran? |
| --- | --- |
| fall off the end | yes |
| exception | yes |
| **`return`** | **no** |
| **`break`** | **no** |
| **`continue`** | **no** |

The ticket asked for `break`/`continue` to be measured "at the same time"
because the source comment claimed all three. They were both broken.

### The ticket's hypothesis was wrong, and checking it is what found the cause

The ticket reasoned "the return presumably unwinds past the finally". Two
controls killed that:

- **Pascal** `try/finally` with `Exit` / `Break` / `Continue` — all correct. So
  the unwinder is fine and this is not Track A.
- **NilPy's own** `try/finally` with a `return` inside — also correct. So
  `AN_TRY_FINALLY` is fine, and the `with` lowering that builds one is not.

Same node, same unwinder, opposite behaviour: the difference had to be in what
was hung off the node.

### Cause — a statement built as an expression

`PXXDBG=a.ir` on both spellings, side by side:

```
try/finally (works):   6:  call a=1306  ival=1     <- statement root
                       7:  block a=6
with      (broken):   58:  call a=1307  ival=0     <- a VALUE
```

`PyCallMeth3` yields an expression node, and the IR lowering emits an unused
value without marking it a statement root — so the fall-through/return copy of
the finally body was **pruned as dead**. A statement-level `finally:` suite is an
AN_SEQ, which is exactly why the identical program written with `try/finally`
always worked.

The fix is `ASTRight[node] := PySeqAppend(-1, exitNode)`.

### Why only the exception arm ever looked right

The landing pad lowers ITS copy of the finally body as a statement root
regardless of what the frontend handed it. So the one arm anybody measured was
correct for a reason that had nothing to do with the other four — and it made
the whole lowering look innocent. Worth remembering as a shape: **an arm that
works for its own reasons is not evidence about the arms beside it.**

### Gate

- `test/test_nilpy_with_early_exit_runs_exit.npy` — return (single AND multiple
  managers, checking the m2-before-m1 unwind order), `break`, `continue`,
  fall-through, the exception path kept as an explicit CONTROL, `return` inside a
  `try` inside a `with`, and `return` out of a loop inside a `with`. Expectation
  is CPython's own output; matches byte for byte. Wired into `make test-nilpy`.
- `make compiler/pascal26` — self-host fixedpoint converged, byte-identical.
- `tools/gate.sh quick` — GREEN.

## Log
- 2026-08-09 — resolved, commit PENDING-COMMIT.
