---
prio: 30
---

# cpreproc: "C include file not found" reports the last search dir, not the requested name

- **Type:** bug (diagnostic quality, cpreproc). Track A (shared core) / C-facing.
- **Found:** 2026-07-07 by Track T while triaging tstate regression test-core#261.

## Symptom
When an `#include "..."` (or a source file passed with `-I` search) cannot be
resolved, the error prints the LAST directory probed instead of the include
name and the search list:

```
pascal26:1: error: C include file not found (/usr/lib/llvm-18/lib/clang/18/include/re.c)
```

Actual cause was `library_candidates/tiny-regex-c/` being absent (gitignored
corpus tree), but the message points at the clang system include dir — it cost
a triage round-trip to see the real problem. Repro (with the corpus tree
absent):

```
./compiler/pascal26 -Ilib/crtl/include -Ilibrary_candidates/tiny-regex-c test/crtl_tiny_regex_match.c /tmp/x
```

## Wanted
`error: C include file not found: "re.c" (searched: lib/crtl/include, library_candidates/tiny-regex-c, /usr/lib/llvm-18/lib/clang/18/include)` —
name first, search path list after. See `compiler/cpreproc.inc` around the
hardcoded clang path (`CPAppendRange(CPrepPath, '/usr/lib/llvm-18/...')`,
cpreproc.inc:1845) — the hardcoded llvm-18 path itself is also fragile on
boxes with a different llvm major and may deserve its own probe/fallback.

## Non-goals
Fixing test-core#261 itself — that was a watcher-box corpus gap; testmgr now
self-skips corpus jobs when `library_candidates/<tree>` is absent.
