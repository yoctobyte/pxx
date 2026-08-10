# Handoff — 2026-08-10, Track A+C+P+N

Prompt to self for the next session, and a plan for the week.

## Cold start

```
git pull --rebase && tools/progress.sh next --track <A|C|P|N>
```

Pin is **v256** (`44db8460…`). Everything below is pushed and green.

## Start here — 30-minute wins

1. **`bug-p-parenless-call-to-an-all-defaulted-routine-is-an-undefined-variable`** (P, 50).
   `P;` fails when every parameter is defaulted; `P()` works and methods work.
   The diagnostic says "undefined variable", blaming name resolution for an
   arity problem. Small, and I filed it with the boundary already measured.
2. **`bug-nilpy-method-chained-on-open-result-fails-to-parse`** (N, 50).
   `open(p).read().strip()` — one chained call works, two do not. Suspect the
   bare `Exit` in the `open` intrinsic; **check the sibling intrinsics
   (`input`, `int`, `str`) for the same shape** before fixing just this one.
3. **`bug-nilpy-del-on-a-plain-variable-silently-does-nothing`** (N).
   `del x; print(x)` prints 5 instead of raising NameError. Verified still live.

## The week's themes, in priority order

**1. Let Track B run.** Two items are unblocked *because of today* and B is
waiting on neither of us:
- `feature-b-tkhtmlview-in-nilpy` — pure Track B now that library `.py` imports
  resolve. The point is to surface NilPy's *library*-shaped gaps: platonic code,
  file tickets, do not contort the library around a compiler bug.
- `feature-b-crtl-last-seven-unimplemented-declarations` — pin v256 carries the
  entry-stub finalizer. If handlers do not fire, suspect crtl's registration,
  **not** the stub (the hook is inert until crtl registers a drain).

**2. The `==`-on-a-variant family.** `bug-nilpy-eq-dunder-skipped-when-either-operand-is-a-variant`
is now the *only* live piece: `in`/`count`/`index`/`remove` all dispatch
`__eq__` correctly as of today, `a == xs[0]` does not. The old "fix PyVarEq and
everything follows" framing is stale — something already reaches `__eq__` from
the container side, so the first question is **what route membership uses**, and
whether `==` can be pointed at it rather than growing a second path.

**3. `environ`.** `feature-c-entry-stub-must-run-initializers-for-environ` —
`char **envp = environ;` silently becomes NULL. Today's work added the *fini*
phase; this needs the *init* phase. Prefer a general
`__pxx_run_initializers` shell over an `environ`-shaped hole.

**4. Optional[str] + None** (`unfinished/`). Root found and recorded: the None is
**coerced to a string at the call site** (arrives tagged VT_STRING alongside
`"a"`), so `is None` is correctly False about a value that is no longer None.
Fix belongs at the Optional lowering, not at the comparison. Re-check it against
`PyPickOverloadByArgTypes` — a variant parameter now exactly matches a variant
argument, which may make it resolve honestly rather than by conversion.

## Parked deliberately — do not re-derive

- **Named parameters in Pascal** → `rainy-day/idea-p-named-parameters-in-the-pascal-dialect`.
  Owner's call. Decisive argument: not standard Pascal, so the only consumers
  would be pxx-authored wrappers of Python-shaped APIs — and those can just be
  Python. Full reasoning + the FPC-compat analysis is in the ticket.
- **songformatter stays blocked**, on purpose. It is a test case and is more
  useful as the thing that surfaced the tkhtmlview question.
- Two dialect calls want a `decide-` if not obvious: text-mode `read(n)`
  returning bytes, and object dict keys with `__eq__` but no `__hash__`.

## Method notes that paid off today

- **Measure, don't reason.** Three defects in the scope-hiding change came from
  gates, not thought: FPC-seed include ordering (which `make compiler/pascal26`
  had already converged past), the parameterless-vs-parameterised split binding
  through *different code*, and a `System.Random` regression only `test-core`
  caught.
- **A ticket's stated cause is usually wrong.** songformatter blamed a
  module-level `def get`; the repro fails with no module-level `get` at all. The
  `-O3` cmath diffs were crtl. The `in`/`==` tickets' shared-mechanism premise
  is now false.
- **Use each ticket's own test.** The multi-parameter-lambda repro matches
  CPython *by design* — output matching would have called it fixed; its real
  test is `strings | grep -c '^return '`.
- **One concept, N sites.** Today: four parameter parsers, two default-arg
  builders, two file classes for one Python type. Grep for the sibling before
  closing.

## Cheap, reusable

I extracted all 43 python repros from non-done NilPy tickets and diffed them
against CPython in one pass — it found two stale tickets and one false positive.
Worth re-running after any big NilPy landing.
