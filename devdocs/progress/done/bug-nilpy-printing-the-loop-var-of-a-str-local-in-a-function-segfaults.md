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

## What the crash actually is — an UNINITIALISED managed local being released

CORRECTION to an earlier reading in this ticket: `rip = 0x400181` looked like a
jump into the ELF header, i.e. a bad call target. Disassembling there shows it
is nothing of the sort — it is the managed-string RELEASE helper, which simply
lives at a low address in this ELF layout:

```
=> 0x400181:  decq   -0x10(%rax)     ; refcount at [handle-16]
   0x400185:  jne    0x4001ab
   0x400187:  sub    $0x10,%rax      ; ...else fall through to free
   0x40018b:  push   %rsi
```

So the fault is a DATA dereference with a garbage `%rax`: a managed string is
being released through an uninitialised handle. `PXXDBG=n.locals` shows both
`s` and `ch` as tk=23 managed locals, and the loop desugar adds a managed
hidden local (`__py_c_N`) as well.

That puts it squarely in the recorded zero-init landmine family
(`project_nilpy_method_result_not_zeroed_landmine`,
`project_nilpy_object_reclamation_arc`'s "mid-body-local zero-init landmine"):
a managed slot that the prologue does not zero, so the first store's release of
the "previous" value dereferences whatever the frame happened to contain.

It is frame-layout dependent, which is why every neighbouring shape works —
adding ANY other local shifts the slot onto bytes that happen to be zero:

| change | pxx |
| --- | --- |
| the repro | **SIGSEGV** |
| add `t2 = "cd"` (a second managed local) | correct ✓ |
| add `z = 1` (an int local) anywhere in the body | correct ✓ |
| iterate a LIST local instead | correct ✓ |
| iterate a str PARAMETER instead | correct ✓ |
| `while i < len(s)` instead of `for ch in s` | correct ✓ |

`PXXDBG=a.ir:f` confirms the crashing and working variants are structurally
IDENTICAL apart from the extra `store_sym`, so the IR is right and the defect is
in what the prologue zero-initialises for this frame shape.

Next step: `-dPXX_HEAP_DEBUG` makes freed bytes `$DD` rather than a recycled
neighbour's, which should show whether the handle is stale-freed or never
written; then compare the two prologues under `-g` in gdb.

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

## Log
- 2026-07-30 — resolved, commit f81334384.
