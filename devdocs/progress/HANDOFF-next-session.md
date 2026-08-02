# Handoff — 2026-08-01, NilPy bughunt (tracks A+N+P+C)

Supersedes the 2026-07-05 Track C+B+A handoff, archived alongside as
`HANDOFF-2026-07-05-track-CBA.md` (its cross-target debug tactics are still
good; its "no Nil-Python until C is stable" directive is superseded).

Paste everything below the line as the opening prompt for a fresh session.

---

Continue on tracks **A+N+P+C**. You are sole-A. Work on `master`, commit small,
push often.

## Cadence — the user asked for this explicitly

**Go fast; let Track T find regressions. Quick checks only.** Per fix:

1. `make` — the self-host loop must converge.
2. **FPC seed build, but only if you ADDED or MOVED a routine** (~30s):
   `rm -rf /tmp/fpcu && mkdir -p /tmp/fpcu && fpc -O2 -Tlinux -Px86_64 -FU/tmp/fpcu -o/tmp/pxx-fpc compiler/compiler.pas`
   Neither `make` nor `gate.sh` ever invokes FPC, so a declaration-order break
   (PXX is lax, FPC is strict) is structurally invisible locally. I shipped one
   this session; T caught it.
3. Self-host fixedpoint from the pinned seed (A==B==C) + `tools/testmgr.py --tier quick`.
4. Push.

Do **not** run `make test-nilpy` (~9 min) per fix.
`git fetch` **before** `tools/twatch.py --status` — it reads the LOCAL `tstate/`
dir, so without a fetch it reports your own checkout's staleness. That gave a
false "T is DOWN" this session.
Never pipe a backgrounded `make`/gate to `tail` — it masks the exit status.

## State

HEAD `eeae1e4a3`, tree clean, all pushed, T is UP.

**One unverified thing:** a `make test-nilpy` was still running at session end.
Re-run it once. It had already passed everything through
`test_nilpy_comprehension_scope`. If something is red, the likeliest cause is
another assertion encoding OLD compile-error behaviour that is now a runtime
raise — exactly what `test_nilpy_list_plus_nonlist_fail` was.

## Landed this session — 11 NilPy fixes, each CPython-diffed with a test

ordering dunders · `__bool__`/`__len__` truthiness · list ordering (was comparing
heap ADDRESSES, ignoring contents) · `__ne__` · bitwise/shift (was SIGSEGV) ·
`__floordiv__`/`__mod__`/`__pow__` · all seven reflected dunders · undefined
operand pairs now raise a catchable TypeError instead of aborting the build ·
`__abs__`/`__invert__`/`__index__` · `with` context-manager protocol ·
`b.decode()` (was SIGSEGV). Plus the uses-leak instrument fix (Track A) and
`PXXDBG=n.locals` now dumping the MODULE constraint table.

Also closed by measurement: the uses-transitivity "campaign" is not one —
35 leak pairs across all 934 test files (was reported as 81 from 80 files), and
the "hundreds of files need `uses builtin`" work was pure instrumentation
artifact.

## Pick up next, in order

1. **`bug-nilpy-too-few-args-to-container-method-compiles-and-segfaults`** (75).
   `xs.index()` and `d.get()` compile then SIGSEGV; `.count()` returns a wrong
   value. Too MANY args IS rejected and str methods ARE rejected — so a check
   exists and fails in one direction on one path. Cause deliberately NOT
   guessed: diff `xs.index()` against `xs.index(2)` with `PXXDBG=a.ir:<proc>`
   and check whether `FindUMethArity` is consulted there at all.
2. **`bug-nilpy-dict-from-pairs-and-bytes-decode-segfault`** (70) — only the
   `dict()` half is left. Diagnosed: `dict(x)` lowers as a **typecast** to
   TPyDict rather than a conversion, so it reinterprets a TPyList's header
   words. Evidence and fix shape are on the ticket.
3. **`bug-nilpy-global-shadowed-by-method-param-name-loses-class-type`** (75).
   Pre-existing (reproduces on pinned v239). Heavily narrowed on the ticket,
   which also records a REJECTED fix and two of my own wrong claims, corrected —
   read those first so you don't repeat them.
4. **`bug-nilpy-static-typed-operands-skip-mixed-type-guard`** (70) — 117 sweep
   cases, the largest remaining family. Needs a per-operator legality table
   derived from CPython's rules, NOT another guard. The ticket explains why
   there is no single entry point to patch (`+ - * /` and comparisons are typed
   in `parser.inc`; bitwise goes through `PyWiden` in `pyparser.inc`).
5. `bug-nilpy-str-format-ignores-positional-indices` (60), then the survey
   tickets (step slicing, `list(range(...))`, `pow`, `str.index`, `expandtabs`).

Also filed for other lanes, not yours: `bug-t-xeon-job-set-covers-only-a-third-of-nilpy-tests`
(T, 55 — the user is investigating on that box) and
`bug-t-gate-sh-pgrep-fc-double-zero-integer-error` (T, 25).

## Tooling left behind — reuse it

Two differential sweeps under the session scratchpad (may be gone; each has a
`gen.py` that regenerates its cases, and `run.sh <pxx-binary>` diffs against
precomputed CPython oracles):

- **sweep** — 1094 cases, operator × operand-type matrix + every dunder protocol.
- **sweep2** — 133 cases, string/list/dict/builtin METHOD surface.

Three traps, each of which cost me a run:

- The pxx binary **must live inside the repo tree** or `uses builtin` fails and
  every case silently "passes" — one bogus zero-divergence run.
- **Never rebuild the compiler mid-sweep** — two discarded runs.
- After a batch of fixes, re-run a sweep and **diff the group counts against the
  previous run**. That is the only thing that caught a regression where I traded
  a loud compile error for silent pointer math; nine passing per-fix tests did
  not see it.

## Discipline that actually mattered

- **Write tests that can distinguish the broken implementation from the correct
  one.** The list allocated first must sort last; `__ne__` must disagree with
  `not __eq__`; `__enter__` must return something other than `self`. Several
  existing tests passed only by coincidence.
- **Check how a test's operands are BOUND before trusting it.**
  `test_nilpy_mixed_type_operands` asserts all the mixed-type cases and passes —
  its operands come from a heterogeneous list literal, so they are all variants,
  the one path that works. It reads as coverage while being unable to fail.
- **Measure with `PXXDBG` before writing a cause into a ticket.** Three
  plausible diagnoses died on contact this session; each would have sent a fix
  to the wrong file.
- **Park forks as Track U `decide-*` tickets and move on.** Do not guess.
