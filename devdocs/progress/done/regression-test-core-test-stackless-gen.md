---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_stackless_gen.pas red at dfac1da00b04 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-18T20:57:06Z
- **Test source:** test/test_stackless_gen.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_stackless_gen.pas'` at dfac1da00b04ad41b85996873b19ad4c767d37ca

## Range
bad `dfac1da00b04`, last good `9d96253f2c14`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:141: error: for-in generator: a variant argument needs pylib (pycell_new) in scope
(tail)
pascal26:141: error: for-in generator: a variant argument needs pylib (pycell_new) in scope
  near: mv  score     >>>  writeln  

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## COORDINATOR TRIAGE 2026-08-18 — very likely ALREADY FIXED; do not start on it

**Do not pick this up without re-verifying at HEAD first.** The evidence says it is
closed and Track T simply has not caught up:

- The red opened at `dfac1da00b04`, from the Nil Python generator work.
- **`f132f1f7e` — `fix(A): a Pascal 'var' generator argument is not a Nil Python
  variant` — explicitly names this test** and states it verified `test_stackless_gen.pas`
  compiles and prints the values its own source documents, with the fixedpoint +
  `gate.sh quick` green.
- **T's most recent run is at `78842fec8beb`, which does NOT include `f132f1f7e`**
  (`78842fec8` → `f132f1f7e` → the tstate commit). So the open red is tagged to a sha
  that predates the fix.

**Root cause, recorded because it is a reusable shape:** the variant-argument heap cell
added for Nil Python generators keyed on `Params[k].IsRef` — which is equally true of a
Pascal `var` parameter and of the by-ref `const record` a stackless generator takes. So
a plain Pascal generator was told it needed pylib's `pycell_new`, which a Pascal program
has no reason to have in scope. **One predicate answering a question it was not asked** —
the same identity-vs-kind family as `rec = FindUClass('TPyList')` standing in for "is
this a container". The fix asks for both facts (Nil Python **and** a variant) rather than
the one they share.

**`track: P` in the frontmatter is a watcher guess from the test filename and is wrong** —
the cause and the fix are both in `parser.inc`, i.e. Track A. Left in place rather than
edited, since the ticket should be resolved outright once T's next run confirms it.

**Action: wait for Track T's next native run, or re-verify at HEAD, then resolve.** Not
verified here to avoid a concurrent build while a worker holds the tree.

## Log
- 2026-08-18 — auto-closed by the plexus watcher: `test-core#src:test/test_stackless_gen.pas` passes at 18bcb92ffb8b (tier native); it was red at dfac1da00b04. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
