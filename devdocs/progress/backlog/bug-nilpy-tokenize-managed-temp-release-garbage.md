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

## Refined findings (2026-07-21, session 2)

- The bug is the SAME at -O0 and -O2, it just manifests differently: at -O2 the
  release faults (SIGSEGV); at -O0 the corrupted value makes `tokenize` return an
  EMPTY token list, so the interpreter dispatches nothing and `1 2 + .` produces
  no output. So uforth "runs clean" at -O0 but does nothing — the SAME root
  blocks native-word execution.
- The release is emitted by the CODEGEN EPILOGUE for managed-typed locals in
  scope — it is NOT a named IR op, so `--dump-ir` does not show it (confirmed:
  the tokenize IR block, ~1060 ops at dump line 29463, has NO release op).
- tokenize's IR block has many managed-string locals: `cur_word`, `content`,
  `prefix`, `prev_tok`, `bs`, `line`, `tokens` (+ `i/j/k/L/ch/self`). A local
  assigned only inside the char loop is garbage on the early-return path and gets
  released at epilogue — matches "early return still crashes". `EmitManagedLocals
  ZeroInit` SHOULD cover declared tyAnsiString locals, so the offender is either
  (a) a local `PyCollectLocalsAST` typed as something other than tyAnsiString but
  used as one, or (b) a hidden temp created during CompileAST (after the prologue
  zero-init pass) lacking `SymIsHiddenArgTemp`. Audited all `AllocVar('',
  tyAnsiString)` sites in ir.inc — only the case-of-string selector (7417) missed
  the flag and is now FIXED (separate commit, byte-identical); it was not
  tokenize's (tokenize has no case-of-string), so the offender is still open.
- Fixed en route (real, committed): bytes slice-assign from a variant rhs
  (`mem[a:b] = snapshot["blk"]`) — that unblocked `_restore_input_state`, which
  is why -O0 now reaches "runs clean".

## Analysis caveat (don't repeat this dead end)

An IR-dump count of `default_mem` (12) vs unnamed tyAnsiString temps (13) in
tokenize looked like a smoking gun (sym 153, the `str(tokens[-1]).upper() if
tokens else ""` ternary temp, line 111). It is NOT conclusive: `default_mem` is
the INLINE release-before-store for arg temps, whereas ternary/result temps are
nil'd via `SymIsHiddenArgTemp` at the CODEGEN prologue — which the IR dump does
not show. So a temp without `default_mem` may still be nil'd by the flag. The
exact construct (str-ternary with a str-method-chain arm + early return)
reproduces GREEN in isolation. The bug stays layout-sensitive.

## Tooling for the next attempt

Raw gdb conditional breakpoints on the ARC release helper (0x40021a `decq
-0x10(%rax)`) are too slow — the condition is evaluated on every managed release
across uforth's whole startup (thousands). Use instead: (a) rr record/replay with
a hardware watchpoint on the faulting frame slot, or (b) a debug compiler build
that logs each managed temp's frame offset + whether it was nil-inited, then
diff against the epilogue release list for tokenize. The gdb helper addresses:
AddRef 0x400202 (`incq -0x10(%rax)`), Release ~0x400210 (`decq -0x10(%rax)`).

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
