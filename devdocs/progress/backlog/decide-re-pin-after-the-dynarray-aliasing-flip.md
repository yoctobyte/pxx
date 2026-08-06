---
summary: "The dyn-array aliasing flip (937c51dc2) is a codegen change, so gate.sh quick reads RED on its pinned-seeded fixedpoint step for EVERY lane until `pinned` is refreshed. Re-pin now, or wait for T's full matrix?"
type: decision
track: U
prio: 70
---

# Decide: re-pin now after the dyn-array aliasing flip, or wait for the matrix?

- **Type:** decision — **Track U**
- **Opened:** 2026-08-06 by the A+N session that landed `937c51dc2`.
- **Why escalated rather than decided:** `make pin` is the one action CLAUDE.md
  calls "the deliberate brake", and this is a semantics flip. Choosing either way
  imposes a cost on other lanes, so it is not an agent's call.

## The situation

`937c51dc2` removed the dynamic-array copy-on-write so `b := a` aliases, matching
FPC. It changes **emitted code**, and `tools/gate.sh quick` checks the self-host
fixedpoint by seeding stage A from `stable_linux_amd64/default/pinned`:

```
sh-A = pinned(compiler.pas)   <- OLD codegen, still emits the COW calls
sh-B = sh-A(compiler.pas)     <- new codegen
sh-C = sh-B(compiler.pas)
pass iff A == B == C
```

`sh-A` therefore comes out 138KB larger than `sh-B == sh-C`, and the step reports
FAIL. The real fixedpoint is intact — seeded from the new compiler, A==B==C is
byte-identical (6398664 bytes), and `make compiler/pascal26` converges — but
**every lane's `gate.sh quick` will read RED until `pinned` is refreshed.**

This is inherent to any codegen change, so it is presumably a recurring
situation, not new; the `chore(stable): pin vNNN` commits suggest re-pinning is
the routine answer.

## The fork

1. **Re-pin now** (`make stabilize` → `make pin`, commit `stable_linux_amd64/**`).
   Restores a meaningful gate for everyone immediately. Cost: Track B's ground
   becomes a compiler with the new dyn-array semantics *before* Track T's full
   matrix has swept it. If the matrix finds RTL fallout, B is building on it.
2. **Wait for the matrix, then pin.** B's ground stays proven. Cost: a red
   fixedpoint step in every lane's gate for as long as it takes, which trains
   agents to ignore a red gate — the worst possible habit for the one check that
   is safe-by-construction.
3. **`make stabilize` only** (moves `latest`, NOT B's ground). Records the
   checkpoint but does not fix the gate reading, since gate.sh seeds from
   `pinned`. Halfway, and does not buy the thing that hurts.

## Recommendation

**(1), re-pin now**, with (2) as the answer if the user would rather hold B still.
The evidence behind that: the change is verified against the FPC oracle on
x86-64 / i386 / arm32 / aarch64 (flat, nested, managed elements, record field,
SetLength-detaches, Copy-detaches), the entire dynarray/open-array test corpus is
green (39 tests, zero failures), and `testmgr --tier quick` is green. The
unswept surface is `lib/rtl` + `compiler/builtin` — the 63 dyn-array variables and
79 candidate whole-array assignments the original ticket scanned as an upper
bound and never resolved per-scope. That is real, and it is also exactly what
pinning would surface fastest, via Track B's own gates.

A cheaper hedge if (1) feels early: pin, and treat the first `lib-test`/`demos`
red as a revert-the-pin trigger rather than a fix-forward.

## Not part of this decision

The code is already pushed and T can see it. Nothing is blocked on this except
the gate's readability, so a slow answer costs only that.
