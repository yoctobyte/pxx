---
prio: 70
track: P
---

> **Track guessed as P from the FAILING STEP** — line 1 of 8, `./compiler/pascal26 -Futest/generic_xunit_method_units test/test_generic_method_across_a_uses_clause.pas /tmp/test_gen_x`, which names `test/test_generic_method_across_a_uses_clause.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 7 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_generic_method_across_a_uses_clause.pas at d11b8a1a99dd in step 1/8, `./compiler/pascal26 -Futest/generic_xunit_method_units test/test_generic_method_across_a_uses_clause.pas /tmp/test_gen_…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-06T06:24:39Z
- **Test source:** test/test_generic_method_across_a_uses_clause.pas test/test_generic_routine_type_parameter_arity.pas +5
- **Failing step:** line 1 of 8 of the job's recipe; it names `test/test_generic_method_across_a_uses_clause.pas`.
  ```
  ./compiler/pascal26 -Futest/generic_xunit_method_units test/test_generic_method_across_a_uses_clause.pas /tmp/test_gen_xmeth26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_generic_method_across_a_uses_clause.pas'` at d11b8a1a99dda7d388c66ecfa43889f89b7e9a58

## Range
bad `d11b8a1a99dd`, last good `655e32b1256d`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:10: error: this token is not a class member: expected a field, method, property, a visibility section, var/class/type, or end
(tail)
pascal26:10: error: this token is not a class member: expected a field, method, property, a visibility section, var/class/type, or end
  in: test/generic_xunit_method_units/uxgm.pas
  near: : String ) : String ; >>> class generic function 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-06 — auto-closed by the seven watcher: `test-core#src:test/test_generic_method_across_a_uses_clause.pas` passes at ddd0d63e188b (tier native); it was red at d11b8a1a99dd. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
