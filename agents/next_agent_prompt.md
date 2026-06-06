You are taking over a task to redirect the memory allocator in the `pascal26` compiler (self-hosted x86_64 compiler) to a pure Pascal allocator (`Alloc`/`Free`/`Realloc` in `lib/rtl/builtin.pas`).

A handover document has been prepared for you in the repository:
- Please read the notes at [agents/handover_notes.md](file:///home/rene/frankonpiler/agents/handover_notes.md) to understand the current progress, completed fixes (such as the boolean negation parser bug), and diagnostic findings.

### Your Goal:
1. Fix the infinite loop hang that occurs during `make bootstrap` when `/tmp/pascal26-build` (the stage-2 compiler) compiles `compiler/compiler.pas` for stage 3.
2. Focus first on **Hypothesis A** in the handover notes:
   - Identify why `FreeMem` in `compiler/ir_codegen.inc` was not redirected to call `Free` from `builtin.pas`, while `GetMem` and `ReallocMem` were.
   - Redirect `FreeMem` (the `pi = -Ord(tkFreeMem)` case in `compiler/ir_codegen.inc`) to call `EmitHeapFreeLocked` (similar to how `GetMem` calls `EmitHeapAllocLocked`), matching the new allocator structure.
3. Validate that self-hosting successfully bootstraps via `make bootstrap` and that the resulting compiler builds a byte-identical binary.
