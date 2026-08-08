---
prio: 35
track: N
blocked-by: []
---

# `input` has TWO lowerings in parser.inc and one silently discards the prompt

- **Type:** bug (latent — no shape found that reaches the broken arm)
- **Track:** N (Nil-Python semantics; the edit lands in the SHARED `parser.inc`,
  so it is Track A file-ownership and needs the sole-A guard)
- **Status:** backlog — found 2026-08-08 while fixing [[regression-test-uforth-00]]
- **Owner:** —

## The two arms

| site | guard | prompt |
| --- | --- | --- |
| `parser.inc` ~10745 | `isNilPy and (name = 'input') and (FindSym(name) < 0)` | **parsed and DISCARDED**, always lowers to `pyinput` |
| `parser.inc` ~12305 | `PyExprMode and CaseEqual(name, 'input') and (procIdx < 0)` | lowers to `pyinput_p`, which **writes it** |

CPython's `input(prompt)` writes the prompt to stdout without a newline. That is
observable output, so the first arm is a silent wrong answer for any program
that prompts — the exact class of divergence a NilPy program can see (upward
compatibility: code that works on CPython must work here).

The first arm's comment justifies the discard with "its only effect in Python is
a stdout write; uforth's REPL prompt is cosmetic". Cosmetic to uforth, but the
differential harness compares stdout byte for byte, and any other program's
prompt is not cosmetic at all.

## Reachability — probed, not reasoned

Five syntactic positions were compiled and diffed against CPython at
`ba1cc9f64`+fix, all with a prompt: plain assignment, inside `len(...)`, as a
user function's argument, inside a list literal, and as a ternary arm. **All
five matched CPython** — i.e. every one took the `PyExprMode` arm. So the bug is
latent today; the first arm is either dead or reached only by a shape not yet
found.

That is exactly why it is filed and not patched: `normalise-dont-special-case`'s
rule is that the second path is the one that stays broken, and a second parser
for one construct is the smell itself. The fix is to **delete one arm**, not to
teach the broken one about prompts — but proving which is dead needs a
`PXXDBG`/instrumented run rather than another round of guessing.

## Suggested approach

1. Instrument arm 10745 (a temporary `WriteLn(ErrOutput, ...)`) and run the
   NilPy suite plus the uforth corpus to see whether anything reaches it.
2. If nothing does: delete it, keep the `PyExprMode` arm, gate.
3. If something does: that shape is a live prompt-dropping bug — promote this
   ticket out of "latent" and make the arm lower to `pyinput_p` on the way to
   collapsing the two.

Either way both arms must keep the `FindSym`/`procIdx` guard: a user parameter
or `def` named `input` legitimately shadows the builtin (songformatter's
`int_to_roman(input)` is the recorded case).

## Related
[[regression-test-uforth-00]] (the EOFError fix that surfaced this),
`test/test_nilpy_input_builtin.npy`, `test/test_nilpy_input_eof_raises.npy`
