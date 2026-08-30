---
track: U
prio: 45
type: decision
blocked-by: []
summary: "The 2026-08-27 per-topic tree topology puts ~/frank-rust on branch `rust` because topic branches carry 'destabilizing' work. frank-rust argues, with evidence, that its work has not been destabilizing: 8 commits, compiler/rparser.inc + tests + 38 Makefile lines, no shared internals, self-host byte-identical each time, gated suite. Cost of the branch: Track T sweeps origin/master only, so those 8 commits have never met the matrix, and origin/rust is already 57 behind. Decision: retire the topic branch and put Track R on master, or keep it and adopt a merge-in cadence."
status: superseded
superseded-by: decide-does-track-r-work-on-master-like-every-other-lane
---

> **SUPERSEDED 2026-08-30 by `decide-does-track-r-work-on-master-like-every-other-lane`.**
> This ticket and its sibling asked one question, and both priced it off a
> divergence measurement that has since moved: `git cherry origin/master
> origin/rust` reports **122 of the 136 commits already have patch-equivalents
> on master**, only 14 do not, and 14 is an upper bound — two spot-checks of
> those 14 are demonstrably present on master. **Do not act on the numbers
> below.**
>
> Filed in `rejected/` because it is not the open question, **not because its
> reasoning is wrong** — the analysis below is preserved intact and is still
> the best writeup of the topology argument. Read it; re-measure before
> quoting it.


# Should the Rust topic branch be retired onto master?

Filed 2026-08-29 by frank-coordinator on frank-rust's argument. **The evidence
is frank-rust's; the measurement and the Makefile finding are mine.** I recommend
retiring it, and it is the owner's topology call, not mine.

## The current rule and why it exists

`session-roster.md`, "2026-08-27 — PER-TOPIC TREE TOPOLOGY": a checkout per
role, with topic branches carrying the **destabilizing** targets (`wasm`,
`rust`) while `master` is the trunk where A, B and the coordinator meet. The
mechanical reason it does not extend to A/B is good and unchanged:
`stable_linux_amd64/**` is 28 MB of committed binary that A rewrites at every
pin, so a long-lived branch pays a binary conflict on it every merge.

CLAUDE.md still says all tracks work on `master`; the roster section is newer
and supersedes it for these two trees. **That divergence is itself worth
settling** — an agent reading CLAUDE.md alone concludes its own tree is
mis-checked-out, which is what happened to me this session.

## The argument for retiring it

frank-rust's, and it engages the criterion rather than preferring an outcome:
**the work has not been destabilizing.** Every commit is `compiler/rparser.inc`
plus tests, no new AST node, no IR op, no symtab field, no backend edit; the
self-host fixedpoint converged at each one; the Rust suite is gated. Twice a
change looked like it needed a Track A ticket and did not — struct/enum returns
and the `&mut` aliasing switch were both already in the shared machinery and
simply unused by the Rust frontend.

## The measured cost of keeping it

- **Track T sweeps `origin/master` and nothing else.** 8 commits have never been
  near the matrix — no cross-target jobs, no corpus. A per-commit self-host
  fixedpoint proves the compiler reproduces itself *at the default `-O` level*;
  it is not evidence that thirteen green `test_rust_*.rs` hold on i386 or
  aarch64.
- **Drift is already live.** `origin/rust` is 8 ahead and **57 behind**
  `origin/master`, four hours after a merge-in. The comparison case is
  `origin/wasm` at 76 ahead and **312 behind**, where every finding that lane
  files describes the tree as it stood 312 commits ago.

## The cost of retiring it, which is not zero

`origin/rust` touches **`Makefile`, +38 lines** — not only `rparser.inc` and
tests. frankB holds `Makefile` right now for the assertion-conversion campaign
(498 landed, ~1630 in flight). So the merge must be **sequenced behind frankB**
either way; this is a scheduling constraint, not an argument against.

## The three options

1. **Retire the branch; Track R works on `master`** like A, B, C, N and D.
   Restores CLAUDE.md's rule, puts R's work in T's matrix immediately, removes
   the merge ceremony. Costs: R's destabilizing work, if any arrives later,
   lands on the trunk — mitigated by the same `working/` ticket lock every other
   lane uses, and by the fact that R's files are disjoint from every other lane's.
2. **Keep the branch, adopt a mandatory merge-in cadence** — `git merge
   origin/master` at every rung boundary, not once per session. Preserves the
   owner's topology. Costs: the cadence is a discipline nobody can enforce, and
   `wasm` at 312 behind is what happens when it lapses.
3. **Keep it and accept the drift**, merging on occasion as originally intended.
   Honest, and the status quo. Costs: R's work stays outside the matrix
   indefinitely.

**Recommendation: option 1**, with the merge sequenced after frankB's tranche
two. The criterion the topology was built on — destabilizing work — does not
describe what Track R has actually produced, and the branch's only measured
effect so far is to keep 8 green commits out of the test matrix.

**Not in scope:** `wasm`. It is 76 ahead and 312 behind with shared-file arms
already ledgered in `feature-a-merge-the-wasm-branch-the-shared-file-arms`, and
nothing there is pre-approved. Branch permission is not merge permission, for
either branch.
