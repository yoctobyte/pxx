---
prio: 70
track: A
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 7 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_opt_store_reload.pas red at c951ec710b33 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T05:52:56Z
- **Test source:** test/test_opt_store_reload.pas tools/expect_same.sh

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_opt_store_reload.pas'` at c951ec710b33da734e7141394258135689c3e5fa

## Range
> **The named sha `c951ec710b33` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `c951ec710b33`, last good `08cbfa20a11d`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
expect_same: MISMATCH [test_opt_sr_O0.4]
--- expected
+++ actual
@@ -15,3 +15,5 @@
 br between
 br after neg
 mem   -112 -112 -110
+reord 635218
+reord2 635317

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## 2026-08-30 (coordinator) — RETRACKED P → A (O-flavoured), on the diff's own content

Auto-filed as **P** from the test path; the banner in this ticket says the
frontmatter is what the ranker reads, so the guess decides the owner. It is wrong.

The mismatch is two lines the actual output has and the expectation does not:

```
+reord 635218
+reord2 635317
```

Those are emitted by `test/test_opt_store_reload.pas:153` and `:161`
(`WriteLn('reord ', Int64(qh))`). The subject is **store/reload reordering** —
codegen and the `-O` pipeline, i.e. Track **A** under the **O** work-tag, which by
CLAUDE.md is file-owned by A and obeys A's gate. The Pascal frontend is not
involved at any point.

**Read the two candidate causes before fixing**, because they want opposite
changes and the diff alone cannot tell them apart: either the optimizer's
behaviour changed and the new lines are a real regression, or the test grew two
`WriteLn`s and its expectation was never regenerated. **The second one is the
quiet case** — it leaves a permanent red that looks like a codegen bug and wastes
whoever picks it up. Check `git log -- test/test_opt_store_reload.pas` and the
expectation file's mtime first; that is one command and it decides which bug this
is.

Standing, not flaky: STILL-RED on every native report from 06:57Z to 08:45Z. The
attributing sha `c951ec710b33` is a `diag(N)` commit and the earlier one is a
`tstate-ticket` commit — **neither can be the cause**; a tstate red attributes to
the sha it swept.
