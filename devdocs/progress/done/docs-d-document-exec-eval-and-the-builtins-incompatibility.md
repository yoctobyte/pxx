---
track: D
prio: 35
type: docs
summary: "docs/targets/nil-python.md tells the public `eval`/`exec` do not exist (\"No eval of runtime-constructed code\") — but the explicit-dict form has worked since 2026-07-31 via pyeval's tree-walker. Document what exec/eval DO support, the refused ambient form, and the decided __builtins__ incompatibility (decided 2026-08-19, permanent for now)."
status: done
owner: frankD
---

# Public docs: `exec`/`eval` exist, and `__builtins__` is a decided incompatibility

- **Track:** D (prose only — `docs/**`, never `compiler/**` or `lib/**`).
- **Source of truth to write from:**
  `devdocs/dev/nilpy-semantics-divergences.md` §`exec binds, but injects no
  __builtins__ key`, and [[decide-nilpy-exec-injects-a-builtins-key]] in
  `rainy-day/` (the decision record).

## Why this is filed

The `__builtins__` question was **decided 2026-08-19 (user): leave it out, and
document it as a known incompatibility rather than emulate it badly.** The
decision explicitly names documentation as the deliverable — an undocumented
incompatibility is the thing the decision was made to avoid. The internal
divergences note carries it; the public docs do not, and the public docs are
where a user landing on a `NameError` difference will look.

## Two things to fix, and the first is a stale claim

### 1. `docs/targets/nil-python.md:31` says eval/exec do not exist

> **What it will not do**, and this is a design boundary rather than a gap to
> close: anything requiring a live interpreter. No `eval` of runtime-constructed
> code, …

That was true when written and is now wrong. `exec(src, g, l)` and
`eval(src, g, l)` — the **explicit-dict** forms, which is what CPython also
offers — have worked since 2026-07-31 ([[feature-lib-pyexec]], Engine 1: a
tree-walker over the source, `EvalPyStmts` / `pyeval_expr` in
`compiler/builtin/pyeval.pas`, lowered at `compiler/parser.inc:12167`). They are
gated by a test diffing whole output against CPython.

The sentence needs to become a boundary that is actually true. The honest shape:
the **ambient** forms are refused, the **explicit-namespace** forms work. Do not
overclaim in the other direction either — this is a Python *subset* walker
(no `import`, no `class` definitions, no exec-in-exec), and the contract is in
`feature-lib-pyexec`'s "Contract" section. Verify anything you write by
compiling it against `$(PXX_STABLE)`; do not restate this ticket's summary as
if it were tested.

### 2. Add the `__builtins__` incompatibility

Belongs in **Known gotchas** (`:341`) or a short `exec`/`eval` subsection —
whichever reads better once §1 is rewritten; that is the writer's call.

The user-visible facts, all measured:

| | CPython | Nil Python |
| --- | --- | --- |
| `d={}; exec("x=1", d, d); sorted(d.keys())` | `['__builtins__', 'x']` | `['x']` |
| `d["x"]` | `1` | `1` |
| `d={"__builtins__":{}}; exec("n=len([1,2,3])", d, d)` | `NameError` | `n = 3` |

Row 3 is a **separate open bug**
([[bug-n-exec-ignores-a-caller-supplied-builtins-mapping]]), not covered by the
decision — if it is fixed before this ticket is taken, drop that row and say so
here. Rows 1-2 are the decided, permanent-for-now difference.

**The reason, one sentence, because it is what makes it credible rather than an
apology:** CPython resolves every name miss through one runtime dict, so
`__builtins__` is live and mutating it is program-wide; Nil Python resolves
builtin names in compiled code at compile time, so any `__builtins__` it handed
back would be honoured by exec'd source and silently ignored by compiled call
sites. A key that half-works is worse than an absent one, so it is absent.

Keep the public wording **uncompressed** — this is a claims-discipline area: say
*"the explicit-namespace forms of `exec`/`eval` work"*, never *"exec works"*,
and never imply a live interpreter.

## Out of scope

Do not touch `compiler/**`, `lib/**`, or the divergences note (that one is
Track N/A ground and already correct). If a code snippet here fails to compile
against the pinned compiler, file a ticket in the owning lane — do not adjust
the snippet until it passes.

## Log
- 2026-08-29 — resolved, commit PENDING-COMMIT.

---

## RESOLVED 2026-08-29 (frankD)

Both halves done in `docs/targets/nil-python.md`; no other page in `docs/**`
mentions `exec` or `eval` at all, so nothing else needed touching.

### 1. The stale claim, replaced with a boundary that is true

`:31` no longer says "No `eval` of runtime-constructed code". The design boundary
(no live interpreter, no monkeypatching, no run-time duck typing) **stays** — it is
still true and still the point — and exec/eval are pulled out of it into a pointer at
the new section, stating the honest shape in the ticket's own words: the
explicit-namespace forms run source built at run time, over a subset, through a
tree-walker over the text and **not** a live interpreter.

### 2. New `## exec and eval` section, before Known gotchas

Written uncompressed, as the ticket demanded — *"the explicit-namespace forms work,
over a subset of Python"*, never "exec works", and the no-live-interpreter sentence
sits in the opening paragraph where a skim cannot drop it.

Covers: a worked example of both; `eval`'s ambient form (allowed — an expression only
reads); `exec`'s ambient form refused, with the diagnostic quoted; the subset, both
halves (what is in, and that `import` / `class` / nested `exec` are out); the
`__builtins__` incompatibility with its reason; and the separate open bug.

### One correction to the source material

The divergences note quotes the ambient-`exec` refusal **without its tail**. The real
message ends `..., then read the results out of d`. The page quotes what the compiler
actually prints — verified by extracting the fenced block from the published Markdown
and string-comparing it to the compiler's own stderr, not by eye. The internal note is
Track N/A ground and out of scope here; it is a stale quote, not a wrong one.

### Row 3 kept — the bug is still open

The ticket said to drop it if fixed first. `bug-n-exec-ignores-a-caller-supplied-builtins-mapping`
is still in `backlog/` and still reproduces, so the row stands, in its own table,
labelled open-and-tracked and separated from the decided-permanent rows. The page
tells the reader not to use it as a sandbox.

That row is the one place the page describes NilPy accepting what CPython rejects.
Left in deliberately: it is not mine to reclassify — it is already filed as an
upward-compatibility **defect** by its own lane, on the grounds that working CPython
code relying on the restriction takes a different path here. Framed as tracked, never
as a dialect feature.

### Measured — pinned v391, no rebuild, every claim diffed against `python3`

- rows 1-2: CPython `['__builtins__', 'x']` / `1`; pxx `['x']` / `1`;
- row 3: CPython `NameError`, pxx `3`;
- the page's own snippet, extracted verbatim from the rendered Markdown: `6` / `42` on
  both, matching its inline comments;
- the quoted refusal: extracted from the fenced block and string-compared to the
  compiler's stderr — **exact match**;
- the subset paragraph is not restated from the Contract on faith: `def`, `for`, `if`,
  augmented assignment, f-string, `isinstance`, list literal, `len` and a nested call
  inside one `exec` produce identical output on CPython and pxx;
- the three exclusions checked individually.

### Found while documenting, filed not fixed

[[bug-n-an-import-inside-exec-is-silently-skipped-and-execution-continues]] — the
"NO import" restriction is enforced by **discarding the statement in silence** while
execution continues, unlike the walker's other two restrictions, which announce
themselves. `exec("import os\nk = 1", d, d)` binds `k` and says nothing; with the
module used, the error arrives at the use site naming the module rather than the
skipped import. That is the accepted-and-ignored failure mode the ambient-`exec`
refusal was explicitly built to avoid. Also noted as a Known gotcha, since a real
program can hit it today.
