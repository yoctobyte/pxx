---
slug: task-t-a-makefile-recipe-that-is-not-valid-sh-passes-every-gate
track: T
prio: 25
type: task
status: backlog
blocked-by: []
owner: ""
summary: "Appending to a looped `test-core` recipe at an anchor INSIDE a `for arch ... done` continuation put a RED on origin for hours (`ebc0dcb4f`..`ca6b96843`: `sh: 17: Syntax error: \")\" unexpected (expecting \"done\")`), and five instruments were green because each is correct about something else -- `--job src:<file>` selects the recipe line for the file you NAME, `make compiler/pascal26` does not read test-core, `--tier quick` does not run it, and gate.sh quick's Makefile-assertion row checks that assertions can FAIL, not that a recipe is valid sh. The obvious mechanism was ATTEMPTED and measured not to work: `sh -n` over every logical recipe line gives 190 hits, essentially all regex mangling of `$(...)` across continuations -- a ~100% hit rate, as empty as a check that never fires. So the hard part is the CONTINUATION JOIN, not the `sh -n`. Filed as the residual frankB deliberately did not land, so the next person to have the idea starts from the 190 rather than from zero."
---

# A recipe line that `sh` cannot parse is green in every gate we own

`ebc0dcb4f` / `ce5a257d9` (frankB, Group 28) appended five fixtures to `test-core` at an
anchor that sat inside the qemu-user cross-target `for arch ... done` continuation. On
origin, for hours, `tools/testmgr.py --tier native --job src:test/test_nd_subarray_as_param.pas`
was RED with a **shell parse error** — an rc no test in the harness can produce. Fixed at
`ca6b96843`.

**The instrument that sees it is the job BEFORE the change** — the neighbouring row, which
nobody has a reason to run. A file-scoped selector is precisely the tool that cannot see it:
selecting by name is what makes each added row independent of the syntax around it. The
author's five new rows all reported PASS.

Playbook: `## THE FIFTH INSTRUMENT IS THE ROW YOU DID NOT ADD`.

## What was tried, and the number that matters

`sh -n` over every logical recipe line of the Makefile: **190 hits**, of which essentially
all are the joiner mangling `$(...)` across `\`-continuations rather than real defects.
frankB stopped there and did not file a gate row on that evidence, which is right — a check
with a ~100% hit rate is as empty as one that never fires, and it would have been a gate row
that every session learns to ignore in a week.

**So this ticket is not "add `sh -n`".** The measured gap is the CONTINUATION JOIN: producing
the logical line the shell will actually receive, with `$(...)`, `$$`, `@`/`-`/`+` prefixes
and `.ONESHELL` semantics handled, before handing anything to `sh -n`. Get the join right
and the `sh -n` is trivial; get it wrong and the hit rate tells you nothing.

## Candidate mechanisms, none measured

- **`make --dry-run` on the target and `sh -n` THAT** — make does the join for you, which is
  the whole difficulty, and it expands variables the way the real run will. Cost and whether
  it is safe to `-n` these targets is unmeasured.
- **A far narrower assertion instead of a lint**: for each looped recipe, check that its
  `for`/`done` and `if`/`fi` keywords balance per logical line. Cheap, no expansion needed,
  and it catches exactly the defect that landed. Lower value, near-zero false-positive rate.
- **Run the NEIGHBOUR** — make the discipline a habit rather than a check: after appending
  to a generated or looped recipe, run the row above the paste. Free, unenforceable, and it
  is what actually found this one.

## Scope note

Not a defect in `testmgr`. `--job src:<file>` answered correctly about the recipe line it was
given; the row it named was broken by its neighbour's syntax. Do not "fix" the selector.
