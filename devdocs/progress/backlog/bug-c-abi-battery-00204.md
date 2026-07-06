---
prio: 55  # auto
---

# c-testsuite 00204: calling-convention battery (structs 1..17 bytes by value, HFAs, varargs)

- **Type:** bug (umbrella — run AFTER the other init/float tickets). Track C/A.
- **Found:** 2026-07-06 c-testsuite run.

## Failing test
- 00204 (527 lines): passes/returns structs of every size 1..17, HFA float
  structs, mixed varargs, by value AND through `...`. Output mismatch from the
  first "Arguments:" block (stack-passed args print garbage).
  Known-adjacent: v180 struct-by-value fix covered 8-byte records; this battery
  covers every size class + return-in-registers + varargs-of-struct.

## Approach
Re-run after bug-c-init-designated-and-nested + bug-c-float-single-precision
land (its structs use string/float inits); then diff section by section vs
.expected and file/fix per size class. x86-64 SysV first, then cross targets.

## Gate
Drop 00204.c from test/c-conformance/pxx.skip; runner green.
