---
track: N
prio: 90
status: open
type: bug
owner: frankB
blocked-by: []
summary: "REJECTED 2026-09-20, SAME DAY, FALSE PREMISE — 0c508e507 is exonerated and nothing here was ever a compiler defect. I bisected the BINARY LOCATION, not the compiler version. Proof, one variable: sha 7e5bea1ba120c986 run in-tree gives `ok:`, the byte-identical copy of that same file run from a scratchpad gives `error: no member heapify came of the qualifier heapq`, and the `before` binary run in-tree also gives `ok:`. `--where` on the scratchpad copy reports every library root MISSING. Every failing arm I reported was scratchpad-located; every passing arm was in-tree. THE CONTROL THAT FOOLED ME VARIED TWO THINGS: running another seat's compiler from my root changed the compiler AND the binary's location together, so it could not separate them, and it returned the answer I expected. The byte-identical-sha cross-check on the parent was real and made it worse, lending its credibility to the half nobody checked — a sha identifies the binary and says nothing about where it was run from. Kept loaded rather than deleted so the citation resolves and so the hazard is findable: see devdocs/dev/debugging-playbook.md, a relocated binary whose CWD fallback resolves ENOUGH to fail later with a credible domain error."
---

# `0c508e507` breaks lekkerzeilen's `heapq.heapify`

Reproducer, ~19 s to the error:

```
./compiler/pascal26 --threadsafe -dSDL_DISABLE_IMMINTRIN_H -dGL_GLEXT_PROTOTYPES \
  /home/neo/lekkerzeilen/lekkerzeilen/__main__.py /tmp/out
```

| compiler | result |
|---|---|
| `24c2f18de` (parent) | `ok:` |
| `0c508e507` | `error: no member heapify came of the qualifier heapq` |
| `1fbe6e104` (memoisation) | same error |

Owner is the commit's author, who is mid-flight in the file and has the
reproducer. Filed rather than fixed because two seats in one decider is the
collision git cannot see, and only the author knows which half of the change is
load-bearing.
