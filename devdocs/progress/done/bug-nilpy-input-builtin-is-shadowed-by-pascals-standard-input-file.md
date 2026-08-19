---
track: N
prio: 45
type: bug
summary: "`input()` never reached a call lowering — `Input` is a standard Pascal identifier (the text file), so `line = input()` bound the file variable and the failure surfaced later and unrecognisably at the first USE of the result"
commit: 744fb89bb
---

# `input()` is shadowed by Pascal's standard `Input` text file

Found 2026-08-07, the second uforth compile blocker after
[[bug-nilpy-to-bytes-on-a-variant-receiver-does-not-compile]].

```python
line = input()
print("got:" + line)
```

```
pascal26: error: Nil Python: expected newline after statement
  near:  got:  line   >>>  unit builtinheap
```

## Why it was hard to place

`line = input()` on its own **compiles**. So does `print(line)` after it. Only a
use that needs the value to be a STRING fails — `len(line)`, `"got:" + line` —
and the error names a position **inside builtinheap's source**, which is not a
file the programmer wrote. Nothing points at `input`.

The cause: `Input` is a standard Pascal identifier — the text file. The name
resolved to that, so `line` was bound to a file variable and the intrinsic was
never consulted. Meanwhile `pyinput()` (pylib's real implementation, spelled
with the prefix precisely because `input` is taken) worked fine, which is the
tell.

## Fix

An explicit arm in the builtin-name dispatch (`parser.inc`, beside Ord/Chr),
gated on `PyExprMode` so **Pascal's `Input` is untouched**, and on `procIdx < 0`
so a NilPy `def input()` of the program's own still wins:

- `input()` → `pyinput`
- `input(prompt)` → new `pyinput_p(prompt)`, which writes the prompt with
  `Write` (no newline, as CPython does) and then reads.

`pyinput_p` was added rather than leaving the prompt form unsupported — a
half-wired builtin is the thing that made this hard to diagnose in the first
place. It carries a note that it relies on this RTL's `Write` going straight out
(there is no `Flush` here), so if stdout ever becomes buffered that is the line
to fix.

## Measured

`test/test_nilpy_input_builtin.npy`, stdin-driven from the Makefile like
`test_eof_stdin.pas`, **byte-identical to CPython** across both forms, `len`,
`.upper()`, concatenation, indexing and comparison — i.e. the result is a real
string, not a file handle.

## uforth

With this and the `to_bytes` fix, **uforth.py COMPILES** — it had never compiled
before. It now segfaults at run time, which is new territory rather than a
regression, and is filed as [[bug-nilpy-uforth-compiles-but-segfaults-at-runtime]].
So `make test-uforth` is still red, and the "uforth still green" gate on
[[bug-nilpy-pyeval-fallback-still-binds-host-kwargs-by-position]] is still not
readable — but for a later reason, and the two compile blockers are gone.

## Gate

`make fpc-check` byte-identical, self-host fixedpoint, `tools/gate.sh quick`
GREEN.
