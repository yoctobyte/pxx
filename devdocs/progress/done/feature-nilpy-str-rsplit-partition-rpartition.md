---
track: N
prio: 35
type: feature
blocked-by: []
---

# str.rsplit()/partition()/rpartition() missing

Found by proactive CPython-diff sweeping. `split()` existed with its
0/1/2-argument forms, but its sibling `rsplit()` did not, nor did
`partition()`/`rpartition()` — all real, commonly-used str methods
(`"unsupported str method"` error listing every OTHER str method NilPy has).

## Fix

- `compiler/builtin/pylib.pas`: `pystr_rsplit_sep_max` (right-anchored
  maxsplit — only the 2-argument form of rsplit needs its own algorithm;
  `rsplit()`/`rsplit(sep)` give the identical result to `split()`/`split(sep)`
  since only a maxsplit limit depends on which end it's anchored to).
  `pystr_partition`/`pystr_rpartition` — a 3-tuple `(before, sep, after)` at
  the first/last occurrence, or `(s,'','')` / `('','',s)` when the separator
  is absent, matching CPython exactly.
- `compiler/pyparser.inc`: wired `rsplit` into `PyStrMethodInfo` reusing
  `split`'s dispatch shape (a new `wantArgs = -8` case in `PyParseStrMethod`
  that reuses `pystr_split_ws`/`pystr_split_sep` for 0/1 args and only calls
  the new right-anchored function for the 2-arg form); `partition`/
  `rpartition` as ordinary 1-argument str methods. Updated the "unsupported
  str method" error's method list to include all three.

Verified against CPython (empty-string edge case, separator absent, `maxsplit`
values). Regression test `test/test_nilpy_str_rsplit_partition.npy` (gated in
`test-nilpy`). Self-host confirmed byte-identical via `make pxx-debug`.

## Log
- 2026-07-31 — resolved, commit HEAD.
