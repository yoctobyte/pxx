---
prio: 70
track: P
status: done
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_ptr_deref_vararg.pas red at b936d125601e (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-25T06:10:55Z
- **Test source:** test/test_ptr_deref_vararg.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_ptr_deref_vararg.pas'` at b936d125601ea26a9e570d65be152ff3a35d04a0

## Range
bad `b936d125601e`, last good `0626344011cf`, 6 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:37: error: this value cannot be indexed — only arrays, strings and pointers can (pa)
(tail)
pascal26:37: error: this value cannot be indexed — only arrays, strings and pointers can (pa)
  near:  pa     >>>   writeln 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
- 2026-08-25 — resolved, commit PENDING-COMMIT.

## Resolution (2026-08-25)

Self-inflicted, by `6cb98e361` (bug-p-ten-constructs-fpc-rejects-are-accepted-and-silently-wrong).
Two new diagnostics were guarded on the node's TYPE KIND, and a node's kind is
the wrong question for an array: an array-shaped node carries its ELEMENT kind,
and `TypeIsOrdinal` answers True for `tyPointer` (symtab.inc lists 17
deliberately — a pointer has a simple ordinal value). So a dynamic array read
as "an ordinal that is not an array" from both guards.

- the index guard now also requires `tk <> tyPointer` and `ASTKind[node] =
  AN_IDENT`, i.e. the FIRST subscript applied directly to the variable. `pa^[2]`
  and `g.m[i][j]` arrive with `idx` still naming the ROOT symbol while `tk` has
  walked down to the element type — the message did not even name the thing
  being indexed.
- the Length guard now asks the SYMBOL of a bare identifier operand instead of
  the node's kind. `Length(MakeDyn(3))`, `Length(gr.mm[0])` and `Length(pfx^)`
  are all chains and are all legal.

`test/test_indexing_length_for_new_inc_positive.pas` gained a row per shape, so
these cannot come back. Writing those rows found two further pre-existing
defects, both filed rather than papered over:
`bug-p-length-of-a-dereferenced-pointer-to-array-answers-zero` and
`bug-p-an-array-returning-call-cannot-be-indexed-directly`.

The lesson is root-cause-over-microfix's: "everything indexable has already been
claimed by an arm above" was reasoning, and it was wrong. The measurement that
would have caught it is the one that closed this — running the positive test
against fpc.
