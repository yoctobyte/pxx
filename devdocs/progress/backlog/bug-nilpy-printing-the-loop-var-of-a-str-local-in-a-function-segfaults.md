---
track: N
prio: 75
type: bug
---

# `def f(): s = "ab"; for ch in s: print(ch)` SEGFAULTS

```python
def f():
    s = "ab"
    for ch in s:
        print(ch)
f()
# CPython: a / b     pxx: SIGSEGV
```

## The shape is very narrow — and every neighbour works

| variant | pxx |
| --- | --- |
| **the program above** | **SIGSEGV** |
| the same loop with `print` removed (count only) | correct ✓ |
| `for ch in "ab":` — literal inline, no local | correct ✓ |
| the same three lines at TOP LEVEL (not in a def) | correct ✓ |
| `def f(s):` — the string as a PARAMETER, then iterate and print | correct ✓ |
| `def f(s):` param, `ord(ch)` in the body | correct ✓ |
| `def f(s):` param, building a string from `ch` | correct ✓ |

So it needs all three of: inside a function, iterating a str LOCAL (a named
variable, not a literal), and using the loop variable in `print`.

Found via a caesar-cipher program, which is why it matters: `for ch in s` over a
local is how you write almost any string-processing helper.

## Provenance — bisected, NOT from this session's work

Bisected by rebuilding the compiler at successive commits and running the
repro:

| built at | result |
| --- | --- |
| the 2026-07-27 stable BINARY | prints `a b` ✓ |
| `acab84ed8` — this session's starting commit, before any change of mine | **SIGSEGV** |
| `7e90f99e3` (first change of the session) | SIGSEGV |
| `943f590c7` (mixed-type operands) | SIGSEGV |
| current HEAD | SIGSEGV |

The session's starting commit already crashes, so none of this session's fixes
introduced it. The 07-27 stable BINARY differs because it compiles against its
own frozen `stable_linux_amd64/default/builtin/`, not the working tree's
`compiler/builtin/` — so the regression window is between 2026-07-27 and
`acab84ed8`, in the builtin/pylib or frontend work landed in that period.

Worth bisecting that window properly with `tools/bisect`-style rebuilds rather
than guessing; the window is small and the repro is a five-line file.

## Note

`make test-nilpy` is green across all 230 `.npy` tests, so this shape is not
covered anywhere in the suite — worth adding regardless of who fixes it.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` with the table above
against CPython's own output. Keep the neighbour rows: they are what makes the
shape identifiable if it regresses again.
