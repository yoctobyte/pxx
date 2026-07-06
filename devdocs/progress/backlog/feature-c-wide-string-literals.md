---
prio: 28  # auto
---

# C wide string literals L"..." / wchar_t

- **Type:** feature (clexer + crtl <wchar.h>). Track C. Low priority.
- **Found:** 2026-07-06 c-testsuite run.

## Failing test
- 00220: `wchar_t s[] = L"hello$$你好¢¢世界€€world";` — UTF-8 source decoded to
  wchar_t (4-byte on Linux) array; test prints code points %04X. We output
  empty line (literal decays to nothing). Needs: L-prefix lexing, UTF-8 →
  UCS-4 decode, wchar_t array init, crtl wchar.h with wchar_t typedef.

## Gate
Drop 00220.c from test/c-conformance/pxx.skip; runner green.
