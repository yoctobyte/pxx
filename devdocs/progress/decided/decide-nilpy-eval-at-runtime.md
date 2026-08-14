---
track: U
prio: 35
type: decide
blocked-by: []
summary: "Does NilPy support `eval(s)` / `exec(s)` over a runtime string at all? A compiled dialect either ships a parser in every binary or it does not — this is a design call, not work, and it has sat as a to-do row on a bug ticket for three sessions."
status: decided
---

# Decide: is `eval(s)` in scope for NilPy?

Raised by [[bug-nilpy-builtin-surface-gaps-found-by-the-2026-08-12-sweep]],
whose table lists `eval(s)` with the note *"deliberately absent? if so it
belongs in the divergences page, not here"*. Three sessions have passed it over
because it is not a gap to close, it is a question to answer.

## The fork

**A.** `eval` / `exec` are OUT of scope. They go in
`devdocs/dev/nilpy-semantics-divergences.md` with the reason, the diagnostic
names them explicitly ("NilPy compiles ahead of time; eval() has no run-time
parser"), and the row leaves the bug ticket.

**B.** They are IN scope, which means every binary that might reach one carries
the NilPy front end — lexer, parser and lowering — plus a run-time code path to
execute what it built. `pyeval` already exists as an interpreter for closures,
so the execution half is not from nothing; the parser half is.

**C.** A middle: `eval` over a restricted EXPRESSION grammar only (literals,
names already in scope, arithmetic, indexing), refusing statements. Covers the
config-file and calculator uses that motivate `eval` in real code without
shipping the whole front end.

## Trade-offs

- **A** costs nothing and closes the row honestly. It also closes the door on
  compiling any library that uses `eval` in a code path we actually reach — worth
  knowing, since [[feature-nilpy-thirdparty-libraries-as-targets]] is the
  campaign this dialect exists for, and `namedtuple` in CPython's own stdlib is
  built with `exec`.
- **B** is the largest of the three and puts a parser in every binary that
  imports the wrong module. It is also the only one that makes `namedtuple`-style
  code work as written.
- **C** is bounded and covers the common case, but a restricted eval that is
  *nearly* Python invites exactly the "works until it doesn't" complaint that a
  clean refusal avoids.

## Recommendation

**A for now, revisited only when a corpus library actually blocks on it.** The
mission is compiling real libraries, so the question should be answered by a
measurement — grep the corpus for `eval(` / `exec(` on a reachable path — rather
than in the abstract. If that measurement comes back non-empty and the module
matters, **C** is the cheaper half-step and **B** is what `namedtuple` would
really need.

Note the asymmetry: choosing A and reversing later costs only the divergences
entry. Choosing B early costs a parser in every binary.

## DECIDED 2026-08-14 by the user — the fork is already settled by shipped work

> *"It already works. It's a done job. I'm not sure why the ticket is even there."*

Mostly right, and worth writing down precisely, because "eval" turns out to name
three different things here and only one of them is done.

**Runtime eval capability EXISTS and is real.** [[feature-lib-pyexec]] is in
`done/`: exec-as-a-library in CPython's explicit-dict form, no ambient scope
capture, host passes name -> value bindings including BOUND METHODS of compiled
classes — which is how uforth's PYTHON blocks call back into their VM. Diffed
against `python3`, not against our own output. `pyeval.pas` is 5289 lines.

So **option B's stated cost is already paid**: the parser and an execution path
ship today. The design question this ticket asked — "does a compiled dialect
ship a parser in every binary or not" — was answered by building one.

**And there is a compile-time evaluator**, also substantial. Where a construct
genuinely cannot be settled at compile time (a lambda, a closure), falling back
to the runtime library is a legitimate answer — slower than compiled, correct,
and it has full run-time type information. That is the policy, and it needs no
decision.

### What is NOT done, measured 2026-08-14

The BUILTIN surface, as opposed to the library:

| | pxx | CPython |
| --- | --- | --- |
| `lib_pyexec` library form | works | — |
| `exec("x = 1 + 2", d, d)` then `sorted(d.keys())` | **`[]`** | `['__builtins__', 'x']` |
| `eval("1+2")` | `error: undefined variable (eval)` | `3` |
| `exec("x = 1")` (ambient) | compile error | `1` |

`test/test_nilpy_exec_stub.npy` does not catch the first row: it calls
`exec("x = 1", d, d)` and then asserts a **pre-existing** key, never the one exec
was supposed to define.

**The silent no-op is the part that matters** — worse than the name being
absent, because `eval` failing to compile is a loud, actionable error while
`exec` accepting the call and doing nothing is a program that runs and is wrong.

### Outcome

Ticket closed: no design fork remains. The remaining work is wiring the builtin
names onto the shipped library, filed as
[[bug-n-exec-builtin-is-a-silent-no-op-and-eval-is-absent]] (Track N).

## Log
- 2026-08-14 — decided, commit 1ae19131c.

**Addendum, same session:** and they belong on the BUILTIN surface, auto-included
like the rest of the Python RTL rather than behind an import — Python has no
separate runtime library to opt into, so presenting them any other way would be
the divergence. Recorded on the Track N ticket so the implementer does not
re-open it.
