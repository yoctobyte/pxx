---
prio: 45
---

# C/i386: `return X` of an enum constant declared inside an anonymous-struct member returns garbage (00120)

- **Type:** bug (i386 backend / enum-in-struct lowering). Track A.
- **Found:** 2026-07-08 by the C cross-conformance matrix
  (feature-c-cross-target-feature-coverage). i386 ONLY — x86-64, aarch64,
  arm32, riscv32 all pass.

## Repro (c-testsuite 00120, whole test)
```c
struct { enum { X } x; } s;
int main() { return X; }   /* i386: exit 96; expected 0 */
```

## Notes
X is enum member 0; returning it yields 96 on i386. Something in the
enum-registered-inside-inline-struct path leaves X bound to a non-constant
(or the i386 return path reads an uninitialized slot). Check how the C
frontend registers enum constants encountered during ParseCStructInto and
what the i386 codegen does with that symbol class.

## Gate
00120 passes under `tools/run_c_conformance.sh --target i386`; drop its line
from `test/c-conformance/pxx.skip.i386`.

## Log
- 2026-07-08 — resolved, commit 8fa1acd3.
