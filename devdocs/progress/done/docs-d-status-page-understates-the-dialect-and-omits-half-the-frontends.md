---
track: D
prio: 25
type: docs
blocked-by: []
summary: "Spun out of idea-public-status-page per the coordinator's Track D scoping ruling: the live-data half is Track W/T and stays parked. The prose half is already built and good — docs/reference/status.md carries the claims discipline correctly and deliberately no figures — but it has two real defects. It frames the Pascal frontend as 'the Object Pascal language as Free Pascal accepts it', contradicting dialect.md and modes.md which both say PXX is its own dialect first; and its frontend coverage stops at C/Pascal/NilPy while --version advertises twelve and docs/targets/other-frontends.md now accounts for them."
status: done
owner: frankD
---

# The status page understates the dialect, and covers three frontends of twelve

- **Track D** — prose only, `docs/reference/status.md`.
- **Spun out of** [[idea-public-status-page]] on the coordinator's ruling: scope
  to *what the repo can already answer truthfully, with no new machinery*. The
  idea ticket's actual subject — wiring the page to the generated
  `tstate/` conformance/bench/dashboard renderers — needs a publish path and is
  **Track W/T**. That half stays parked in the idea ticket; this is the Track D
  half, and it is not "write a status page" because one already exists.

## What is already right, and must not be disturbed

`docs/reference/status.md` is in good shape and the parts that matter most are
the parts to leave alone:

- the **two "byte-identical" claims are stated separately and correctly** —
  self-host reproducibility (the *binary* reproduces itself) versus behavioural
  output parity (zlib built with PXX emits a stream identical to a gcc-**built**
  zlib's), with *"PXX does not emit the same machine code as gcc, and does not
  claim to"* said outright;
- it carries **no figures on purpose** (`ce89ff14b`, *"stop hand-writing numbers
  in status.md"*) and defers current counts to the live pages. Do not
  reintroduce a number.

## Defect 1 — it frames the dialect as FPC parity, which the project denies

> PXX targets the Object Pascal language as Free Pascal accepts it

That contradicts the two pages that own the question:

| page | says |
| --- | --- |
| `docs/language/dialect.md` | *"PXX is an Object Pascal dialect… it does not aim for full FPC compatibility and it also has PXX-specific extensions."* |
| `docs/reference/modes.md` | *"PXX is its own dialect first and an FPC-compatibility tool second."* |

And `CLAUDE.md` is explicit that we do **not** chase 100% FPC parity. So the
status page — the page a stranger reads to find out what this is — is the one
place still describing PXX as aiming to be FPC. It is the same rot direction
found repeatedly on 2026-08-29: the docs understating what the thing is.

## Defect 2 — three frontends of twelve

The page has sections for C, Pascal and Nil Python. `pxx --version` advertises
twelve, and `docs/targets/other-frontends.md` (landed 2026-08-29) now accounts
for all of them — BASIC as a real frontend, Rust and Zig as experimental, six as
skeleton probes. A compatibility-status page that silently omits nine of them
invites the reader to conclude they do not exist.

The fix is a pointer and one honest sentence, **not** a status section per
frontend: a probe has no compatibility status worth tabulating, and giving it one
would overstate in the other direction.

## Also worth one line

`--list-targets` lists `wasm32` as *registered only — no codegen yet*. The
cross-target section says "six backends in all" (correct — wasm32 has no
codegen), but a reader who has run `--list-targets` sees a seventh name with no
explanation.

## Scope

Prose only. No figures. No new machinery, no generated content, no website work.
Do not touch the claims-discipline section except to keep it intact.

## Gate

Docs internally consistent — specifically, `status.md` must stop contradicting
`dialect.md` and `modes.md`. Any snippet compiles against `$(PXX_STABLE)`; the
page has none today and does not need one.

## Log
- 2026-08-29 — resolved, commit 1e524bc53.

---

## RESOLVED 2026-08-29 (frankD)

Filed and done in one pass, per the coordinator's *file it, then do it*.

### The scoping call, and why the deliverable was not what it first looked like

The ruling was "a page that states in prose what works today with the evidence
named". **That page already existed and was good** — `docs/reference/status.md`
already carries the two "byte-identical" claims stated separately and correctly,
already says outright that PXX does not emit the same machine code as gcc, and
already carries **no figures on purpose** (`ce89ff14b`). Writing a second one
would have duplicated it, so this ticket is the honest remainder: what that page
gets *wrong*, which is the same rot direction the whole evening turned up.

The idea ticket's real subject — wiring the page to the generated `tstate/`
renderers — needs a publish path and stays parked as Track W/T. Not touched.

### Defect 1 — the page described PXX as aiming to be FPC

> PXX targets the Object Pascal language as Free Pascal accepts it

`dialect.md` says *"it does not aim for full FPC compatibility"*; `modes.md` says
*"PXX is its own dialect first and an FPC-compatibility tool second"*; `CLAUDE.md`
says we do not chase 100% parity. So the one page a stranger reads to learn what
this **is** was the one still selling it as an FPC clone — understating the
project as a compatibility layer rather than a dialect.

Rewritten to say it is a dialect of its own that compiles real FPC code with
parity checks opt-in per rule, plus the sentence that makes the rest of the page
readable: *"works" below means this dialect compiles and runs the code, not that
PXX is indistinguishable from FPC*, and deliberate divergences are recorded
rather than filed as bugs.

### Defect 2 — three frontends of twelve

New `## The other frontends`, pointing at `docs/targets/other-frontends.md`:
BASIC real, Rust and Zig experimental, six skeleton probes with one test each.
Deliberately **not** a status section per frontend — a probe has no compatibility
status worth tabulating and giving it one would overstate in the other direction.
The section says outright that presence in `--version` is not a support claim.

Also the one line the ticket asked for: `--list-targets` names `wasm32` as
*registered only — no codegen yet*, so it is not one of the six backends.

### The defence the coordinator asked for, adapted to this page

Per-claim dates would have fought the page's own deliberate no-figures stance, so
the freshness note is structural instead — new `### What this page can still get
wrong`, which names the failure mode explicitly:

> The gates keep the *numbers* honest, and this page carries none. What they do
> not check is the **prose** — a claim here can quietly stop describing the
> compiler without any test going red, and that failure runs in one direction:
> docs understate what works.

Then the date and pin the structural claims were last checked against
(**2026-08-29, v393**), the rule that the compiler wins over the page, and the
three flags that answer it without a source file. A date does not rot the way a
count does.

### Claims discipline — left intact, checked rather than assumed

The `## What "works" means here` section was **not edited**. Verified after the
fact that all three load-bearing phrases survive: the *binary* reproducing itself,
zlib's **output** matching a gcc-**built** zlib's, and *"PXX does not emit the
same machine code as gcc, and does not claim to."*

### Measured — pinned v393, no rebuild

`--version` prints the twelve-frontend line; `--list-targets` prints `wasm32…
registered only — no codegen yet` verbatim as quoted; `--version`,
`--list-targets` and `--doctor` all exit 0 with no source file, as the new text
claims. All four internal links resolve to existing files.

### Still parked, deliberately

[[idea-public-status-page]] keeps its live-data half. Nothing here generates,
templates, or publishes anything.
