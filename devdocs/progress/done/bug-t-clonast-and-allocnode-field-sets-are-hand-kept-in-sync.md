---
track: T
prio: 45
type: bug
summary: "`CloneAST` copies AST-indexed slots by hand, one assignment per field, and nothing checks that list against `AllocNode`'s. On 2026-09-06 it was missing TWO: `ASTEnumId` (now the semantic-identity carrier) and `ASTCLongRank`. Both fixed; the guard was not. Wanted: a devtest asserting that the set of AST-indexed fields `CloneAST` writes equals the set `AllocNode` initialises, DERIVED FROM SOURCE rather than hand-listed -- same shape as tools/ast_slot_overloads.py and test/ast_slot_writes.expected, which already parse compiler/*.inc for exactly this kind of census. A hand-listed expectation would reproduce the defect it is guarding against."
status: done
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

## 2026-09-06 (frankA) — done, both sides derived from source

`tools/clone_ast_field_sets.py` extracts the two sets out of
`compiler/ast_arena.inc` — `AST*[ASTNodeCount] :=` inside `AllocNode`,
`AST*[Result] :=` inside `CloneAST` — and diffs them. Today: 20 slots, 19
assigned by CloneAST, `ASTKind` carried otherwise (CloneAST passes it into
`AllocNode`, so the allocation carries it), none missing. Wired into
`gate.sh quick` and the Makefile beside `ast_slot_overloads.py --self-check`,
which is the other declaration in the same file that goes stale silently.

**No expected-field list anywhere.** The ticket asked for that and it is worth
saying why it matters: a hand-written list would be a THIRD copy of the thing
that was already wrong twice, and — the part that decides it — **it would have
passed on 2026-09-06**, because whoever wrote it would have transcribed the
list from CloneAST, which was already missing both slots.

**`ASTLeft` and `ASTRight` are deliberately NOT exempted**, though they are the
obvious candidates: they are payload slots, cloned or copied per
`ASTLeftIsChild`/`ASTRightIsChild` rather than assigned plainly. They need no
exception because CloneAST assigns them either way, and listing them anyway
would excuse a future CloneAST that dropped the payload handling entirely. An
exception that is not needed is a hole, not tidiness — there is a devtest case
asserting exactly that (`t_a_payload_slot_is_NOT_excused`).

Six devtest cases, each against a scratch arena built to make its branch fire,
because the live file passes and a suite that only ran the real thing would
print OK for a checker broken since it was written — the same shape as the
docstring that hid the omissions. The controls are the REAL defect, not a
synthetic one: one case deletes exactly the `ASTSemId` line that was missing,
and another deletes both it and `ASTCLongRank`, because **the original bug was
two omissions at once and a guard that reports the first and stops hands its
reader a repair that leaves the tree still broken.** Also covered: a stale
exception naming a slot `AllocNode` no longer initialises, and a renamed
routine reporting CANNOT SCOPE (exit 2) rather than passing over an empty set.

That last one is not hypothetical — the first run of the tool hit it, because
the header regex lacked `re.M`. It reported "CANNOT SCOPE … this is not a pass"
instead of "0 missing", which is the whole reason the third state is there.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit c0c3d7979.
