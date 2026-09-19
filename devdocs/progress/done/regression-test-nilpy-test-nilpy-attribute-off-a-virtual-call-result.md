---
prio: 70
track: N
status: done
---

> **Track guessed as N from the FAILING STEP** — line 5 of 8, `out=$(./compiler/pascal26 test/test_nilpy_qualified_name_error_names_the_receiver.npy /tmp/test_nilpy_qualrecv26 2>&1); `, which names `test/test_nilpy_qualified_name_error_names_the_receiver.npy`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 4 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 7 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_attribute_off_a_virtual_call_result.npy at 7e4f69a34350 in step 5/8, `out=$(./compiler/pascal26 test/test_nilpy_qualified_name_error_names_the_receiver.npy /tmp/test_nilpy_qualrecv26 2>&1);…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `883da23adb0a`).
  Untriaged.
- **Found:** 2026-09-10T11:02:15Z
- **Test source:** test/test_nilpy_attribute_off_a_virtual_call_result.npy test/test_nilpy_attribute_off_a_virtual_call_result.expected +2
- **Failing step:** line 5 of 8 of the job's recipe; it names `test/test_nilpy_qualified_name_error_names_the_receiver.npy`.
  ```
  out=$(./compiler/pascal26 test/test_nilpy_qualified_name_error_names_the_receiver.npy /tmp/test_nilpy_qualrecv26 2>&1); \ rc=$?; \ test "$rc" = "1" \ && printf '%s\n' "$out" | grep -q '^pascal26:14: error: no member Foo came of the qualifier strings .* (strings\.Foo)$' \ && test ! -e /tmp/test_nilpy
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_attribute_off_a_virtual_call_result.npy'` at 7e4f69a343501a4b71ef7cfb5033e90fe5e4bcd5

## Range
bad `7e4f69a34350`, last good `e1ba463ce0c1`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:36: error: this build would die at exec: `memcmp` is imported from libstrings.so, which no library on this machine answers to. That soname was not declared anywhere — the compiler derived it from the name of the header you imported (strings.h), and a header file name is not a library name. Name the library explicitly instead, with an `external '<soname>'` clause carrying the soname the loader wants.
(tail)
ok: /tmp/testmgr-scratch-2773303/test_nilpy_virtcall26  [code=1261336B  data=84472B  bss=55084B  procs=2020]
test_nilpy_qualified_name_error_names_the_receiver: FAIL - rc=1 (want 1, one error on line 14 naming the qualifier, no binary)
pascal26:36: error: this build would die at exec: `memcmp` is imported from libstrings.so, which no library on this machine answers to. That soname was not declared anywhere — the compiler derived it from the name of the header you imported (strings.h), and a header file name is not a library name. Name the library explicitly instead, with an `external '<soname>'` clause carrying the soname the loader wants.
  near: n      >>> static void bcopy 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-10 — the seven watcher saw `test-nilpy#src:test/test_nilpy_attribute_off_a_virtual_call_result.npy` GREEN at 16993f9196cf (tier full) and did NOT close this: the job's class is `corpus`, which testmgr treats as runtime-nondeterministic (RUN_RETRY_CLASSES) — a single pass does not refute a red there. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.

## CENSUS 2026-09-19 (frankS) — does not reproduce; closed by events

Run through **testmgr's own job runner**, using this ticket's exact `Repro`
line — the instrument that filed it, and the one auto-pin reads. Not through
`make`, and not through a hand-run of the fixture:

    tools/testmgr.py --tier full --job <this ticket's own literal job selector>
    ->  testmgr: GREEN, 1/1 pass

All **17** open NilPy regressions were run that way and all 17 came back GREEN.

**The census carries a positive control drawn from the same population**,
because seventeen greens from an instrument nobody has shown can fail are not
evidence. Same runner, same tier, on the xmlreader job — which is still built
by the PINNED compiler and therefore still broken — the identical form returns:

    expect_same: MISMATCH [lib_mimic_xmlreader.1]
    --- expected
    +++ actual
    @@ -1 +1 @@
    -25
    +24

    testmgr: RED

So GREEN here means the job passed, not that the runner is blind.

**This does not say the report was never real.** It was real at its filing sha;
the tree has moved past it. Closed as NOT REPRODUCING, so it stops occupying a
ranked slot and stops being dispatched to.

**Why a whole pile went stale at once, which is the part worth keeping:** these
are auto-filed by the Track T watcher, and the watcher DOES retire them — 19
open tickets have a twin in `done/` and every one of those twins carries the
line `auto-closed by the borg watcher`. The defect is narrower than "nothing
closes them": the auto-close WRITES the closed copy into `done/` and does not
remove the `backlog/` original. The duplicate then keeps a real prio, so it
goes on sorting alongside live work and a seat gets dispatched to a subject
that has been passing for weeks — and `progress.sh resolve` refuses it as an
ambiguous slug, which is how the pattern surfaced at all.
- 2026-09-19 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 9749340a2.
