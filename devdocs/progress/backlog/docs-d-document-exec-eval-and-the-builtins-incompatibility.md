---
track: D
prio: 35
type: docs
summary: "docs/targets/nil-python.md tells the public `eval`/`exec` do not exist (\"No eval of runtime-constructed code\") — but the explicit-dict form has worked since 2026-07-31 via pyeval's tree-walker. Document what exec/eval DO support, the refused ambient form, and the decided __builtins__ incompatibility (decided 2026-08-19, permanent for now)."
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
