---
summary: "crtl stdint.h lacks the C99 constant macros (UINT64_C/INT64_C/...) — QuickJS libbf fails with 'call to undeclared function: UINT64_C'"
type: bug
prio: 50
---

# crtl stdint.h: missing INTn_C / UINTn_C / INTMAX_C constant macros

- **Type:** bug (crtl header gap). **Track B** (lib/crtl) — filed from Track A's
  night session per lane rules; C-frontend token-paste in this position may
  need a Track C look if the obvious define fails.
- **Status:** done
- **Opened:** 2026-07-14 night, the wall AFTER alloca in the QuickJS bring-up
  ([[feature-c-corpus-quickjs]]).

## Symptom

```
pascal26:18884: error: call to undeclared function: UINT64_C ()
  near: radixl  UINT64_C
```

QuickJS's libbf uses `UINT64_C(0x...)` for its radix tables. C99 requires
stdint.h to provide `INT8_C..INTMAX_C` / `UINT8_C..UINTMAX_C`.

## Fix shape

In `lib/crtl/include/stdint.h`:

```c
#define INT8_C(c)    c
#define INT16_C(c)   c
#define INT32_C(c)   c
#define INT64_C(c)   c ## LL
#define UINT8_C(c)   c
#define UINT16_C(c)  c
#define UINT32_C(c)  c ## U
#define UINT64_C(c)  c ## ULL
#define INTMAX_C(c)  c ## LL
#define UINTMAX_C(c) c ## ULL
```

Needs cpreproc `##` token paste on a macro ARG followed by a suffix — the
paste-rescan arc (b184-188, tcc bring-up) landed that machinery; verify it
handles `c ## ULL` where c is a hex literal.

## Acceptance

- `UINT64_C(0x123)` in a pxx-compiled C file equals `0x123ULL` (gcc parity).
- QuickJS unity build compiles past line ~18884 (next wall surfaces).

## Log
- 2026-07-15 — resolved, commit 25a0499c.
