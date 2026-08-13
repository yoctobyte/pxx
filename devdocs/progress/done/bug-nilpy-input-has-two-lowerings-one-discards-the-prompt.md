---
prio: 35
track: N
blocked-by: []
---

# `input` has TWO lowerings in parser.inc and one silently discards the prompt

- **Type:** bug (latent — no shape found that reaches the broken arm)
- **Track:** N (Nil-Python semantics; the edit lands in the SHARED `parser.inc`,
  so it is Track A file-ownership and needs the sole-A guard)
- **Status:** done
- **Owner:** claude-A-N

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

## DONE 2026-08-13 — one builder, both entry points

The ticket's own prescription was "delete one arm, not teach the broken one
about prompts", and blocked itself on proving which arm is dead. That proof is
not needed: the two arms differ only in their GUARD, which is real in both cases
— the builtin-chain arm requires that nothing else is called `input` (so a
parameter may shadow the builtin, songformatter's `int_to_roman(input)`), and
the PyExprMode arm requires no user proc of that name. What was duplicated was
the LOWERING, and that is what is now singular.

`PyParseInputCall` (pyparser.inc) is the one builder: `pyinput()` with no
argument, `pyinput_p(prompt)` with one — the correct arm's behaviour, verbatim.
Both intercepts in `parser.inc` now call it and keep their own guard. There is
no second lowering left to drift, which is what
`normalise-dont-special-case.md` asks for; deleting a guard nothing has shown to
be dead would have been the riskier reading of it.

The discarded prompt is therefore gone whether or not the first arm is
reachable — the question the ticket parked on stops mattering.

### Verified

Six shapes with a prompt diffed against CPython (plain assignment, inside
`len(...)`, as a user function's argument, in a list literal, as a ternary arm,
and the no-argument form), plus `def int_to_roman(input)` — the shadowing case
the first arm's guard exists for — all matching. The three existing `input`
tests re-run: `test_nilpy_input_builtin` (which already asserts the prompt is
written), `test_nilpy_input_eof_raises`, `test_nilpy_select_stdin_ready`.

Gate: `make compiler/pascal26` fixedpoint + `tools/gate.sh quick` GREEN.

## Log
- 2026-08-13 — resolved, commit b482008cc.
