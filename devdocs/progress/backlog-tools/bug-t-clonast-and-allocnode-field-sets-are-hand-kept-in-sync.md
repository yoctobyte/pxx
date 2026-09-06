---
track: T
prio: 45
type: bug
summary: "`CloneAST` copies AST-indexed slots by hand, one assignment per field, and nothing checks that list against `AllocNode`'s. On 2026-09-06 it was missing TWO: `ASTEnumId` (now the semantic-identity carrier) and `ASTCLongRank`. Both fixed; the guard was not. Wanted: a devtest asserting that the set of AST-indexed fields `CloneAST` writes equals the set `AllocNode` initialises, DERIVED FROM SOURCE rather than hand-listed -- same shape as tools/ast_slot_overloads.py and test/ast_slot_writes.expected, which already parse compiler/*.inc for exactly this kind of census. A hand-listed expectation would reproduce the defect it is guarding against."
status: open
---

# CloneAST's and AllocNode's field sets are kept in sync by hand

`CloneAST` (`compiler/ast_arena.inc`) copies each AST-indexed array with its own
assignment. `AllocNode` initialises the same arrays. Nothing relates the two
lists, so a new AST-indexed field is copied only if whoever added it remembered
both places — and its header asserted, in prose, that the list was already
complete.

Two were missing when it was checked on 2026-09-06 (frankA's lead, no repro):
`ASTEnumId` and `ASTCLongRank`. Both now copied, and the completeness claim is
out of the header. See `devdocs/dev/debugging-playbook.md`, *"A HEADER SAYING
'THIS LIST IS COMPLETE' IS WHY NOBODY RE-DERIVES IT"*, for why the omission's
COST changed when `ASTEnumId` widened from a diagnostic aid into the carrier for
"integer kind, boolean semantics".

## What is wanted

A devtest that fails when the two sets diverge. The load-bearing constraint:
**derive both sides from the source.** `tools/ast_slot_overloads.py` already
parses `compiler/*.inc` to census slot writes per node kind and snapshots the
result in `test/ast_slot_writes.expected` with an `--update` flow; this is the
same instrument aimed at two functions instead of at node kinds.

A hand-written list of expected fields is **not** a guard here — it is a third
copy of the thing that was already wrong twice, and it would have passed on
2026-09-06.

Not every `AllocNode` field necessarily *should* be cloned; if any legitimately
should not, the exception belongs in a named, commented set in the tool, so the
next reader sees a decision rather than an absence.

frankA offered to file this; filed here so the playbook's citation resolves.
