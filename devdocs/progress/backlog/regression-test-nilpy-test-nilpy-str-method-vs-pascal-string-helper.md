---
prio: 70
track: P
---

> **Track guessed as N from the FAILING STEP** — line 1 of 2, `./compiler/pascal26 test/test_nilpy_str_method_vs_pascal_string_helper.npy /tmp/test_nilpy_strmhelper26`, which names `test/test_nilpy_str_method_vs_pascal_string_helper.npy`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 8 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_str_method_vs_pascal_string_helper.npy at 4d018b041297 in step 1/2, `./compiler/pascal26 test/test_nilpy_str_method_vs_pascal_string_helper.npy /tmp/test_nilpy_strmhelper26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `0c5ad13167ab`).
  Untriaged.
- **Found:** 2026-09-09T09:28:31Z
- **Test source:** test/test_nilpy_str_method_vs_pascal_string_helper.npy test/test_nilpy_str_method_vs_pascal_string_helper.expected
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/test_nilpy_str_method_vs_pascal_string_helper.npy`.
  ```
  ./compiler/pascal26 test/test_nilpy_str_method_vs_pascal_string_helper.npy /tmp/test_nilpy_strmhelper26
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_str_method_vs_pascal_string_helper.npy'` at 4d018b0412976d19045ab9e9ce1a1bb09059728c

## Range
> **The named sha `4d018b041297` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `4d018b041297`, last good `06e404587e29`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:50: error: Nil Python: unsupported str method .Trim() (have: upper, lower, strip, lstrip, rstrip, startswith, endswith, find, isspace, isdigit, isalpha, isalnum, isupper, islower, isascii, translate, format, join, split, rsplit, partition, rpartition, splitlines, replace, count, rfind, title, capitalize, swapcase, casefold, ljust, rjust, center, zfill, removeprefix, removesuffix)
(tail)
pascal26:50: error: Nil Python: unsupported str method .Trim() (have: upper, lower, strip, lstrip, rstrip, startswith, endswith, find, isspace, isdigit, isalpha, isalnum, isupper, islower, isascii, translate, format, join, split, rsplit, partition, rpartition, splitlines, replace, count, rfind, title, capitalize, swapcase, casefold, ljust, rjust, center, zfill, removeprefix, removesuffix)
  near:   return label . Trim >>> ( )  

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## RE-LANED N -> P, 2026-09-09 (frankB) — the failing step is a NilPy file and the cause is not

`track: N` here is the watcher's FALLBACK, guessed from the failing step's
filename, and CLAUDE.md says in as many words that an auto-filed regression's
track is a fallback rather than a finding. The test is a `.npy`; the defect is
not in the NilPy frontend.

**What the test asserts** is that a Pascal type-helper method reached through
`import 'strhelperprobe.pas'` still resolves for a `str`-typed receiver —
`label.Trim()`, where `Trim` comes from `sysutils` and is deliberately NOT a
Python str method. It is the NEGATIVE arm of that test, present so a str-method
guard that is too broad cannot pass unnoticed. It now fails as
`unsupported str method .Trim()`, i.e. the helper is no longer reachable and the
str-method path claims the call instead.

**That is unit/scope resolution, which is Track P.** The range the watcher
records is `06e404587e29..4d018b041297`, and it contains
`f0aca9c59 fix(P): a generic routine's body resolves names as its declaring
unit` — a change to which unit's scope a body resolves names in, which is
exactly the mechanism a helper imported into a NilPy module depends on.
`1c16d4523` and `2049595a3` are in the same neighbourhood.

**Not a bisect — a reading of the range plus the subsystem.** Recorded so
whoever picks it up starts at the scoping change rather than at the NilPy
frontend.

**Confirmed present independently of anything in flight here:** the PINNED
compiler compiles this test and `compiler/pascal26` at `fedb492f9` does not,
with no local changes applied.

**How it nearly misled me, which is worth one line:** it went red in my second
nilpy tier run and green in my first, with my own frontend change in between, so
it read as mine. It was not — the discriminator is that I PULLED between the two
runs, and the tree moved. CLAUDE.md carries the case where a pull IMPROVES a
number you did not earn; this is its mirror, where a pull worsens one and the
obvious suspect is your own diff. I reverted a good change on that reading
before re-checking. Attribute a tier delta to a RANGE before attributing it to
yourself.
