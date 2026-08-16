---
prio: 70
track: P
status: done
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_typed_const_record.pas red at 406a40dfaffa (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-16T18:02:23Z
- **Test source:** test/test_typed_const_record.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_typed_const_record.pas'` at 406a40dfaffa9dbea2077cd1319605670801233f

## Range
bad `406a40dfaffa`, last good `17f671533234`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2793116/test_tc_record26  [code=54928B  data=1544B  bss=9524B  procs=113]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## 2026-08-16 — RESOLVED, fixed in 9cf91cf8d

Mine, from 406a40dfa. `C: Char = 'Z'` in a typed record constant stored the
wrong bytes and printed garbage.

**Cause.** That commit taught the record-constant parser to accept string
literals, `@proc` and `@var` — value forms the emitter had always implemented and
only the C frontend produced. The string arm keyed on the TOKEN. A single-char
literal is `tkString` as a token and an ORDINAL as a value, and ConstEvalFactor
has always special-cased it as the latter, so the new arm claimed `'Z'` before
the ordinal path saw it. The arm now requires a string-typed destination: the
token cannot decide this, only the field type can.

Worth keeping: `tkString` is a *true* fact about that literal. It was still the
wrong thing to branch on — a true fact standing in for the deciding one, which
is a failure mode no amount of double-checking the condition would have caught.

**Gate note (not a gap to close).** `gate.sh quick` was GREEN before and after
the bad commit, because `test-core` is not in the quick tier. Nothing local could
have seen this; the offloaded sweep is what caught it, about fifteen minutes
after the push, and the event named the file so no bisect was needed. That is the
confirm-native/offload-the-matrix split working as designed, and it argues
against widening `quick` in response.

**Regression test.** `test/test_record_const_addr_field.pas` now carries BOTH
halves of the ambiguity side by side — the same `'Z'` literal in a `Char` field
and an `AnsiString` field — since asserting either one alone is exactly what let
this through.

Verified: the test passes at HEAD, its four record-constant neighbours re-checked
by value, output identical to fpc 3.2.2 -O1 -Mobjfpc, self-host fixedpoint
converged.
- 2026-08-16 — resolved, commit 5e2e470d4.
