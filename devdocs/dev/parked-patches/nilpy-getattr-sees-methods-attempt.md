# nilpy-getattr-sees-methods-attempt.patch

Parked 2026-09-25 at the wrap-up, from a stash in the frank-user checkout
dated 2026-09-13. It adds 73 lines to compiler/pyparser.inc so that
getattr(o, "m") resolves a METHOD name as well as a field. The stash message
records the state: it "resolves but the value does not call", meaning the
lookup finds the method and the result is not yet callable. It is against a
2026-09-13 tree, so expect conflicts. Not measured against the current tree;
the method case may since have been covered by other getattr work, so check
before reviving.
