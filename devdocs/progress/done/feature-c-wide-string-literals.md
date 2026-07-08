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

## Triage 2026-07-07
Foundations present: `wchar_t` = `int` (4-byte) in lib/crtl/include/wchar.h, and
00220 COMPILES (so wchar_t/wchar.h resolve). It just produces empty output —
`L"..."` is not decoded. Needs a coordinated add across clexer + cparser:
1. clexer: detect an `L` immediately followed by `"` as a wide-string prefix
   (before the identifier path), lex the string, and UTF-8-DECODE its bytes to
   Unicode code points. The token model stores byte strings (SVal:AnsiString),
   so the code points must be stored as 4-byte-LE in SVal (SLen = 4*count) with
   a wide flag, or in a side table.
2. cparser: `wchar_t s[] = L"..."` must initialize a 4-byte-element (int32) array
   from the wide token's code points + a wide NUL, sized count+1 (mirror the
   `char buf[]="lit"` per-element init path but 4-byte).
Multi-subsystem; ~60-80 lines across two files with UTF-8 edge cases. Focused
session. (00220's chars are all BMP, so 1-3 byte UTF-8 -> <=U+FFFF.)

## Log
- 2026-07-08 — resolved, commit 658d284c.
