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

## The trigger is the BODY SHAPE, not the loop variable

Refined after the first pass: the loop variable is irrelevant. `print` of a
CONSTANT crashes just as well, and any ASSIGNMENT anywhere in the body cures it.

| loop body (inside a def, iterating a str local) | pxx |
| --- | --- |
| `print(ch)` | **SIGSEGV** |
| `print("x")` — the loop variable is not even used | **SIGSEGV** |
| `print("x")` then `print("y")` | **SIGSEGV** |
| `print(ord(ch))` | **SIGSEGV** |
| `z = 1` then `print("x")` | correct ✓ |
| `print("x")` then `z = 1` | correct ✓ |
| `c2 = ch` then `print(c2)` | correct ✓ |
| `out = out + ch` (no print at all) | correct ✓ |

So: a loop body consisting ONLY of print statements. One assignment, before or
after, in any position, makes it work.

## What the crash actually is

`rip = 0x400181` — a jump to a bogus address inside the ELF header region, so
this is a bad CALL TARGET, not a data dereference. Compare the recorded
landmine `project_bodyless_procaddr_links_to_entry_minus_one`: "@proc on a
BODYLESS routine links as entry-1 -> plausible ptr, crashes far away".

`PXXDBG=n.locals` shows both `s` and `ch` as tk=23 (managed string) locals, and
`PXXDBG=a.ir:f` shows the two variants are structurally identical apart from
the extra `store_sym z` — same calls, same order, same blocks. Only the frame
layout differs, which is why adding any local shifts it out of the failure.

Together those point at the function's prologue/epilogue or its local-init
sequence rather than at the loop desugar itself: the IR is right and something
below it is emitting or linking a wrong address for this frame shape.

Next step for whoever picks it up: build with `-g` and single-step the prologue
(`make pxx-debug`, `source tools/pxx-gdb.py`), and compare the emitted prologue
of the two variants — the difference should be visible directly, since the IR
is identical.

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
