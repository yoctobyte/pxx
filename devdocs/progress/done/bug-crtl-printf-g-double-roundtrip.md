---
prio: 60
---

# crtl: %g double formatting (or %lg parse) loses exactness — cJSON floats fail

- **Type:** bug (library, lib/crtl printf/scanf float path). Track B (library).
- **Found:** 2026-07-07 by Track T, first watcher run with corpus trees fetched
  (test-cjson#00 was previously skipped everywhere — this is a newly-covered
  gap, NOT a dev regression; the tstate "bad" SHA for it is meaningless).

## Failing job
`tools/testmgr.py --tier full --job 'test-cjson#00'` (needs
`tools/install_lib_candidates.sh cjson`). Two fixtures fail:

```
-{"ratio":0.125,"delta":-0.0625,...}
+{"ratio":0.125,"delta":-0.062500000000000008,...}
-{...,"big":100.125,"tiny":0.001953125,"price":19.5}
+{...,"big":100.12499999999999,"tiny":0.0019531250000000003,...}
```

## Analysis (verified 2026-07-07, pascal26 @ 87ce0f60)
Two independent defects; the first is the primary cause:

1. **scanf float conversions store raw bits.** EVERY float conversion
   (`%lf`, `%le`, `%lg`, float `%g`) returns garbage whose bit pattern is
   the parsed INTEGER part: `sscanf("100.125", "%lf", &d)` gives
   `4.94065645841247e-322` — that is a double whose raw bits are 100. The
   integer part is parsed, then stored into the double as raw bits with no
   int→float conversion (fraction discarded too). Returns n=1, so callers
   trust the garbage. This makes cJSON's `%1.15g`-then-reparse round-trip
   check always fail, forcing its `%1.17g` fallback.
2. **`%1.17g` digit generation is not correctly rounded:**
   `printf("%1.17g", 100.125)` prints `100.12499999999999` (glibc:
   `100.125`). `%1.15g` of the same value is fine. This is what then shows
   up in the JSON output.

Also noticed (minor, not part of this gate): `%a` is unsupported — prints
the literal `%a`.

## Repro without cJSON
```c
double d; int n = sscanf("100.125", "%lf", &d);   // n=1, d = 4.94e-322 (bits==100)
printf("%1.17g\n", 100.125);                       // 100.12499999999999
```

## Gate
`make test-cjson` green (all 5 fixtures) with the corpus tree present.

## Log
- 2026-07-08 — resolved, commit 3e6f57f5.
