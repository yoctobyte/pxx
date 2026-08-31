---
track: T
prio: 55
type: bug
status: backlog
blocked-by: []
summary: "gate.sh's stale_binary_hint compares compiler/pascal26's MTIME against the newest commit touching compiler/, so it only catches the sibling-landed-a-commit case. It is silent for a binary you built yourself and then reverted under (git stash, git checkout --), whose mtime is newer than every commit -- which is the commonest way an agent violates the precondition. Three lanes read three stale-binary REDs as a master miscompile on 2026-08-31; the hint fired for one of them."
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

**mtime cannot distinguish "built from these sources" from "built recently."**
The check fires only when the binary is OLDER than the newest commit touching
`compiler/`. A binary you built yourself five minutes ago from sources you have
since reverted is NEWER than every commit, so the condition is false and the
hint stays silent — while the binary is stale in the only sense the comparison
cares about.

That is CLAUDE.md's case 2 (*a reverted experiment*), and it is the likelier of
the two for an agent mid-fix, because reverting is something you do to yourself
on purpose. The hint catches case 3 (*a sibling landed a commit*) and nothing
else.

## Measured, 2026-08-31

Three sessions hit a RED on the same step within about twenty minutes, with the
identical signature (`byte 98, line 1`), by three different routes:

| lane | route | NOTE fired? |
| --- | --- | --- |
| frank-user-a | pulled a sibling's `compiler/**`, did not rebuild (case 3) | no — ran the script directly, bypassing gate.sh |
| coordinator | pulled mid-run (case 3) | **yes**, correctly |
| frankB | `git stash` — sources reverted, binary still built WITH the diff (case 2) | no, and it **could not have** |

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

**And it ships with a POSITIVE CONTROL** — a deliberately stale binary that the
check MUST classify as stale, asserted. The hint has been in `gate.sh` since
`87be2d98b` (2026-08-13), silent on the case-2 shape for that whole span, which
is the *guard that cannot fail* family: it never errored, it answered correctly
about mtime, and mtime was not the question. (Eighteen days, not "years" — the
first draft of this ticket said years and nobody had measured it.)

## Cheap mitigation available today, no code

`converged after N round(s)` already carries the answer. A fresh binary at a
settled tree converges in **1** round; **2 means the sources moved under the
binary.** Every one of the three REDs above printed 2. Worth putting in the
failure message itself, since the message currently offers "local seed
contamination, or a self-perpetuating miscompile" as the two explanations and
the actual cause is neither.
