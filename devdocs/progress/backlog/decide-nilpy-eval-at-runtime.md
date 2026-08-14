---
track: U
prio: 35
type: decide
blocked-by: []
summary: "Does NilPy support `eval(s)` / `exec(s)` over a runtime string at all? A compiled dialect either ships a parser in every binary or it does not — this is a design call, not work, and it has sat as a to-do row on a bug ticket for three sessions."
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
