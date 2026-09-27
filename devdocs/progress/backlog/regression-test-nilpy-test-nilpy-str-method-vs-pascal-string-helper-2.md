---
prio: 70
track: N
---

> **Track guessed as N from the FAILING STEP** — line 1 of 2, `./compiler/pascal26 test/test_nilpy_str_method_vs_pascal_string_helper.npy /tmp/test_nilpy_strmhelper26`, which names `test/test_nilpy_str_method_vs_pascal_string_helper.npy`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 9 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_str_method_vs_pascal_string_helper.npy at 9bd5d47ef746 in step 1/2, `./compiler/pascal26 test/test_nilpy_str_method_vs_pascal_string_helper.npy /tmp/test_nilpy_strmhelper26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `f35167cd4e55`).
  Untriaged.
- **Found:** 2026-09-27T20:09:54Z
- **Test source:** test/test_nilpy_str_method_vs_pascal_string_helper.npy test/test_nilpy_str_method_vs_pascal_string_helper.expected
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/test_nilpy_str_method_vs_pascal_string_helper.npy`.
  ```
  ./compiler/pascal26 test/test_nilpy_str_method_vs_pascal_string_helper.npy /tmp/test_nilpy_strmhelper26
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_str_method_vs_pascal_string_helper.npy'` at 9bd5d47ef74674467b5309302c3d40eb93e4e7e5

## Range
> **The named sha `9bd5d47ef746` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `9bd5d47ef746`, last good `2954d103babe`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:62: error: Nil Python: unsupported str method .Trim() (have: upper, lower, strip, lstrip, rstrip, startswith, endswith, find, isspace, isdigit, isalpha, isalnum, isupper, islower, isascii, translate, format, join, split, rsplit, partition, rpartition, splitlines, replace, count, rfind, title, capitalize, swapcase, casefold, ljust, rjust, center, zfill, removeprefix, removesuffix)
(tail)
pascal26:62: error: Nil Python: unsupported str method .Trim() (have: upper, lower, strip, lstrip, rstrip, startswith, endswith, find, isspace, isdigit, isalpha, isalnum, isupper, islower, isascii, translate, format, join, split, rsplit, partition, rpartition, splitlines, replace, count, rfind, title, capitalize, swapcase, casefold, ljust, rjust, center, zfill, removeprefix, removesuffix)
  near:   return label . Trim >>> ( )  

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
