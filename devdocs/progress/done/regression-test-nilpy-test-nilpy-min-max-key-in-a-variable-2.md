---
prio: 70
track: N
status: done
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 25 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_min_max_key_in_a_variable.npy red at c4fba16e4675 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-30T08:19:21Z
- **Test source:** test/test_nilpy_min_max_key_in_a_variable.npy test/test_nilpy_min_max_key_in_a_variable.expected

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_min_max_key_in_a_variable.npy'` at c4fba16e467577c84148a805ea5f18c62a558262

## Range
> **The named sha `c4fba16e4675` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `c4fba16e4675`, last good `e46dbffaa80d`, 210 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2142329/test_nilpy_minmaxkey26  [code=1269528B  data=78339B  bss=51796B  procs=1870]
Unhandled exception: TypeError: expected a number, got object
--- test/test_nilpy_min_max_key_in_a_variable.expected	2026-08-13 07:14:25.147322024 +0200
+++ -	2026-08-30 10:10:38.534539237 +0200
@@ -4,8 +4,3 @@
 var-lambda 3 1
 bound 3 1
 inline-bound 3 1
-variant-container 3 1
-sorted [3, 2, 1]
-plain 1 3 1 3 1.5
-strings a b
-bylen a ccc

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

---

## Already fixed — this report predates the fix

Second auto-file of the same test, from a different watcher host (`plexus`; the
first came from `seven`). Not a second defect and not a reopen.

- tested sha `c4fba16e4675` — 2026-08-30 09:54:04 +0200
- fix `f5f361d74` — 2026-08-30 10:14:40 +0200

`git merge-base --is-ancestor f5f361d74 c4fba16e4675` is false, so the fix was
not in the tree the watcher measured. Verified PASS at HEAD (`daa4a9661`).

Cause, fix and the full receiver x key matrix are in
`regression-test-nilpy-test-nilpy-min-max-key-in-a-variable` (done/). The sibling
`...-key-none` stays BLOCKED on the literal-receiver defect and is deliberately
not closed by this.
- 2026-08-30 — resolved, commit PENDING-COMMIT.
