---
prio: 70
track: A
status: done
owner: frankS
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_warn_ignored_directives.pas red at 83fb0ef72419 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T13:24:51Z
- **Test source:** test/test_warn_ignored_directives.pas tools/expect_same.sh

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_warn_ignored_directives.pas'` at 83fb0ef72419b46cf22dd1ce57885950574d69ef

## Range
> **The named sha `83fb0ef72419` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `83fb0ef72419`, last good `42fde2a7e025`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
expect_same: MISMATCH [test_warn_ignored_directives26.1]
--- expected
+++ actual
@@ -1 +1 @@
-6
+5

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Diagnosis and fix (frankS, at HEAD): NOT a regression — a stale expectation

The compiler is right and the test was left behind. The missing warning is
line 6, `cdecl`, and it stopped firing on purpose: `3af4f6380` gave a bodied
`cdecl` proc a genuine SysV prologue on x86-64 and `c5b8442e1` narrowed the
soundness reject to match (`feature-cdecl-bodied-sysv-prologue`). The warning's
own text is *"on this target the calling convention is not selectable per
routine"* — once x86-64 could select it, continuing to say that would have been
a false warning, so `pasparser_proc.inc:1225` gates it `TargetArch <>
TARGET_X86_64` with the narrowing written down beside it.

Five is correct natively. The other five targets keep the warning, so the same
file counts 6 cross-target; the suite runs it on x86-64.

Fixed by moving the Makefile expectation 6 -> 5 and writing the reason into the
test header, where `cdecl` is now named as a **second control** beside `Ok`.
The header also warns the next reader that a directive leaving this population
is the expected shape of progress here — so a future 4 is a stale expectation
before it is a regression, and `pasparser_proc.inc` is where to check.

Verified at HEAD: assertion .0 = 0 (silent without the flag), .1 = 5, .2 = 1/1.
No compiler change.
- 2026-08-30 — resolved, commit 969dae43b.
