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

## Update, same day: it broke a SECOND time, in the opposite direction

After the fix above landed, two lanes had fixed the same absence independently
and both landed, leaving the pair forward-declared twice. FPC rejects a repeated
forward as hard as a missing one:

```
pasparser_generic.inc(431,10) Error: Function is already declared Public/Forward
  "QualArgAliasName(const AnsiString):AnsiString;"
```

**This is the stronger form of the argument above.** It is not "the seed can
break". It is: **the seed breaks in two opposite ways — a missing forward and a
duplicate forward — and pxx tolerates both, so `make compiler/pascal26`
converges through either.** The self-host loop cannot see this class in either
direction, by construction.

`forwardlint` detects both, and names the *other* declaration site and the exact
FPC error text, which is what made the duplicate a two-line fix rather than a
bisect.

Instance count is now six across six lanes: Track R, frankwasm x2, frankC x2,
Track P (absence), and Track P again (duplicate).

**One further data point for option 2 (a hook) over option 1 (a documented
step).** One of the lanes that broke it *did* run `forwardlint` on the change —
and redirected its output to `/dev/null`, reading the `echo` after it. The tool
told it, at the right moment, in its own terminal, and the answer was discarded.
A documented step survives that; a hook that fails the edit does not.
