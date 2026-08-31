---
track: T
prio: 55
type: bug
status: backlog
blocked-by: []
summary: "gate.sh's stale_binary_hint asks a WORKING-TREE question (is this binary built from these sources) using GIT-HISTORY inputs (mtime vs the newest commit touching compiler/), so it can only ever see divergence that has been COMMITTED. Measured: an uncommitted edit under compiler/ leaves BOTH its inputs byte-identical, so its output is provably independent of the thing it detects -- it is blind to the entire uncommitted present, which includes every agent between a build and a commit. Three lanes read three stale-binary REDs as a master miscompile on 2026-08-31; the hint fired for one."
owner: frank-user-a
---

# The gate's binary-freshness check cannot see the common case

`tools/selfhost_fixedpoint.sh` compares the fixedpoint reached from the PINNED
seed against `compiler/pascal26` **as it sits on disk**. That comparison is only
meaningful if the on-disk binary was built from the current sources, and nothing
establishes that it was. `tools/gate.sh:107-119` tries:

```sh
stale_binary_hint() {
  newest=$(git log -1 --format=%ct -- compiler/)
  binmt=$(stat -c %Y compiler/pascal26)
  if [ "$binmt" -lt "$newest" ]; then ... NOTE: STALE BINARY ... fi
}
```

**The hint's inputs are GIT HISTORY; its question is about the WORKING TREE.**
(frankT's framing, and it is sharper than the two-cases one this ticket was
filed with.) It can therefore only ever see divergence that has been
**committed**. Everything uncommitted is invisible to it, in one direction, by
construction — not as a gap to be narrowed by a better timestamp rule.

**Positive control, constructed 2026-08-31** — frankT identified the property
from the two commands and explicitly did not build the case, so here it is
built. Clean tree, freshly built binary, then one uncommitted comment line
appended to `compiler/ir_codegen.inc` and nothing rebuilt:

```
clean tree, fresh binary:   newest=1788194998  binmt=1788195276  -> silent
+ uncommitted edit,
  never rebuilt:            newest=1788194998  binmt=1788195276  -> silent
                            (git status: M compiler/ir_codegen.inc)
```

**Both inputs are byte-identical across the two runs.** The guard's output is
not merely wrong here, it is *provably independent* of the condition it exists
to detect: `git log -1 --format=%ct -- compiler/` cannot observe an uncommitted
change, and the binary's mtime is unaffected by editing a source. So it cannot
fire for ANY uncommitted edit, whatever the values happen to be — which is the
*a guard that cannot fail is not a guard, and it prints PASS* family.

The population this blinds it to is not exotic. It is **every agent between
`make compiler/pascal26` and `git commit`** — the normal working state, not an
error. Build-then-revert (`git stash`, `git checkout --`, CLAUDE.md's case 2) is
one instance of it; frankB's was another. The one case it does catch is case 3,
a sibling landing a commit, where the divergence is by definition committed.

## Measured, 2026-08-31

Three sessions hit a RED on the same step within about twenty minutes, with the
identical signature (`byte 98, line 1`), by three different routes:

| lane | route | divergence committed? | NOTE fired? |
| --- | --- | --- | --- |
| frank-user-a | pulled a sibling's `compiler/**`, did not rebuild | yes | no — ran the script directly, bypassing gate.sh |
| coordinator | pulled mid-run | yes | **yes**, correctly |
| frankT | same sibling route, on plexus | yes | **yes** — `newest=1788191922` (17:58:42) vs `binmt=1788144713` (04:51) |
| frankB | `git stash` — sources reverted, binary still built WITH the diff | **no** | no, and it **could not have** |

The "committed?" column is the whole finding: the hint fired in every row where
the divergence had landed in git, and in none where it had not.

It was read as a master miscompile and escalated as one: *"nobody can pass the
pin gate today"*, with a pin held. There was no miscompile. Same tree, same
commit, same box:

```
tree c2545bd6a, binary 886f5397f26e  -> exit 1, differs at byte 98
make compiler/pascal26               -> converged after 2 round(s), 3d5308a75742
tree c2545bd6a, binary 3d5308a75742  -> exit 0, agrees
```

Cost: three sessions' investigation, an innocent commit named as the only
suspect, and a claim relayed to five lanes that the divergence between
`compiler/builtin/builtinheap.pas` and its frozen pinned copy was "sufficient on
its own" to cause it. That last was refuted by timing — the divergence dates
from 15:15, three hours before two GREEN gate runs.

## Why "clean tree" felt like a control to all three of us

`compiler/pascal26` is **untracked**, so `git status` says nothing about it.
Every instrument any of us reached for reported on the tree; the binary is the
one thing none of them could see. CLAUDE.md already says this in as many words —
*"A CLEAN TREE IS NOT EVIDENCE ABOUT THE BINARY"* — and three agents who had all
read it walked into it the same evening, which is the argument for changing the
construction rather than the documentation.

## The fix, and the shape it must not take

**Not a better mtime rule.** Any timestamp comparison has the same blind spot.
Establish provenance instead:

- record the sha256 of the binary the suite is about to test, and of a build of
  the current sources, and say plainly when they differ; or
- have the build stamp the sources it came from and have the gate read that; or
- refuse to compare at all when provenance cannot be established, rather than
  comparing and blaming the sources.

Whichever it is, keep the property the current comment is protecting: **gate.sh
must NOT silently rebuild before comparing**, or it loses the anti-Thompson
check, which is the entire point.

The history-vs-working-tree framing is what *argues* for provenance rather than
merely preferring it: naming the sources that produced the binary answers a
working-tree question with a working-tree fact. Any mtime-vs-commit rule is
answering a question about history, however it is refined, and the thing being
asked about lives in the tree.

**And it ships with a POSITIVE CONTROL** — a deliberately stale binary that the
check MUST classify as stale, asserted. The hint has been in `gate.sh` since
`87be2d98b` (2026-08-13), silent on the case-2 shape for that whole span, which
is the *guard that cannot fail* family: it never errored, it answered correctly
about mtime, and mtime was not the question. (Eighteen days, not "years" — the
first draft of this ticket said years and nobody had measured it.)

## The same mechanism one layer down: `make compiler/pascal26` can print proof without building

Raised by the coordinator, whose own diagnosis of it went into dispute with
frankB and is NOT what is recorded here. This is the narrow version,
constructed locally and confirmed against the recipe.

`Makefile:307-319`. The `$(COMPILER)` rule depends on the sources AND on
`$(COMPILER_STAMP)` (`compiler/.pascal26.fixedpoint`), and its recipe is only a
verification:

```make
have=$(sha256sum $(COMPILER)); want=$(sed -n 's/^sha256 //p' $(COMPILER_STAMP))
if [ "$have" != "$want" ]; then ... "Something replaced the binary without rebuilding." exit 1
echo "self-host fixedpoint: verified — $(sed -n 's/^rounds //p' STAMP) round(s), $(want | cut -c1-12)"
```

So when mtimes say there is nothing to do, `make compiler/pascal26` **does not
build**, and prints:

```
self-host fixedpoint: verified — 1 round(s), 3d5308a75742
```

Measured, clean tree, binary `touch`ed so it is newer than every source: no
build ran, the binary's sha was unchanged, and that single line was the entire
output.

**Both numbers in that line come from the stamp, not from a build.** Positive
control: forge `rounds 1` to `rounds 7` in the stamp, leave the sha correct, and
`make` prints `self-host fixedpoint: verified — 7 round(s), 3d5308a75742`. The
round count is replayed verbatim; it is not a measurement of anything.

**What the line therefore does and does not prove.** The sha guard is a real
PROVENANCE check and it works — it caught a swapped binary in frankB's test, and
it is precedent that the fix proposed above already exists twenty lines away in
this repo. But the pair only proves *this binary was once a fixedpoint of some
sources* and *nobody has swapped it since*. **Nothing in it ties the binary to
the sources on disk now.**

### CLAUDE.md's prescribed tell is NOT broken — do not "fix" it

The coordinator's report said the documented tell *"does not discriminate"* this
case, because the line contains the words "fixedpoint", "verified" and a round
count. Measured, it discriminates perfectly:

```
real build:   grep -c 'converged after' -> 1     (plus the summary line)
no-op verify: grep -c 'converged after' -> 0     (summary line only)
```

CLAUDE.md says to grep for `converged after N round(s)`, and that string is
emitted by the BUILD, never by the verify recipe. The doc is correct as written
and needs no change. What is true is the weaker, human-factors claim: the
summary line *reads* like proof, so an agent eyeballing output rather than
grepping the prescribed string will be satisfied by it. That is an argument for
the verify line naming what it is ("stamp only — no build ran"), not for
rewriting the tell.

### Consequence for the round-count heuristic below

The round count is only evidence **on a line accompanied by `converged after`**.
On a no-op it is a stored historical number that can say anything. And frankB
showed the count cannot distinguish *stale* from *deliberately planted* even
when it is real — they seeded a wrong binary on a clean tree, got
`converged after 2 round(s)`, and converged correctly to `3d5308a75742`. So:

- **1 round** — your seed was already the fixedpoint;
- **2+ rounds** — your seed was not the answer; stale, planted, or wrong for
  some other reason, and the count does not say which;
- **no `converged after` line at all** — nothing was built and the number you
  are reading came out of a file.

frankB's seed-independence result is worth recording on its own: forced from a
deliberately wrong seed, a clean tree still converged to `3d5308a75742`, which
rules out "which binary seeded the round" as a mechanism for the REDs above.

## Cheap mitigation available today, no code

`converged after N round(s)` already carries part of the answer, with the
caveats in the section above: **1** means your seed was already the fixedpoint,
**2+** means it was not, and its ABSENCE means no build ran at all. Every one of
the REDs above printed 2. Worth putting in the failure message itself, since the
message currently offers "local seed contamination, or a self-perpetuating
miscompile" as the two explanations and the actual cause was neither.
