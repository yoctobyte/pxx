---
track: N
prio: 55
type: feature
claimed: claude-n-uforth
---

# NilPy: raise def/method parameter limit past 4

Part of [[feature-nilpy-corpus-uforth]] milestone 1. uforth dataclasses need
ctors with 5-7 params (Word has 6 fields + self); the v1 NilPy prologue
spills only the first 4 integer registers (rdi/rsi/rdx/rcx) and errors —
worse, PyParseMethod's spill `case` has no else and SILENTLY drops the spill
for params 5+ (garbage reads, no diagnostic).

Fix: spill r8/r9 (SysV args 5-6) and copy stack-passed params 7+ from
[rbp+16+8*(i-6)] into their frame slots, both in PyParseDef and
PyParseMethod. Limit becomes MAX_PROC_PARAMS-bounded.

## Gate

test-nilpy green (+ regression test_nilpy_many_params.npy with 8-param def),
self-host byte-identical, testmgr quick.
