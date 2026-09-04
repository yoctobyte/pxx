---
prio: 70
track: N
status: done
---

> **Track guessed as N from the FAILING STEP** — line 1 of 2, `./compiler/pascal26 test/test_nilpy_c_pointer.npy /tmp/test_nilpy_c_pointer26`, which names `test/test_nilpy_c_pointer.npy`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_c_pointer.npy at 25b8325d4b83 in step 1/2, `./compiler/pascal26 test/test_nilpy_c_pointer.npy /tmp/test_nilpy_c_pointer26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-02T11:23:25Z
- **Test source:** test/test_nilpy_c_pointer.npy tools/expect_same.sh
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/test_nilpy_c_pointer.npy`.
  ```
  ./compiler/pascal26 test/test_nilpy_c_pointer.npy /tmp/test_nilpy_c_pointer26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_c_pointer.npy'` at 25b8325d4b832de70e4ff573533882edd95e0dca

## Range
> **The named sha `25b8325d4b83` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `25b8325d4b83`, last good `cdae8cf6580b`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:7: error: C #if: expected ':' in conditional expression
(tail)
pascal26:7: warning: #include <bits/libc-header-start.h> resolved from the host system (/usr/include), not pxx's own headers — ABI/macro mismatches (e.g. va_list, M_SQRT2) may silently misbehave
pascal26:7: warning: #include <bits/floatn.h> resolved from the host system (/usr/include), not pxx's own headers — ABI/macro mismatches (e.g. va_list, M_SQRT2) may silently misbehave
pascal26:7: error: C #if: expected ':' in conditional expression
  near: import stdlib >>>  p = 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

## Already fixed, three hours after it was filed (frankA, 2026-09-04)

Fixed by `0da8a0ae4` — *fix(c): a NilPy `import <name>` found the host's header,
never crtl's*.

### The ordering, checked rather than assumed

- tested (red) at `25b8325d4b83`, **2026-09-02 11:19Z**
- fix `0da8a0ae4` landed **2026-09-02 14:31Z**
- `git merge-base --is-ancestor 0da8a0ae4 25b8325d4b83` → **not an ancestor**,
  i.e. the fix was NOT in the tested tree.

That ordering is the whole claim. A green at HEAD alone would not have been
worth anything here, for a reason this same run demonstrated six times over: the
log tail is full of

```
warning: #include <bits/libc-header-start.h> resolved from the host system
         (/usr/include), not pxx's own headers
```

and a failure that depends on the host's glibc headers is exactly the kind that
goes green on a different box for no good reason. So the close rests on the fix
commit's mechanism matching the observed one, not on the green.

### Confirmed the mechanism actually changed

At HEAD the build of `test/test_nilpy_c_pointer.npy` emits **zero**
`resolved from the host system` warnings and exits 0, and the program runs and
prints `1`. Before the fix, `import stdlib` walked into `/usr/include` and died
in the preprocessor at `cpreproc.inc:1364`, `C #if: expected ':' in conditional
expression` — parsing a host header pxx was never meant to read.

### Not the same bug as its closed sibling

[[regression-test-core-test-nilpy-c-pointer]] (2026-08-13) failed with
`import: no unit named stdlib and no shim mimic_stdlib` and was a duplicate of
the C-header-import block. Same test, different mechanism, different month — a
`-2` slug is a second finding, not a reopening, and reading the first one is
what establishes that rather than assuming it.
