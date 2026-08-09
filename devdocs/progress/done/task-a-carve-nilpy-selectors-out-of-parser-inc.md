---
track: A
prio: 45
type: task
status: done
owner: agent-AN
---

# Carve NilPy's selector/subscript parsing out of `parser.inc`

**User, 2026-08-09:** *"parser support functions — instead of being a solution
for multiple languages, as soon as those languages diverge, there is no shame in
copying the helper function and make it language specific."*

This extends the standing rule (`feedback_duplicate_helpers_per_language_shared_ast`,
2026-07-20) from RUNTIME helpers to PARSE routines. The shared thing is the
AST/IR — not the parser.

## Measured

| | count |
| --- | --- |
| `PyExprMode` guards in `compiler/parser.inc` | **129** |
| `isNilPy` guards in `compiler/parser.inc` | 67 |
| `PyExprMode` guards in `ParseClassRecordSelectors` **alone** | **34** |

A function with 34 dialect tests is two functions interleaved.

## Why it is not cosmetic — two bugs from one day

- **`f()[1]` on a string-returning call returned character 0.** The shared
  `tyAnsiString + tkLBrack` arm applied **Pascal's 1-based index** to a NilPy
  expression. The defect was not a MISSING NilPy arm; it was the Pascal arm
  quietly serving NilPy. `f()[0]` was "correct", so it survived a long time.
- **A `@dataclass`'s `str` default silently became `''`.** A defensive
  "fill every unsupplied string parameter" loop ran ahead of the dataclass
  defaults and consumed the slot.

Both share a shape: **the wrong dialect's behaviour is the DEFAULT, and the
right one is an arm someone has to remember to add.** A split inverts that — a
NilPy-only routine cannot accidentally do the Pascal thing, because the Pascal
code is not in it.

## Scope

Start with `ParseClassRecordSelectors` — the densest, and the one that produced
both bugs. Copy it into `pyparser.inc` as a NilPy-only selector parser, delete
the Pascal arms from the copy and the NilPy arms from the original, and call the
copy from the NilPy entry points. NilPy already owns `pylexer.inc` /
`pyparser.inc`; selector parsing living in `parser.inc` is the anomaly.

Do NOT attempt all 129 at once. One routine per change, each landing green, with
the guard count recorded so the trend is visible. Some guards are genuinely
about *shared* behaviour (a NilPy-only diagnostic on a shared construct) and
should stay — the test is whether the two dialects want different SEMANTICS
there, not merely different messages.

## Note on the Pascal side

`parser.inc` is Pascal's frontend as well as the shared expression parser, so
this is Track A ground and carries the self-host gate. The self-host fixedpoint
is a strong oracle for the Pascal half: if the carve-out changes Pascal
behaviour at all, the compiler stops reproducing itself. Use that — it makes the
Pascal side of each split nearly free to verify, which is the opposite of the
NilPy side.

## Gate

Per routine: `make compiler/pascal26` (the fixedpoint) + `tools/gate.sh quick`,
plus a whole-suite HEAD-vs-pinned `.npy` sweep — a carve-out is a NARROWING
change, and narrowing cannot be regression-tested by the tests that motivated
it (that is how the exact-case ctor fix broke aliased constructors the same day
and was caught only by the sweep).

## Progress — 2026-08-09, split 1 of N: `ParseClassRecordSelectors`

**Done.** `PyParseClassRecordSelectors` now lives in `compiler/pyparser.inc`;
`ParseClassRecordSelectors` (parser.inc) dispatches to it on `PyExprMode` and is
otherwise the Pascal-only selector parser.

### Correction to the measurement in this ticket

The "34 `PyExprMode` guards in `ParseClassRecordSelectors` alone" line is wrong
— it counts a wider span than the routine. Inside the routine's actual bounds
there were **nine** dialect forks: six `PyExprMode`, two `isNilPy`, one
`NilPyUserCode`. Nine forks in one 600-line routine is still exactly the shape
the ticket describes, so the conclusion stands; only the number was inflated.
Leaving the original line in place above rather than editing it, per the
don't-rewrite-history rule.

### What moved, and what deliberately did not

- The NilPy copy keeps every arm and folds all nine guards to `True`.
  `PyExprMode` is set only by `pyparser.inc`, so inside that copy `PyExprMode`,
  `isNilPy` and `NilPyUserCode` are all constantly true — the fold is provable,
  not a judgement call. That makes split 1 a **pure restructuring**: no arm's
  reachability changes in either dialect.
- Deleted from the Pascal copy: the six `PyExprMode` arms (evaluate-receiver-once,
  variant method dispatch, keyword-arg fold, slice divert, chained variant
  subscript, default-property write). Provably dead — `PyExprMode` is false there
  by the dispatch.
- **Kept** in the Pascal copy: the two `isNilPy` arms (Python trailing comma,
  str-method chaining) and the one `NilPyUserCode` arm (bound-method value).
  These are NOT dead. With `PyExprMode` false, `isNilPy` is still true while
  parsing the **Pascal RTL units** an `.npy` program pulls in, and
  `NilPyUserCode` reduces to `isNilPy and (CurrentUnitIdx < 0)`, which holds
  during the main program's pre-`PyExprMode` phase (prepass / trial-AST typing).
  Deleting them would have been the microfix version of this change: it *looks*
  like carving and is actually a behaviour change smuggled into a refactor.
- Pascal-only arms (interface IMT dispatch, class-reference operations, `Free`)
  are still in the NilPy copy on purpose. pylib's containers are Pascal classes
  reached from NilPy code, so "no NilPy program can reach this" needs a
  measurement, not a reading. Removing them is a later, separately gated pass.

### Guard trend

| | before | after |
| --- | --- | --- |
| forks inside the routine | 9 | 1 (the dispatch) |
| `PyExprMode` in `parser.inc` | 129 | 125 |
| `isNilPy` in `parser.inc` | 67 | 67 |

### Gate

- `make compiler/pascal26` — **converged after 1 round**, byte-identical. This is
  the whole Pascal-side proof: 600 lines were moved and six arms deleted, and the
  compiler still reproduces itself exactly.
- `tools/gate.sh quick` — GREEN (self-host fixedpoint 28s, testmgr quick 9s, FPC
  seed canary).
- FPC seed build run by hand as well, because this **adds a routine** and neither
  `make` nor `gate.sh` covers that (`feedback_fpc_seed_build_not_covered_by_make_or_gate`).
  No forwards.inc entry needed: parser.inc's own `forward` for the twin works for
  FPC, since pyparser.inc is included after parser.inc in the linear text.
- Whole-suite HEAD-vs-pinned `.npy` sweep, 513 files: **0 regressions.** HEAD
  differs on 3 (`delitem_dunder`, `input_eof_raises`, `select_stdin_ready`) —
  all three also differ under `pinned`, i.e. pre-existing, and `delitem_dunder`
  already has its own ranked ticket.

### Next splits (not done here — one routine per change)

`ParseLValueAST` is the obvious next target: it is the *sibling* path to this
one (bare-identifier receiver vs chained receiver), and this repo has now been
bitten at least three times by teaching one and not the other
(`project_nilpy_lvalue_vs_selector_path_must_both_know`). Splitting it has a
second payoff beyond guard count: once both selector paths are NilPy-only
routines, the two can be made to share a NilPy-side helper, which is the actual
fix for that recurring double-case — not possible while both are entangled with
Pascal.

## Log
- 2026-08-09 — resolved, commit PENDING-COMMIT.
