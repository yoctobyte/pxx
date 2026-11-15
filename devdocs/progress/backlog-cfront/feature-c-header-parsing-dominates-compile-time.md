---
slug: feature-c-header-parsing-dominates-compile-time
track: C
prio: 40
type: feature
status: backlog
created: 2026-11-15
found-by: claude-opus (toybox A2 measurement)
tags: [cfront, performance]
blocked-by: []
summary: "With --shared-runtime a toybox unit compiles in ~1.8 s CPU, and the headers alone take 1.54 s (toys.h: ~340 KB / 14k lines preprocessed). An empty C file takes 0.39 s in either mode, and that includes the Pascal runtime. So A2 (keep the Pascal runtime out of each shared-runtime object) would save at most ~0.3 s per unit, and the object already keeps only the ~1.4 KB it reaches. It was not built. The lever is the C preprocessor/parser speed over header text. Default mode (crtl impls compiled in): 4.3 s for the same headers. gcc: ~0.05 s."
---

# Header parsing dominates C compile time

Not profiled yet (perf is not permitted on plexus; needs another way to get a
profile).
