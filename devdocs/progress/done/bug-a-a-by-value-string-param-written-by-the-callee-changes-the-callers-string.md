---
prio: 90
track: A
status: done
owner: frankS
summary: "FIXED 2026-09-24. A by-value AnsiString or dynamic-array parameter is now OWNED by the callee: it takes a reference at entry (CompileAST, IREmitOwnedParamRetain) and releases it in the scope-exit sweep (SymReleasedAtScopeExit), which is fpc's model. Before the fix the param was BORROWED, while a store into it already released the old handle as if owned. So a callee writing into a string param changed the CALLER's string: the textbook UpperStr turned the caller's `name` into HELLO WORLD on every target, pin v423 included. A callee that rebound the param leaked one block per call, for strings and dynarrays alike (frankb-12's census). Excluded: const, var/out, open arrays, NilPy/C, wasm32 and stackless generators. Guard: test_a_by_value_string_param_the_callee_writes_leaves_the_caller_alone (output == fpc, plus assert_no_leak) in test-core and test-i386."
---

# A by-value string param the callee writes changes the caller's string

Found 2026-09-24 by frankS while chasing frankb-12's dynarray leak census
(a by-value dynarray param rebound by `SetLength` leaked 0.98 blocks per call).

## Measured

- `function UpperStr(s: string): string; ... s[i] := UpCase(s[i]); Result := s;`
  left the caller's `name` upper-cased. fpc -Mobjfpc prints `hello world | HELLO
  WORLD`; pxx HEAD and pin v423 printed `HELLO WORLD | HELLO WORLD`. Same on
  i386, arm32, aarch64 and riscv32.
- Rebinding a param (`s := s + 'x'`, `SetLength(a, 9)`): allocs 9755 / frees 2
  over 10000 calls. After the fix, frees 9752 / live 3.
- Dynarray ELEMENT writes through a value param still reach the caller, as in
  fpc: dynarrays share, strings copy on write.

## Fix

The store side already treated the param as owned. The entry retain and the
exit release were missing. Both halves now key on SymOwnedValueParam, and all
seven copies of the sweep loop ask SymReleasedAtScopeExit.

Cost: +2.0% on a self-compile of compiler.pas (22395 -> 22832 ms, min of 5,
interleaved A/B, same tree with and without the change). fpc pays the same.
Possible follow-up: skip the retain for a param that the body never writes.

Verified: fixture output byte-identical to fpc on x86-64, i386, arm32, aarch64,
riscv32, esp32c3 and esp32s3. Census flat on x86-64, i386 and aarch64. The pin
fails both halves (corrupted output; live=23395).
