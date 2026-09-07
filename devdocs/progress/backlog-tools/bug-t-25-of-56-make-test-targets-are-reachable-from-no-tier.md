---
track: T
prio: 45
type: bug
status: backlog
owner: ""
created: 2026-09-07
found-by: frankA
tags: [testmgr, tiers, coverage, enrolment]
blocked-by: []
summary: "25 of the Makefile's 56 `test-*` targets are reachable from NO tier root in tools/testmgr.py -- not named in quick/native/limited/full, and not a prerequisite (transitively) of anything that is. They run only when somebody types them. The list MIXES two populations that must not be closed together: targets that are deliberately manual because they need a toolchain this fleet does not have (test-esp-idf, test-fpc, test-sqlite-*), and targets that were simply never enrolled -- including three cross-target gates written in the last week (test-record-layout-cross-frontend, test-skeleton-frontends-cross-target, test-packrecords-c-gcc-oracle). This is the same enrolment hole test-nilpy was in (238 of 309 .npy files invisible to the watcher, 2026-08-01) and test-uforth after it, both recorded in testmgr.py's own comments -- so the hole is KNOWN to recur and nothing measures it."
---

# The census, and the method so it can be re-run

Reachability, not grep: start from every `"test-…"` string in `tools/testmgr.py`
plus every `$(MAKE) <target>` in the Makefile, then close over Makefile
prerequisites. Anything not in that closure is run by nobody but a human.

```python
# targets = every ^test-...: rule head in the Makefile
# rules   = target -> prerequisites, EXCLUDING .PHONY (it NAMES a target, it
#           does not RUN it -- counting it made the first pass report 4)
# roots   = testmgr tier strings + $(MAKE) invocations; close transitively
```

**`.PHONY` is the trap.** A first pass that treated `.PHONY: foo` as "something
depends on foo" reported 4 orphans instead of 25, and 4 looks like a rounding
error rather than a finding. The line is a declaration, not an edge.

Reachable from no tier root, 2026-09-07:

```
test-asm-emit          test-c                  test-c-abi-cross
test-c-abi-glibc-oracle test-c-conformance-cross test-c-float-const-cross
test-chess-perft       test-duktape            test-esp-bare
test-esp-idf           test-fpc                test-fpc-seed-checked
test-frozen            test-managed            test-nilpy-frozen
test-nilpy-managed     test-packenum-gcc-oracle test-packrecords-c-gcc-oracle
test-quickjs           test-record-equality-cross-target
test-record-layout-cross-frontend               test-skeleton-frontends-cross-target
test-sqlite-parity     test-sqlite-threads     test-wasm32
```

## The part that needs judgement, and it is why this is a ticket

**Unreachable is not the same as neglected**, and closing this by enrolling all
25 would be wrong. At least three groups are in there:

- **Deliberately manual, needs an absent toolchain** — `test-esp-idf`,
  `test-fpc`/`test-fpc-seed-checked`, `test-sqlite-*`, `test-duktape`,
  `test-quickjs`. Enrolling these makes a tier RED on every box that lacks the
  dependency, which is the failure mode `limited`'s "a box with no qemu can run
  it" promise exists to prevent.
- **Reachable only from a non-test root** — `test-managed` is a prerequisite of
  `stabilize-managed`, so it runs when somebody stabilises and never otherwise.
- **Genuinely dropped** — the three cross-target gates. A gate nobody runs is
  not a gate, and two of them were written specifically because a whole defect
  class is invisible on the 64-bit host.

So the deliverable is a DECISION per target plus a check that keeps the answer
honest, not a bulk enrolment.

## The check this is really asking for

Whatever the per-target answer, the recurrence is the finding: this hole caught
`test-nilpy` (2026-08-01) and `test-uforth` (2026-08-08), both of which
testmgr.py now documents in comments — and then caught three more targets
anyway, because a comment is not a check. A lint that lists every `test-*`
target reachable from no tier root, with an explicit allowlist of the ones that
are manual ON PURPOSE and WHY, converts "somebody remembered" into a row that
goes red when the next target is written.

The allowlist is the load-bearing half: without it the lint reports 25 findings
forever and gets muted, which is `[a guard that flags everything]`.
