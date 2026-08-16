---
prio: 70
status: done
---

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:test/lib_classes_tthread.pas red at 459e96f985d1 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-16T09:13:26Z
- **Test source:** test/lib_classes_tthread.pas

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:test/lib_classes_tthread.pas'` at 459e96f985d1588fac20836b151341cf7e967a61

## Range
bad `459e96f985d1`, last good `137a182ad46a`, 70 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:27: error: base type not found: TThread
(tail)
pascal26:27: error: base type not found: TThread
  near:  type TBumper  class  >>> TThread  public 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Resolved 2026-08-16 — two bugs, one red (Track A/P)

Not a threading bug at all. `classes.pas` re-exports TThread with a
unit-QUALIFIED class alias (`TThread = palthreadobj.TThread;`), and
`ParseTypeSection` registered a UClass alias row only for the UNQUALIFIED form —
its lookahead requires a semicolon right after the first identifier, so the
qualified shape fell through to the plain type-alias path and no alias row was
ever created. The re-export had always been a no-op; it was invisible only
because `uses` was transitive, so an importer found palthreadobj's row directly
through the leak. Closing the leak (2026-08-15, `VisibilityAllows`) is what made
the dead re-export observable — which is why this reads as a regression with a
70-commit range and nothing in the range touching threads.

Second, independent gap found on the way: `{$threadsafe on}` set `ThreadSafeMode`
but never defined `PXX_THREADSAFE`. That define is derived from the
`--threadsafe` FLAG in `PasApplyTargetDefines`, at option-parse time, long
before the directive is lexed — so the directive form left classes.pas's
`{$ifdef PXX_THREADSAFE}` gate false. The flag form compiled; the directive form
(what this test uses) could not.

Fixed in 341dbf99f (`QualClassAliasCi` + the directive define), pinned as v344
in 64e262c69 — lib-test builds on `pinned`, so the pin is what carries it.
Records and arrays already re-exported correctly through the qualified form
(verified); this was the class name table alone.

Gate: `make compiler/pascal26` + `tools/gate.sh quick` GREEN; the test builds
and prints CLASSESTHREAD OK with both the directive and the flag.
- 2026-08-16 — resolved, commit ae630bce2.
