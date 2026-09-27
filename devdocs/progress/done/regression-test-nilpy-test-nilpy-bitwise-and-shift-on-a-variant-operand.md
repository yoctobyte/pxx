---
prio: 70
track: P
---

> **Track guessed as P from the FAILING STEP** — line 3 of 3, `PXXDBG='p.fresh:*' ./compiler/pascal26 test/test_result_fresh_verdicts.pas /tmp/test_result_fresh_verdicts26 2>&1 | grep`, which names `test/test_result_fresh_verdicts.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 4 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **The SLUG names `test_nilpy_bitwise_and_shift_on_a_variant_operand`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `test_result_fresh_verdicts`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **This expectation records a REFUSAL** (TypeError). Before treating a converged bisect range as an accusation, check whether the named commit IMPLEMENTED the thing being refused -- a feature landing makes its own refusal test go red, and the bisect converges on it correctly. Not a verdict; the tool cannot decide this one.

> **origin/master has advanced 10 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_bitwise_and_shift_on_a_variant_operand.py at 2954d103babe in step 3/3, `PXXDBG='p.fresh:*' ./compiler/pascal26 test/test_result_fresh_verdicts.pas /tmp/test_result_fresh_verdicts26 2>&1 | gre…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `f35167cd4e55`).
  Untriaged.
- **Found:** 2026-09-27T19:42:44Z
- **Test source:** test/test_nilpy_bitwise_and_shift_on_a_variant_operand.py test/test_nilpy_bitwise_and_shift_on_a_variant_operand.expected +2
- **Failing step:** line 3 of 3 of the job's recipe; it names `test/test_result_fresh_verdicts.pas test/test_result_fresh_verdicts.expected`.
  ```
  PXXDBG='p.fresh:*' ./compiler/pascal26 test/test_result_fresh_verdicts.pas /tmp/test_result_fresh_verdicts26 2>&1 | grep -E '^PXXDBG p.fresh (TA\.|MakeA|PassThrough)' | diff -u test/test_result_fresh_verdicts.expected -
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_bitwise_and_shift_on_a_variant_operand.py'` at 2954d103babe782994f7e93b6433edb8157702ab

## Range
> **The named sha `2954d103babe` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `2954d103babe`, last good `f94424b44030`, 22 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-359195/test_nilpy_bitvar26  [code=565637B  data=107354B  bss=65276B  procs=2315  codeseg=569056B]
--- test/test_result_fresh_verdicts.expected	2026-09-25 14:22:10.365051641 +0200
+++ -	2026-09-27 21:29:31.640365846 +0200
@@ -9,5 +9,5 @@
 PXXDBG p.fresh TA.Named TRUE arg=-1
 PXXDBG p.fresh TA.NamedSelf FALSE arg=0
 PXXDBG p.fresh TA.Mixed FALSE arg=0
-PXXDBG p.fresh TA.ViaLocal FALSE arg=-1
+PXXDBG p.fresh TA.ViaLocal TRUE arg=-1
 PXXDBG p.fresh TA.OrNil TRUE arg=-1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-27 — auto-closed by the borg watcher: `test-nilpy#src:test/test_nilpy_bitwise_and_shift_on_a_variant_operand.py` passes at 9bd5d47ef746 (tier full); it was red at 2954d103babe. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
