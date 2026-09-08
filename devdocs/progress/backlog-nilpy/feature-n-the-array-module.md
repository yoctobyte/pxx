---
slug: feature-n-the-array-module
track: N
prio: 50
type: feature
status: backlog
owner: ""
created: 2026-09-08
found-by: frankuser
tags: [nilpy, stdlib, mimic, lekkerzeilen]
blocked-by: []
summary: "`import array` fails with `no unit named array and no shim mimic_array`. Measured 2026-09-08 against compiler/pascal26 a7b03135f504; it blocks lekkerzeilen's `world` and `audio` modules. The mechanism already exists -- lib/rtl/ carries ~20 mimic_* shims in both .py and .pas -- so this is writing one, not designing one. array is a typed dense buffer over the same typecodes struct already uses ('f', '<f', '=f' all appear in lekkerzeilen/world.py), which is what a program avoiding numpy reaches for instead."
---

# The gap

```
$ ./compiler/pascal26 lekkerzeilen/world.py out
pascal26:9: error: import: no unit named array and no shim mimic_array
```

Same for `audio.py:25`.

# What it needs

`array.array(typecode)` with append, indexing, `len`, iteration, `frombytes`/
`tobytes`, and the buffer handoff that makes it useful to the GL layer. The
typecodes actually used by the target are float ('f') first.

`lib/rtl/mimic_*.{py,pas}` is the established shape and the error message names
the expected filename, so the resolution path is already wired — this is a
module, not a mechanism.
