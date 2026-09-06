---
track: A
prio: 50
type: bug
blocked-by: []
status: done
owner: frankD
created: 2026-09-06
summary: "Every semantic diagnostic raised while lowering a node from a `uses`d unit printed `pascal26:0:` with no line, no `in: <file>` and no `near:` window. Not three losses — `ErrorPrintAt` drives all three off the line number, so a zero erases the entire locating apparatus at once. Cause: `ASTLine` was deliberately 0 for nodes from an appended unit, a correct DWARF decision (the RTL, pylib and unit bodies must contribute no line-table rows or the whole runtime lands in the table) that was ALSO serving as the coordinate for ErrorAt/ErrorAtRecover. One field, two unrelated jobs. Corpus work is entirely used units, so this hit every semantic error in every one of them: fcl-passrc pastree.pp reported a real miscompile with no coordinate in 5947 lines. FIXED 2026-09-06 by splitting the jobs — AllocNode always stamps the real line, and `ASTFile = 0` (carried into IRFile) now means 'not in the line table', checked in DbgRecordRow."
---

# A semantic diagnostic in a used unit has no location at all

- **Type:** bug (diagnostics + debug info) — **Track A**
  (`compiler/ast_arena.inc`, `compiler/ir.inc`).
- Found in fcl-passrc rung 7, [[feature-pascal-corpus-expansion]].

## The measurement, both positions in one run

The same statement — `r := p`, a Pointer stored into a record, refused by the
AN_ASSIGN kind check:

| where | reported as |
| --- | --- |
| line 30 of a program | `pascal26:30: error: incompatible types: cannot assign Pointer to record` |
| line 18 of a `uses`d unit | `pascal26:0: error: incompatible types: cannot assign Pointer to record` |

A **parse** error cannot see this defect — it is reported off the lexer's own
position and never lost its coordinate — which is why the corpus rungs kept
producing usable line numbers right up until one didn't.

## Why one field was doing two jobs

`AllocNode` stamped `ASTLine := 0` for any token past `DbgMainTokEnd`, and the
reason is good: the Pascal RTL, pylib and unit bodies nobody wants to step
through must contribute **no line-table rows**, or the whole runtime lands in
the table. `DbgRecordRow` enforced it by testing `IRLine[i] = 0`.

`ErrorAt`/`ErrorAtRecover` take the same field. So the DWARF answer to "should
this appear in the line table" was silently answering "where is this?" as well.

## Resolution 2026-09-06 — split the two questions

- `AllocNode` always stamps `ASTLine := CurTok.Line`.
- `ASTFile = 0` is the new spelling of "not in the line table"; it rides into
  `IRFile` through the existing `CurLowerFile` propagation.
- `DbgRecordRow` exits on `IRFile[i] = 0`.

## The control, and it is the half that can regress silently

A diagnostic losing its line is loud the first time someone hits it. **The RTL
leaking into the line table is invisible unless you count** — `readelf` does not
complain and gdb resolves happily to the wrong text. Measured with the new
guard removed on purpose, on an eight-line program that `uses` a one-function
unit:

| | line rows | highest line claimed |
| --- | --- | --- |
| with the guard | **6** | 6 |
| without it | **3663** | 6290 |

6290 is the RTL's own line number, attributed to a file with eight lines in it.
That is now `tools/dwarf_smoke.sh` T5, with a deliberately loose bound: what it
must catch is a flood, and a threshold near the true count would be a
maintenance tax on a legitimate extra row.

## Fixtures

`test/test_a_semantic_diagnostic_in_a_used_unit_has_a_line.pas` plus
`test/pascal_units/{unit,driver}_a_semantic_error_in_a_unit.pas`, both
positions asserted in the Makefile. **The assertion is the COORDINATE, not the
message** — the text was correct throughout the defect, so a row asserting it
passed the whole time.

## Log
- 2026-09-06 — fixed and resolved; see the commit carrying this file.
