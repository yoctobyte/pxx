---
track: A
prio: 60
type: bug
---

# NilPy/uforth: managed-string hidden temp released with garbage at method return

Hangs off [[feature-nilpy-corpus-uforth]] (runtime-correctness phase). Blocks
uforth actually running: it now compiles, constructs, prints its banner, reaches
the REPL, reads a line, tokenizes it — and SIGSEGVs when `VM.tokenize` returns.

## The crash (decisive gdb evidence)

```
Program received signal SIGSEGV
rip  0x40021a:  decq  -0x10(%rax)      ; managed-string ARC refcount decrement
                jne   0x400244
                sub   $0x10,%rax
rax  0x200000000                       ; a GARBAGE handle (not a heap pointer)
```

`decq -0x10(%rax); jne; sub $0x10,%rax` is the managed AnsiString **release**
sequence (decrement the refcount word at handle-0x10, free if zero). `rax =
0x200000000` is not a valid heap pointer, so `[rax-0x10]` faults. So: a value
typed as a managed string is being RELEASED at scope exit while holding stack
garbage.

## What is known

- It happens in `VM.tokenize` (compiler/... N frontend), at the RETURN: an
  instrumented build prints right up to `return tokens` inside tokenize, then
  crashes before the caller receives the result.
- Forcing `return tokens` at the TOP of tokenize (before the char loop) STILL
  crashes — so the bad managed value exists at function ENTRY, not built by the
  loop. tokenize's only explicit local there is `tokens` (a TPyList, not a
  managed string), so the offender is a HIDDEN temp (a nested-def capture
  spill, a string ternary/`join` temp, or a return-marshal temp).
- **Layout-sensitive.** ~12 standalone reproductions — method + nested def
  (`flush_current`) capturing `self` and a list, `"".join(field)`, `ch =
  line[i]`, hasattr-guarded field init, early return, nested-def method calling
  a list-returning nested-def method — ALL pass. The garbage `0x200000000` comes
  from a prior stack frame; small repros leave a benign (often 0) value there,
  so they don't fault. uforth's larger call chain (VM has 55 fields, many
  managed-string) leaves 0x200000000.

## Diagnosis

Matches the known landmine class [[project_interface_ascast_temp_lifetime_landmine]]:
an IR-lowering hidden temp of managed-string type MISSES prologue zero-init, so a
skipped branch / scope exit releases stack garbage — a layout-sensitive SIGSEGV.
The suspect temp is created somewhere in tokenize's lowering (most likely the
nested-def **capture spill** for `flush_current`, given the early-return still
crashes, or the managed-string ternary/`join` result temp) and is not covered by
`EmitManagedLocalsZeroInit` / `SymIsHiddenArgTemp`.

## KEY FINDING: optimizer-sensitive (-O2 only)

At **-O0 (`-g`) and -O1 the tokenize SIGSEGV does NOT happen** — uforth runs
past tokenize and reaches a *different, deterministic* error deeper in
(`ValueError: byte slice assignment length mismatch (expected 8, got <garbage>)`,
in `set_in_pos`'s `int(pos).to_bytes(8,...)` slice-assign — a second
uninitialized-value bug, tracked separately). This CONFIRMS the diagnosis: the
managed-string hidden temp is genuinely uninitialized, and only -O2's register
allocator / stack-slot reuse leaves garbage (0x200000000) in it; -O0 happens to
leave zero. So the fix is real prologue zero-init of that temp, not an -O2
codegen bug per se. Default builds are -O2, so this still blocks.

## Next steps

- Reduce uforth.py's tokenize with creduce (oracle = "compiled binary SIGSEGVs
  on `1 2 + .`") to a minimal case — hand-reduction failed because the trigger
  is layout-sensitive. NOTE the -O0 successor bug (set_in_pos's `mem[a:b] =
  int(pos).to_bytes(8,...)` length mismatch) ALSO does not reproduce in isolation
  (a captured nested def doing exactly that slice-assign works at both -O0/-O2).
  Both are context-sensitive: creduce/IR-dump on the real file is the path, not
  more hand-repros.
- Or inspect tokenize's lowered IR for a managed-string temp (AllocVar '' with
  tyAnsiString) that is not marked SymIsHiddenArgTemp / not zero-inited, then
  extend the zero-init to cover it. Prime suspect: the capture-spill temp path
  introduced with nested-defs-in-methods, and the string-valued ternary temp.

## Repro (compiles, crashes at runtime)

`~/projects/uforth/uforth.py` compiled to a .npy: `echo "1 2 + ." | ./uf` →
`SIGSEGV`. Reaches the banner "Unicode Forth (UF/O)" first.
