---
slug: bug-a-the-nilpy-arms-in-the-shared-call-loop-are-dead-and-guarded-by-the-wrong-flag
track: A
prio: 40
type: bug
status: done
owner: ""
blocked-by: []
summary: "MEASURED, not reasoned. The NilPy star/kwargs arms inside the SHARED call-argument loop (pasparser_expr.inc ~7730-7955) never fire for NilPy source, because NilPy source goes through PyParseFactorCore's own copy of that loop. They are guarded by `isNilPy` (true for the whole compilation) where the question is `PyExprMode` (is THIS unit Python) -- and with PyExprMode true the code is unreachable anyway, ParseFactorCore having Exited to PyParseFactorCore 7000 lines earlier. So they are evaluated ~3000 times per NilPy compile while parsing PASCAL library units, where a `*` token and a `name=` keyword cannot occur. Four star arms never fired in six programs; the keyword-overload retarget ran ~3000 times and changed procIdx ZERO times, including on the exact call its own bug ticket cites. DELETED 2026-08-31 in pasparser_expr.inc: nine arms gone, all 18 test programs (compiler.pas included) emit BYTE-IDENTICAL binaries, carve metric 232 -> 214. The pasparser_stmt.inc twin (four arms) followed the same day on the same evidence: metric 214 -> 209, 15/15 Pascal programs and 5 NilPy programs byte-identical. BOTH LOOPS ARE NOW CLEAR."
---

# The NilPy arms in the shared call-argument loop are dead, and guarded by the wrong flag

- **Found:** 2026-08-31 by frankA, while triaging
  [[refactor-a-carve-the-nilpy-arms-out-of-the-shared-pascal-argument-loops]].
  Filed rather than fixed at the time, on a premise that was WRONG -- see the
  correction under "What to do" below.

## The structure

The call-argument loop exists **three times**:

| where | reached when |
| --- | --- |
| `pasparser_expr.inc:~7730` | expression position, shared |
| `pasparser_stmt.inc:~6100` | statement position, shared (its own comment says *"see the twin site"*) |
| `pyparser.inc:~48960`, inside `PyParseFactorCore` | NilPy's own |

`ParseFactorCore` Exits to `PyParseFactorCore` at `pasparser_expr.inc:521`
whenever `PyExprMode`. **So the shared loop at 7730 is only ever reached with
`PyExprMode` FALSE** — which, per `defs.inc:4199` and `pasparser_proc.inc:4697`,
means *a Pascal unit pulled in by a NilPy program*. Pascal has neither `*args`
nor `name=` call syntax.

## Measured

A probe on each arm, six programs (`zip_star_and_n_way`, `lazy_map_filter`,
`lib_mimic_string_template`, `unbound_method_keyword_args`, `a_unicode_identifier`,
and a two-line `html.escape(s, quote=False)`):

| arm | fired |
| --- | --- |
| `PyStarIterableForm` (`f(*xs)` first-arg) | **0** |
| star-forward into fixed slots | **0** |
| `PyStarUnpackProcArgs` (`f(1, *xs)`) | **0** |
| star-splice into a collecting callee | **0** |
| `PyPromoteProcOverloadByKwAt` | ran **2843-3247** times, **retargeted 0** |
| `PyFixCallableTypeArgs` | ran 2843-3247 times (unconditional under `isNilPy`; whether it *does* anything is unmeasured) |

**The zero is not vacuous**: the enclosing `if isNilPy` was reached ~3000 times
per compile, so the population is large and the arms simply never applied. Every
hit came from a Pascal unit (`pyvartag`, `pyvarobj`, `pystr_of`, `IsOp`,
`MakeStr`, `SlotInt` — unit indices 56/61/435/442), none from NilPy source.

**And the retarget arm was tested against its own ticket's example.**
`bug-nilpy-keyword-arg-vs-overload-set` cites `html.escape(s, quote=False)`. That
program compiles, runs, matches CPython — and retargets **zero** times here,
because the call is parsed by `PyParseFactorCore`'s loop, which has its own
`PyBindKwArgs` (`pyparser.inc:49026`). The fix landed in the twin, and the copy
here was never the one doing the work.

## What was done, and what the evidence actually was

The fix was **deletion**, not a hook: the arms cost ~3000 no-op calls per NilPy
compile and closed 19 of the carve's remaining sites for free. But
*"never fired in six programs"* is a sample, so it was never what blessed it.

**Step 1 as originally written said "run the full NilPy tier". That was the
widening trap CLAUDE.md names, near verbatim, and it is struck.** Corrected by
frankS, 2026-08-31: the full tier is not a gate anyone owes before landing --
breadth is Track T's, asynchronously, and a lane that widens its own gate spends
the machine that produces T's median-8 sampling. It is also unrunnable here by
construction (`no-full-suite.sh` denies it to this lane), so the step as written
made the ticket permanently unactionable by its own author. Asking a peer to run
it instead would have been permission laundering, which is how this was caught.

The honest bar, and what was actually run:

1. **A structural argument, not a sample.** `ParseFactorCore` opens at
   `pasparser_expr.inc:519` with an unconditional
   `if PyExprMode then begin PyParseFactorCore; Exit; end;` -- so every statement
   after :523 runs only with `PyExprMode = False`. The arms cannot fire for
   Python source; the six-program sample was never the load-bearing evidence.
2. **`PyFixCallableTypeArgs` answered on its own terms**, as the old step 2 asked.
   It is the one arm guarded by bare `isNilPy`, so it always *runs* -- but its
   first line is `if not PyExprMode then Exit;`, so it never *acts*. "It runs" and
   "it does nothing" are different claims and this is the second one.
3. **Byte-identity as the verdict.** Compilers built from the before- and
   after-sources emit byte-identical binaries for all 18 test programs,
   `compiler.pas` included.
4. **`.npy` canaries for the exact shapes, watched failing.**
   `test/quick_canary_nilpy.npy` gained checks 28-36 covering `f(*xs)`,
   `f(1,*xs)`, splice into a `*args` callee, a bare genexpr argument,
   `dict(a=1)`, `dict(**m)` and a callable in a callback slot -- diffed against
   CPython, and each proved able to fail by disabling the surviving
   `pyparser.inc` arm as a positive control.

**What that control caught, and it is the reason the step matters:** the first
version of the canary tested `collect(*[5, 6, 7])` -- a LITERAL operand -- and
passed 35/35 with the splice arm disabled. A literal star operand and a variable
one **do not take the same path**; every variable form (`collect(*xs)`,
`collect(1, *xs)`, `mix(2, *xs)`, `collect(*xs, *xs)`) is rejected with the arm
gone, while the literal form still compiles and answers 18. A literal-only check
watches nothing. The canary now carries both shapes deliberately, with that
recorded inline.

## The twin: done, 2026-08-31

`pasparser_stmt.inc`'s four arms (`:6119` keyword-overload retarget, `:6160`
`PyFixCallableTypeArgs`, `:6189`/`:6199` `PyFixIterableArgs`) are deleted.

**The structural argument had to be rebuilt, not reused** — this ticket warned it
would, and it was right. `ParseStatementAST` has no `PyExprMode` early exit, so
the `ParseFactorCore` argument does not transfer. What replaced it:

- `pyparser.inc` has its own statement parser (`PyParseStatement`, `:26778`) and
  **never calls `ParseStatementAST`** — its three mentions of the name are all
  comments.
- Measured rather than read: a probe on `ParseStatementAST` entry printed
  **20603 entries on the quick canary, every one with `PyExprMode = False`, and
  not one True.** The positive control is the count itself — an instrument
  printing 20603 lines is not a silent one.
- Each arm probed individually: all four run ~1000 times per NilPy compile
  (against the Pascal library units), and the retarget's `procIdx` **changed
  zero times**. `PyFixCallableTypeArgs` and `PyFixIterableArgs` both open with
  `if not PyExprMode then Exit;`.
- The retarget has no such guard, so it got a language-level argument instead:
  it fires on `tkIdent` followed by `tkAssign` at paren depth 1, and in the
  Pascal lexer `tkAssign` is `:=` only (`=` lexes as `tkEq`, `lexer.inc:2879`).
  `:=` is not an expression operator, so the shape cannot occur in a Pascal
  argument list.
- Byte-identity: 15 Pascal programs identical, 3 more producing identical
  diagnostics, and 5 NilPy programs identical — including a purpose-built
  **statement-position** probe (`kwtake(1, b=2)` and
  `html.escape(s, quote=False)` as bare call statements, not as arguments to
  `print`, which is what the expression loop would have caught instead).

**The statement probe was watched failing**, by disabling the surviving
`PyPromoteProcOverloadByKwAt` in `pyparser.inc`: it then rejects the `quote=False`
row with the overload-set diagnostic from that arm's own bug ticket. So the probe
reaches the mechanism.

**The other control returned a null, and that null is a separate ticket.**
Disabling `PyFixIterableArgs` entirely changed nothing anywhere — not in this
probe, not in the corpus, and not in `test/test_nilpy_user_iterable_in_builtins.npy`,
which emits a byte-identical binary with the function switched off. That is not
evidence about this deletion (these arms were already inert by their own first
line); it is evidence the *surviving* mechanism is uncovered or superseded:
[[bug-n-pyfixiterableargs-is-inert-its-own-test-passes-with-it-disabled]].

## Still open

Nothing in this ticket. The remaining NilPy references in the shared Pascal
parser are the carve's other regions —
[[refactor-a-carve-the-nilpy-arms-out-of-the-shared-pascal-argument-loops]],
metric at 209.
## Related

- [[refactor-a-carve-the-nilpy-arms-out-of-the-shared-pascal-argument-loops]] — 19 of its sites are these
- `bug-nilpy-keyword-arg-vs-overload-set` — the ticket whose example does not reach this code

## Log
- 2026-08-31 — resolved, commit 23c4552af.
