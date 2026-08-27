# The `wasm` branch — charter

**Standalone checkout: `~/frankwasm`. Branch: `wasm`. Established 2026-08-27.**

This is not a worktree of `~/frank2`. It is an independent clone of
`git@github.com:yoctobyte/pxx.git` with its own object store, its own build
tree, and its own remote. If `~/frank2` is deleted, moved, or mid-rebase, this
checkout is unaffected. That independence is the point and must not be traded
away for convenience.

## Why a branch and a separate checkout at all

The usual rule is that every lane works on **`master`** — one branch, no
worktrees or clones (CLAUDE.md; `dev` came and went between 2026-08-25 and its
collapse on 2026-08-26, commit `8b2a6bae6`). This is the deliberate exception,
granted by the user on 2026-08-27, and it rests on one property: **the wasm target is ~85% new files.** A new backend, a new
encoder, a new text emitter, a new PAL directory — none of which any other lane
opens. The conflict surface with `master` is two shared files, both known in
advance and both listed below.

A lane that touches almost nothing others touch, and that would otherwise push a
long stream of non-green intermediate states through everyone's queue, is
cheaper on a branch. A lane that touched shared ground would not be.

**And the exception carries a standing cost, learned the hard way on day one:**
a side branch is invisible. The first version of this lane's tickets was filed
onto `dev` hours after `dev` was retired, and sat where no agent's
`progress.sh next`, no board, and no Track T sweep would ever see it. **Anything
this lane wants other agents to act on — a ticket, a finding, a decision — goes
on `master`, immediately, not "at the next merge".** Only the branch's own
in-progress code stays here.

## Ownership

**Ours, exclusively — new files, zero conflict expected:**

| path | lane |
| --- | --- |
| `compiler/ir_codegen_wasm32.inc` | A |
| `compiler/wasmenc.inc` (module writer + LEB128) | A |
| `compiler/asmtext_wasm.inc` (WAT text) | A |
| `lib/rtl/platform/wasi/**` | B |
| `test/wasm/**` | own |
| `devdocs/dev/wasm/**` | own |

**Shared — the escapes. Each needs a Track A ticket on `master` and
coordination before it is touched here:**

| what | where | status |
| --- | --- | --- |
| module-writer wiring | `compiler.pas` (2 includes + the `TARGET_WASM32` output arm) | **taken 2026-08-27**, coordinator-granted, `feature-a-wasm32-module-writer-wiring` |
| the wasm error message's stated reason | `exception_emit.inc:437` | **taken 2026-08-27**, same grant, message text only |
| VMT slots hold code addresses → must hold table indices | `elfwriter.inc:1937`, `emit.inc:105` | Phase 4, not yet taken |
| exception model | `exception_emit.inc` (the mechanism) | Phase 5, not yet taken |

**The branch now touches shared files, and that changes its risk profile.** It
was true until 2026-08-27 that a `master` merge could not conflict in
`compiler/**`; it is not true any more. The first two rows above are small and
were taken under a coordinator grant with a confirmed-empty file and the A gate
(self-host fixedpoint seen to converge, plus a before/after corpus proving no
existing target moved). But the property that made this lane cheap is now
partially spent, so **merge `master` in more often, not less**, and treat a
conflict in either file as a coordination event rather than a merge to resolve.

Plus the small, unavoidable ones: a `TARGET_WASM32` constant in `defs.inc`, a
`--target=wasm32` arm in `compiler.pas`, and the `TargetArch` chains — which is
precisely why `refactor-a-target-properties-have-no-single-answer` is a
prerequisite rather than a nice-to-have.

## Merge policy

- **Inbound: merge `origin/master` often.** Weekly at worst, and always before
  starting a phase. Merging often is what keeps the two shared escapes from
  becoming a rewrite. `git merge --no-ff origin/master`.
- **Outbound: only in green, reviewed units.** A merge back to `master` is a
  deliberate event, proposed to the user, never automatic.
- **Never rebase.** Same reason a sync is a merge and not a rebase:
  shas are load-bearing here (tickets cite them). Merge commits are the price
  and they are cheap.
- **Never push branches other than `wasm` from this checkout — with one
  standing exception: tickets, findings and board updates go to `master`
  directly.** That exception is what stops this lane going invisible again. It
  covers `devdocs/**` only; never `compiler/**` or `lib/**`.

## Hard prohibitions

- **Never pin from this branch.** `stable_linux_amd64/**` is 27MB of committed
  binary with one writer, on `master` (CLAUDE.md). If a merge from `master` brings a
  new pin, that is fine — it flows *in*. Nothing about the pinned binary ever
  flows *out* of here, and no commit on `wasm` may modify
  `stable_linux_amd64/**` on its own.
- **Do not do `refactor-a-target-dispatch-chains-fail-open` here.** It is a
  shared-file refactor whose acceptance test is byte-identical output for all
  six existing targets. It belongs on `master`, done by Track A, precisely so
  that this branch merges it in rather than colliding with it. It is **not** a
  prerequisite for this lane — see `PLAN.md`, Phase 0.
- **Track A is held by another session (frank1-80, A+N, as of 2026-08-27).**
  Do not edit `symtab.inc` / `ir*.inc` / `defs.inc` / `lexer.inc` on `master`
  while that holds. Confirm before the Phase 4 and Phase 5 escapes.

## Testing — this lane gates itself

**Granted by the user, 2026-08-27: this checkout is responsible for its own
testing and does not rely on Track T.** Track T does not sweep the `wasm`
branch, so nothing else will catch a regression here.

That grant is also the authorization for the full-suite escape hatch. The repo's
`.claude/hooks/no-full-suite.sh` denies `make test*`, `gate.sh full|limited` and
`testmgr --tier full|limited` by default; in **this checkout only**, running
them with `PXX_ALLOW_FULL_SUITE=1` is the intended behaviour, not freelancing.
The hook exists to stop agents on `master` from burning ten minutes on coverage
Track T already provides. Here there is no Track T, so the coverage has to come
from somewhere.

### Bringing this checkout up — a fresh clone is not ready to build

Verified 2026-08-27 on this exact clone:

```
make bootstrap        # ~50s, needs fpc 3.2.2 on PATH
```

A fresh clone has no `compiler/pascal26` (it is not in git), so
`make compiler/pascal26` fails with *"self-hosted compiler seed missing"* until
`bootstrap` has run once. `bootstrap` is the FPC-seeded chain: FPC builds a
seed, the seed compiles the compiler, that output compiles the compiler again,
and `cmp` demands the two be identical. It passed here on the first try.

### The gate

Per commit — unchanged from every other lane:

```
make compiler/pascal26          # IS the byte-identical self-host fixedpoint
<the repro / test for what you just did>
```

**Measured here: ~40s, not the ~12s CLAUDE.md quotes.** The compiler is one
`.pas` with everything `{$include}`d, so any source edit is a full rebuild;
40s is the honest number for this loop in this checkout. Budget accordingly —
it is still cheap enough to run every commit, which is the point.

**Confirm you see `converged after N round(s)`.** This checkout is exactly the
case CLAUDE.md warns about, and it was reproduced here deliberately on
2026-08-27: immediately after a successful `bootstrap`, `make compiler/pascal26`
printed

```
make: 'compiler/pascal26' is up to date.
```

— a success message, exit 0, everything downstream healthy, **and no fixedpoint
proved.** `touch compiler/defs.inc` and the same command then printed
`converged after 1 round(s)`. There is no error to wait for; the absence of the
convergence line is the only tell. If you seed this tree's binary from anywhere
but your own edit loop, `touch` the sources afterwards.

Per phase — before declaring a phase done, and always before proposing a merge
back to `master`:

```
PXX_ALLOW_FULL_SUITE=1 tools/gate.sh quick      # the six existing targets must not move
PXX_ALLOW_FULL_SUITE=1 make test                # full native suite
make -C test/wasm                               # our own suite, under wasmtime
tools/wasm_diff_probe.sh <corpus>               # native vs wasm output differential
```

The first line is the one that matters most and is the easiest to skip: **the
wasm work must not change the output of any existing target.** Until Phase 4
that is guaranteed structurally (new files only). From Phase 4 on it is a claim
that has to be tested.

## What wasm is good for as a target — and it is not what you would guess

Not portability. This project already has six targets; a seventh is not
interesting on that axis alone. The property worth naming is that **wasm's
validator converts a class of codegen error from a silent wrong value into a
hard failure at emit time.**

Measured, not argued (`devdocs/dev/wasm/phase5-exceptions.md`, finding 3): the
exception design threads a pending flag and checks it after every call, and that
check must dominate every use of the call's result. On a register target,
getting that ordering wrong produces a plausible wrong value far from the cause
— *the exact bug shape CLAUDE.md's debugging section calls the expensive one*.
On wasm it cannot even be encoded: a `br` out of a block requires the operand
stack to match the block's type, so a call result cannot survive the branch the
check performs. Bad codegen fails `wasm-validate` instead of returning 4002 when
it should return nothing.

This was found by writing it wrong first — the prototype's draft printed garbage
on the unwind path — which is the honest way to have learned it and the reason
to trust it.

The general form: wasm's type-checked operand stack, explicit block types and
structured control flow make several whole categories of emitter bug
*unrepresentable* rather than merely wrong. That makes this target useful as a
**cross-check on the IR itself**, not only as a deployment story. An IR-level
mistake that six register backends encode happily will often refuse to encode
here, with a validator message and a byte offset. Budget for that being a
source of real bugs found in shared code — and file them into the owning lane,
never fix them here.

### External tools

`wasmtime` (runtime) and `wabt` (`wasm-validate`, `wasm2wat`) are **dev-only**
dependencies of this lane's tests. They are never build dependencies: we emit
binary wasm ourselves from `wasmenc.inc`, exactly as `x64enc.inc` emits x86-64,
and we never shell out to `wat2wasm`. The self-contained-toolchain property is
paid for everywhere else in this project and is not being spent here.

## Escalation

Same rule as everywhere: **escalate, don't guess.** A design fork this lane
cannot settle — anything about the shared escapes, the exception model, whether
a merge back is due — is a Track U `decide-*` ticket filed on `master`, not a
choice made quietly on a side branch where nobody can see it.
