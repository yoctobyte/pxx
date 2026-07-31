---
summary: "Pascal indexed-property setter statement fails to parse since the NilPy chained-subscript fix"
type: bug
track: P
prio: 85
---

# Indexed-property setter statement no longer parses (test-core RED on master)

- **Type:** bug (Pascal frontend / shared `parser.inc`) — **Track P** (edits A's
  shared ground: `compiler/parser.inc`, so obeys A's gate + no-concurrent-edit)
- **Status:** done
- **Opened:** 2026-07-31, from Track T tstate.

## What is red

Two Track-P core tests, red in every tier since they appeared:

- `test-core#src:test/test_indexed_property.pas`
- `test-core#src:test/test_property_redecl_b283.pas`

```
Expected: :=, but got:  (Kind: 78, Line: 40)
pascal26:40: error: unexpected token
  near: c      >>>  writeln
```

Repro (borg, sha `a9e9528c7f84`):

```
tools/testmgr.py --tier native --job 'test-core#src:test/test_property_redecl_b283.pas'
```

## Provenance

- First reported NEW-RED by the watcher at `0344760405e1` (tstate commit
  `dbf0de3aa`).
- Watcher bisect narrowed `test-core#src:test/test_indexed_property.pas` to
  **1 commit**: bad `d9c5eb4fadbf`, last good `9d3f9123b1c4`
  (tstate commit `dea92c047`).
- `test_property_redecl_b283.pas` bisect stands at 2 commits in the same range
  (tstate commit `6af787e91`) and shows an identical diagnostic — almost
  certainly the same cause.

`d9c5eb4fadbf` = *"fix(nilpy): chained subscript assignment stores into every
target, not just the last"* — a **Track N** fix that edited the **shared**
`compiler/parser.inc` (plus `pyparser.inc`, `Makefile`, a `.npy` test).

## Root cause (measured)

Hypothesis 1 below, confirmed by reading the actual dispatch rather than by
inference from the diff:

`compiler/parser.inc:19367` — the statement-level call site — decides whether
`ParseLValueAST`'s result is *already a statement* purely by node kind:

```pascal
valNode := ParseLValueAST(idx, TokPos - 2);
if (ASTKind[valNode] = AN_CALL) or (ASTKind[valNode] = AN_VIRTUAL_CALL) or
   (ASTKind[valNode] = AN_INTF_CALL) or (ASTKind[valNode] = AN_CALL_IND) or
   (ASTKind[valNode] = AN_IF) then
  node := valNode
else
begin
  Expect(tkAssign, ':=');    { <-- the `:=` was already consumed by the setter path }
```

The default-indexed-property setter path consumes its own `:=` and value. It
used to return the setter `AN_CALL`, which that test accepted. Since
`d9c5eb4fadbf` it returns an `AN_COMMA`, so `c[4] := 11;` falls to the `else`
and the parser demands a second `:=` — landing on the next token, `writeln`.
Exactly the observed diagnostic.

**Hypothesis 2 (the `tk` clobber) is dead**: `tk` is assigned immediately before
`Result := node; Exit`, so nothing reads it afterwards.

## Fix

Landed as **`e09febaf6`** — *"fix(core): gate chained-subscript-assign value
wrapping to NilPy only"*. `PyExprMode` gates the temp/`AN_COMMA` rewrite: NilPy
keeps Python's chained-assignment semantics, Pascal gets its plain setter
`AN_CALL` back. Pascal has no chained assignment, so the hidden temp bought it
nothing in the first place.

Confirmed by Track T: `f575b59cfde2` GREEN (native), with
`FIXED:test-core#src:test/test_indexed_property.pas,test-core#src:test/test_property_redecl_b283.pas`.

**Coordination note.** Two Track A agents worked this concurrently and produced
the same `PyExprMode` gate independently; `e09febaf6` is the one that landed, the
duplicate was discarded unpushed. The sole-A guard did not hold here — worth
remembering that a tstate RED is visible to every agent at once, so an unclaimed
regression attracts duplicate work. Claiming the ticket *before* touching shared
files is what would have caught it.

## Original hypotheses (kept for the record)

The changed hunk is in `ParseLValueAST`'s default indexed-property **setter**
path, which is shared: Pascal's `obj[i] := v` reaches it too, not only NilPy
subscripts. Two candidate mechanisms, both unverified:

1. **Return-node shape.** The path used to `Exit` returning the void setter
   `AN_CALL`; it now returns an `AN_COMMA` wrapping temp-assign + call + temp
   read. If the statement parser recognised "setter call ⇒ this statement is
   complete" by node kind, an `AN_COMMA` would fall through and it would then
   demand a `:=` — which is exactly the diagnostic.
2. **`tk` clobber.** The new code does `tk := IntToTypeKind(UPropTk[pri]);`,
   overwriting a local `ParseLValueAST` already uses on the Pascal paths.

Per `devdocs/dev/debugging-playbook.md`: **do not write either of these into the
fix commit as the root cause without measuring it** — `PXXDBG=a.ast:<proc>` on
`test_indexed_property.pas`, and diff the AST against `9d3f9123b1c4`.

## Fix direction

Keep the NilPy chained-assignment semantics (that fix is real — it closed silent
data loss), but make the temp/`AN_COMMA` rewrite apply only on the NilPy path,
or teach the statement parser to accept an `AN_COMMA` whose effect is a setter
call. Do not simply revert `d9c5eb4fadbf`.

## Notes

- Lane: the *bug* lands in P/A (shared parser + Pascal tests) even though the
  commit came from N — same rule as any cross-lane finding.
- Whoever takes this needs the **sole-A** confirmation, since `parser.inc` is
  A/P shared ground.
- Unrelated and separately tracked: `fpc-bootstrap#src:compiler/compiler.pas`
  (bad `b1976742df2c`) is also STILL-RED, and the cross-target
  `test-c-conformance-*` / `test-sqlite-threads-*` / `test-lua-cross` reds in
  the `full` tier at `a9e9528c7f84` are pre-existing, not from this commit.

## Log
- 2026-07-31 — resolved, commit e09febaf6.
