---
prio: 70
track: P
status: done
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 9 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_operator_implicit_shortstring_b356.pas red at 203438d2cf63 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-24T19:22:37Z
- **Test source:** test/test_operator_implicit_shortstring_b356.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_operator_implicit_shortstring_b356.pas'` at 203438d2cf6306c543194034cc6980662e5c23bf

## Range
bad `203438d2cf63`, last good `6d2af7ca7c23`, 7 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:27: error: incompatible types: cannot assign record to string[N]
pascal26:30: error: incompatible types: cannot assign record to string[N]
(tail)
pascal26:27: error: incompatible types: cannot assign record to string[N]
pascal26:30: error: incompatible types: cannot assign record to string[N]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

---

# Triaged and fixed 2026-08-24 — false positives from the new assignment check

All three reds are the same cause: `497fc8e78` started type-checking assignments
(`bug-p-an-assignment-is-not-type-checked-at-all`), and the rule refused two
shapes it should never have seen.

- **A user-defined IMPLICIT conversion.** `operator :=(a: TFoo): Integer` and
  Delphi's `class operator Implicit(...): TString80` both register under
  `Ord(tkAssign)` keyed on the operand type, so `i := a` and `s := t` are
  conversions, not the record-into-scalar store the kind check refuses. The
  check now stands down when either side has such an overload
  (`AssignHasConversionOperator`), and deliberately NOT for `OPK_EXPLICIT` —
  an explicit operator is what a CAST invokes, and FPC refuses the bare
  assignment exactly as this does.
- **`Default(T)` lied about its type.** For every non-aggregate T the arm built
  an `AN_INT_LIT 0` tagged `tyInt64`, so `s := Default(string)` reported
  "cannot assign Int64 to AnsiString". The tag was wrong before the check
  existed; the check just made it visible. Zero of a string is `''` and zero of
  a class or pointer is `nil`, so the arm resolves the type (`ParseTypeKind`)
  and builds the node the literal would: `c := Default(TCls)` is now exactly
  the node `c := nil` builds. Aggregates keep their materialised zeroed static.

The 625-pair fpc differential is unchanged by both escape hatches — still 416
accepted, 202 tightenings, **0 regressions** — so the diagnostic did not lose
any of its reach.
- 2026-08-24 — resolved, commit 1174c2f54.
