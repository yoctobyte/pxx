---
slug: bug-a-the-nilpy-arms-in-the-shared-call-loop-are-dead-and-guarded-by-the-wrong-flag
track: A
prio: 40
type: bug
status: new
owner: ""
blocked-by: []
summary: "MEASURED, not reasoned. The NilPy star/kwargs arms inside the SHARED call-argument loop (pasparser_expr.inc ~7730-7955) never fire for NilPy source, because NilPy source goes through PyParseFactorCore's own copy of that loop. They are guarded by `isNilPy` (true for the whole compilation) where the question is `PyExprMode` (is THIS unit Python) -- and with PyExprMode true the code is unreachable anyway, ParseFactorCore having Exited to PyParseFactorCore 7000 lines earlier. So they are evaluated ~3000 times per NilPy compile while parsing PASCAL library units, where a `*` token and a `name=` keyword cannot occur. Four star arms never fired in six programs; the keyword-overload retarget ran ~3000 times and changed procIdx ZERO times, including on the exact call its own bug ticket cites. DELETED 2026-08-31 in pasparser_expr.inc: nine arms gone, all 18 test programs (compiler.pas included) emit BYTE-IDENTICAL binaries, carve metric 232 -> 214. REMAINING: pasparser_stmt.inc:~6100-6200 carries the same twin and has NOT been touched."
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

## Still open

`pasparser_stmt.inc`'s twin has the same arms and has NOT been touched. Its
`PyPackStarArgs`/`PyBindKwArgs` pair is at `:6155-6156`. It needs the same
treatment and the same evidence -- and note that the structural argument in
step 1 above is about `ParseFactorCore` specifically, so it does **not** transfer
to the statement loop for free. Establish the equivalent entry condition there
before assuming the twin is dead.

If they are dead, the guard that should have been there is `PyExprMode`, and the
reason nobody noticed is that `isNilPy` reads as *"this is Python"* when it means
*"this compilation started from a .npy file"*. [[the-name-is-not-the-thing]].

## Related

- [[refactor-a-carve-the-nilpy-arms-out-of-the-shared-pascal-argument-loops]] — 19 of its sites are these
- `bug-nilpy-keyword-arg-vs-overload-set` — the ticket whose example does not reach this code
