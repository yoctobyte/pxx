---
prio: 60
track: U
status: backlog
owner: unassigned
---

# decide: should `forwardlint` join the mandatory per-fix loop?

## The fork

The FPC bootstrap seed has been broken on `master` **twice in one session**
(2026-08-30), by two different commits in two different lanes:

| commit | lane | missing forward |
| --- | --- | --- |
| `5c8de9442` | A | `CModuleOfTok` (fixed by `e1fed35b1`) |
| `3ee9a672f` | P | `QualArgAliasName`, `EmitQualAliasDecl` (fixed this session) |

Each left every lane's bootstrap red until someone happened to run
`tools/gate.sh quick`. Neither author did anything wrong by the documented loop.

## Why the per-fix loop cannot catch this, structurally

CLAUDE.md's loop is `make compiler/pascal26` + your repro, and it is emphatic
that this IS the byte-identical self-host fixedpoint. It is — and that is exactly
why it is blind here: **it self-hosts with the CURRENT binary and never asks FPC
anything.** pxx resolves across the unit, FPC resolves in source order, so a
call-above-body compiles, self-hosts, converges, and passes the whole documented
gate while the seed is dead. There is no error to wait for, which is the same
shape as the copied-in-seed no-op the loop already warns about.

`tools/forwardlint.py` catches it exactly, is **~5 seconds** (measured as step 2
of `gate.sh quick`, which reported `5s` next to a `91s` fixedpoint), needs no
build, and has no false positives in this repo's history that I can find — the
one apparent FP this session (`CBlockContinues`) was a real break already fixed
upstream between my two runs.

## Options

1. **Add `forwardlint` to the mandatory per-fix loop** for any `compiler/**`
   edit. +5s on a ~12s loop. Recommended.
2. **A PreToolUse/PostToolUse hook** that runs it after an edit under
   `compiler/**` — the `a-documented-trap-is-not-a-guard` shape: make the mistake
   unexpressible rather than documented. Strongest, but hooks are repo-wide
   policy and this repo already gates edits with `no-full-suite.sh`, so the
   precedent exists.
3. **Leave it in `gate.sh quick`** and rely on agents choosing to run quick after
   touching a frontend include. This is the status quo, and it is what produced
   two breaks in one day.

## Recommendation

**Option 1, and option 2 if the user wants it enforced rather than advised.**
The cost is 5 seconds against a break that is fleet-wide, silent, and blocks the
bootstrap for every lane including a fresh clone. Option 3 has now been measured
twice and lost twice.

Filed by frankA rather than acted on: the per-fix loop is CLAUDE.md's single
source of truth for gating, so widening it is a user decision, not an agent's.
