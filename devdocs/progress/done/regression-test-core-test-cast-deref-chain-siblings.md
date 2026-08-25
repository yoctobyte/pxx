---
prio: 70
track: P
status: done
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 5 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_cast_deref_chain_siblings.pas red at 0bc0cfac61a8 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-25T12:31:10Z
- **Test source:** test/test_cast_deref_chain_siblings.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_cast_deref_chain_siblings.pas'` at 0bc0cfac61a878e4da78348389458d180061c417

## Range
bad `0bc0cfac61a8`, last good `a28bc3993a0e`, 7 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1349025/test_cast_sib26  [code=64635B  data=2112B  bss=42532B  procs=128]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*


## RESOLVED 2026-08-25 — an arm that claimed the node and then could not answer

Row **b**, `PRec(raw)^.arr[1]^`, printed a raw pointer (`136260322590792`)
instead of `world`. The other four rows were fine.

Caused by `15ec54d7a`, which replaced the alias-cast suffix walk's
`NodePtrElem` call with the shared `ResolveDerefShape` so that the walk would
carry DEPTH (the `PPRec(pp)^^.f` fix). `ResolveDerefShape` answers more than
`NodePtrElem` for the shapes it knows — but it knows FEWER shapes: its
`AN_INDEX` arm only handles an `AN_IDENT` base, and row b's base is an
`AN_FIELD` (a `array[0..2] of PStr` field). That arm claimed the node, answered
`tyUnknown`, and the walk — having nothing else — fell back to the OUTER cast's
alias, which is exactly the per-site staleness `NodePtrElem` was written to end.

The trade was invisible in review because `ResolveDerefShape`'s FINAL else
already asks `NodePtrElem`; what it does not do is ask when one of its own arms
has already taken the node. It now asks whenever the chain came out
`tyUnknown`, wherever that happened. `NodePtrElem` carries no depth, so
`remDepth` stays 0 and exactly one level resolves — which is what these chains
did before the swap, so no shape regresses in the other direction.

> **The general lesson, and it is the second time this week.** Two predicates
> answer "what does `^` over this node yield": `NodePtrElem` (knows more
> SPELLINGS — it recurses an index into its base, and has FIELD, PTR_CAST and
> pointer-arithmetic arms) and `ResolveDerefShape` (knows more ABOUT each shape
> — depth and ultimate base). Swapping one for the other trades one kind of
> knowledge for the other, silently. They should be one function; that is the
> same finding as
> [[refactor-a-two-dyn-array-depth-functions-that-drift]], one type-family over.

No new test: `test/test_cast_deref_chain_siblings.pas` is the test, and it did
its job — the watcher had the failure filed within the hour.

Gate: `make compiler/pascal26` converged in 1 round, all five rows match,
`test_cast_deref_pointer_field` / `test_pointer_to_a_pointer_through_a_cast_and_a_forward`
/ `test_new_as_a_function_over_a_pointer_type` unchanged, `tools/gate.sh quick`
GREEN.
- 2026-08-25 — resolved, commit PENDING-COMMIT.
