---
summary: "Pascal indexed-property setter statement fails to parse since the NilPy chained-subscript fix"
type: bug
track: P
prio: 85
---

# Indexed-property setter statement no longer parses (test-core RED on master)

- **Type:** bug (Pascal frontend / shared `parser.inc`) — **Track P** (edits A's
  shared ground: `compiler/parser.inc`, so obeys A's gate + no-concurrent-edit)
- **Status:** urgent — native tier is RED on master
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

## Hypothesis (NOT yet measured — verify before acting)

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
