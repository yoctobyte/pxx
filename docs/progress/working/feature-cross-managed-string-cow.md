# Copy-on-write for managed strings on cross targets (i386 / ARM32 / AArch64)

- **Type:** feature
- **Status:** working
- **Owner:** codex
- **Unblocks:** feature-cross-selfhost-i386, feature-cross-selfhost-arm32, feature-cross-selfhost-aarch64
- **Opened:** 2026-06-13 (split out of i386 self-host burn-down)

## Problem

The cross backends (i386, ARM32, AArch64) do **not** implement copy-on-write
for managed `AnsiString` writes. Only the x86-64 backend does. So a write
through a *shared* string handle mutates the shared data in place instead of
first making the target unique.

This is already acknowledged in `compiler/ir_codegen386.inc` (IR_INDEX comment:
"Managed strings and dynamic arrays (which need copy-on-write) aren't available
on i386 yet, so no COW path here.") and the ARM32/AArch64 equivalents.

### Why it blocks self-host

`compiler.pas`'s own `LowerCase` (parser.inc ~6199) is the trigger:

```pascal
function LowerCase(const s: ansistring): ansistring;
var i: integer; res: ansistring;
begin
  res := s;                       { shares s's handle, refcount bump }
  for i := 1 to Length(res) do
    if res[i] in ['A'..'Z'] then
      res[i] := Chr(Ord(res[i]) + 32);   { in-place write — needs COW first }
  LowerCase := res;
end;
```

With no COW, `res[i] := ...` mutates the buffer still aliased by `s`. In the
compiler this corrupts a proc's **call name**: `HeapMmap` is folded to
`heapmmap` in a buffer that is also the case-preserved decl name, so
`MatchProcCall`'s exact `Procs[i].Name = name` misses and you get:

```
pascal26:119: error: no overload of heapmmap matches these arguments
```

(`heapmmap` is reached on the empty-program startup path via the heap RTL.)

## Minimal repro

`/tmp/lc.pas`:

```pascal
program lc;
function LowerCase(const s: ansistring): ansistring;
var i: integer; res: ansistring;
begin
  res := s;
  for i := 1 to Length(res) do
    if res[i] in ['A'..'Z'] then res[i] := Chr(Ord(res[i]) + 32);
  LowerCase := res;
end;
var x: ansistring;
begin
  x := 'HeapMmap';
  writeln('orig=', x);
  writeln('lower=', LowerCase(x));
  x[1] := 'Z';
  writeln('afterwrite=', x);
end.
```

Build/run per target (`tools/run_target.sh <arch> <bin>`; i386 runs natively):

```
x86_64 : afterwrite=ZeapMmap      <- correct (x stayed 'HeapMmap')
i386   : afterwrite=Zeapmmap      <- BUG: LowerCase mutated x to 'heapmmap'
arm32  : afterwrite=Zeapmmap      <- BUG: same
aarch64: segfaults inside LowerCase itself (additional/earlier string bug)
```

So: **i386 and ARM32 share exactly this COW gap**; **AArch64 has at least this
plus an earlier crash** — investigate AArch64 separately once COW lands, it may
be a second bug on top.

## Scope

- Implement AnsiStrUnique-style copy-on-write before an in-place managed-string
  write on i386, ARM32, AArch64, mirroring the x86-64 path.
  - x86-64 reference: `InLValueWrite` flag (defs.inc:776) drives IR_LEA / index
    lvalue handling in `ir_codegen.inc`; the runtime helper is in
    `compiler/builtin/builtinheap.pas` (search `Unique`). Cross backends do not
    track `InLValueWrite` today — wiring it (or an equivalent lvalue-write
    signal) into the cross IR_INDEX / IR_STORE paths is part of the work.
- Cover the two write forms: string index write `s[i] := c`, and any other
  in-place mutation that assumes single ownership.
- Audit `res := s` share/refcount semantics on the cross targets while here
  (the alias is what makes the in-place write dangerous).

## Acceptance

- `/tmp/lc.pas` prints `afterwrite=ZeapMmap` (x unchanged by LowerCase) on
  i386, ARM32, AArch64 — matching x86-64.
- `make test` and `make test-i386 test-arm32 test-aarch64` stay green; add a
  focused COW oracle test per target.
- Re-probe the full self-host chain afterwards (it is the next wall for both
  `feature-cross-selfhost-i386` and `feature-cross-selfhost-arm32`).

## Context / where to look

- `compiler/ir_codegen386.inc` — IR_INDEX (no-COW comment), IR_LEA, IR_STORE_*.
- `compiler/ir_codegen_arm32.inc`, `compiler/ir_codegen_aarch64.inc` — peers.
- `compiler/ir_codegen.inc` — x86-64 IR_LEA / IR_DYNUNIQUE / InLValueWrite path
  to mirror; `IR_SLOTADDR` is the unconditional slot-address node.
- `compiler/builtin/builtinheap.pas` — runtime string helpers (the place an
  `AnsiStrUnique(handle)` would live; refcount at `[p-16]`, length `[p-8]`).
- Debugging: i386 binaries run natively (ia32) so plain `gdb` works (no QEMU);
  binaries are stripped (`--emit-obj` is xtensa/riscv only). Use
  `gdb -ex starti -ex 'disassemble A,B'`, map crash addr to a proc by structure,
  reproduce in a tiny `.pas`, diff `--target=i386` vs `--target=x86_64` output.

## Log

- 2026-06-13 — opened. i386 + ARM32 confirmed to share the no-COW bug via the
  repro above; AArch64 has an additional earlier string crash. This is the
  current wall for the i386 (and very likely ARM32) self-host tickets after the
  2026-06-13 i386 codegen burn-down (7 fixes; see feature-cross-selfhost-i386).
- 2026-06-13 — claimed by Codex; starting with the i386 `AnsiString` index-write
  COW slice because it is the current i386 self-host wall.
- 2026-06-13 — i386 slice implemented. Added `PXXStrUnique`, wired i386
  `IR_LEA`/`IR_INDEX`/`IR_STORE_MEM` lvalue-write handling so `s[i] := c`
  clone-if-shared publishes a unique handle, and added
  `test/test_cross_string_cow.pas` to `make test-i386`. While re-probing
  self-host, also hardened small 64-bit emission/patching paths that i386
  self-host lowered as duplicated low dwords (`EmitI64`, ELF `writeU64`,
  code/data `Patch*U64`, string-table length headers) and removed executable
  float literals from the cross-runtime float writer. Result:
  `make test-i386` passes and the i386-generated compiler now emits byte-
  identical x86-64 `test/hello.pas` output under `-dPXX_MANAGED_STRING`.
  ARM32 and AArch64 COW remain pending.
- 2026-06-14 — i386 COW proven end-to-end: feature-cross-selfhost-i386 is DONE
  (full `compiler.pas -> i386` self-fixedpoint byte-identical), so the i386 COW
  path (index-write `PXXStrUnique`) is exercised through the whole compiler.
  ARM32 and AArch64 COW remain pending (this ticket stays open for them).
- 2026-06-14 — AArch64 index-write COW slice implemented. Mirrored the i386
  write-mode `IR_INDEX` path: `IR_STORE_MEM` now emits destination addresses
  with `InLValueWrite`, and managed-string byte writes call `PXXStrUnique` before
  indexing. Added `test/test_cross_string_cow.pas` to `make test-aarch64`.
  `make test-aarch64` and `make test` pass. Full AArch64 compiler self-host now
  gets past the LowerCase/COW and stale hidden-temp walls but still crashes
  later while parsing `builtinheap.pas`; track that under
  `feature-cross-selfhost-aarch64`.
