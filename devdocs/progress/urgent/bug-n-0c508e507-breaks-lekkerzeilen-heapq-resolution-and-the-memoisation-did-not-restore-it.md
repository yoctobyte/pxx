---
track: N
prio: 90
status: open
type: bug
owner: frankB
blocked-by: []
summary: "BISECTED 2026-09-20 with controls: 0c508e507 (widening PyModuleGetattrsLiteral's inner term from the main file to every module range, a correct segfault fix) stops lekkerzeilen compiling — `pascal26:512: error: no member heapify came of the qualifier heapq` in world.py. Parent 24c2f18de compiles `ok:`; the follow-up memoisation 1fbe6e104 does NOT restore it, so a wrong answer was made faster rather than corrected. NOT the CWD and NOT the tree: frankuser's compiler run from a different root compiles it fine, both trees carry the same mimic_heapq.py, and no commit in the 44-commit gap touches heapq. Cross-check: building at the parent yields sha 55f1ef09492b, byte-identical to a compiler another seat built independently at the same source state, and that binary compiles the demo. THE FIX IS NOT A REVERT — the segfault fix is real and its two crash fixtures must keep passing; what is needed is the widened decider plus whatever makes a name bound by an import resolve again. The compiler's own error text states the mechanism: an import that bound nothing gives exactly this."
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
