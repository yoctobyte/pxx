# Handover — cross-target bootstrap arc (2026-06-13)

Pick-up doc for the cross self-host bootstrap work. Read this, then the two
working tickets, then continue.

## Goal of the arc

Get `compiler/compiler.pas` to **cross-compile to a non-x86-64 target and
self-host byte-identically under QEMU** (`feature-cross-bootstrap-selfhost`).
Active focus target: **arm32** (smallest deltas, all-stack-ish, good QEMU).
The work proceeds by repeatedly cross-compiling `compiler.pas` to arm32, hitting
the next "not yet supported" wall, fixing it as a small oracle-tested slice, and
advancing. x86-64 is the oracle for every test.

## Where things stand

`compiler.pas` → arm32 currently stops at **parser line 32676**:
`target arm32: builtin/special call not yet supported`, **specialId `j=50` =
`tkSysOpen`**. (Up from line 88 at the start of this arc; this session advanced
13288 → 16307 → 32676.)

**Next slice (do this first): the raw syscall builtins on arm32.**
`tkSysOpen`(50) `tkSysRead`(51) `tkSyswrite`(52) `tkSysClose`(53)
`tkSysFchmod`(54) — `compiler.pas` uses these to *write the output binary*
(open/write/close + chmod +x). None are handled on arm32. The x86-64 handlers
are in `ir_codegen.inc` ~3112–3210 (`specialId = Ord(tkSysOpen)` … emit a
`syscall` with args marshalled from the `IR_ARG` chain). Port each as an arm32
`svc #0`: syscall nr in **r7**, args in **r0..r5**; the arm32 EABI syscall
numbers differ from x86-64 (open=5, read=3, write=4, close=6, fchmod=94 — but
verify against an arm32 syscall table / how `__pxxrawsyscall` is wired in
`builtinheap.pas` `PXXSysOpenRO`/`PXXSysLseek`/`PXXSysRead`/`PXXSysClose`, which
already encode the arm32 numbers: open=5, lseek=19, read=3, write=4, close=6).
Evaluate each `IR_ARG` into the right register (mirror the existing arm32
`IR_SYSCALL` handler if present, or the `__pxxrawsyscall` lowering). Add a focused
oracle test (write a temp file, read it back) and wire into `make test-arm32`.

Reproduce the current wall:
```
./compiler/pascal26 --target=arm32 compiler/compiler.pas /tmp/pc_arm 2>&1 | tail -3
```

### Two tickets in `working/`
- `docs/progress/working/feature-cross-param-abi.md` — i386 by-ref/Variant
  params + arm32 string-result ABI done. Remaining: record-by-value (>register),
  float params/results on i386/ARM32, AArch64 `>8`-arg stack spill.
- `docs/progress/working/feature-cross-codegen-gaps.md` — items 7 (arm32
  SetLength-on-string), 8 (arm32 managed-string Length/indexing), 9 (arm32 `in`
  operator) done. Item 1 was split out (below). Items 2–6 still open (COW on
  cross, class instantiation, AArch64 lit+lit concat, by-ref var-array params,
  float params/full builtin on i386/ARM32).
- `docs/progress/working/feature-cross-managed-aggregate-locals.md` — **arm32
  complete (items 1+2+3)**. Remaining: **i386 + AArch64 ports** of the same three
  pieces, plus array-of-managed local release.

Read each ticket's `## Log` — every slice this session is recorded there with
file/line pointers.

## Workflow / invariants (do not skip)

- **Self-hosted build:** `./compiler/pascal26 compiler/compiler.pas /tmp/pcN`
  produces the next compiler. After a compiler change: rebuild, then
  `cp /tmp/pcN compiler/pascal26` to install the new seed.
- **Fixedpoint gate (must hold after every compiler change):**
  ```
  /tmp/pcN compiler/compiler.pas /tmp/pcN2 && cmp /tmp/pcN /tmp/pcN2   # byte-identical
  ```
- **Regression suites:** `make test-arm32`, `make test-i386`,
  `make test-aarch64`, `make test-core` (core includes x86-64 self-host +
  threadsafe fixedpoints). Run the relevant cross suite + core before every
  commit.
- **Oracle test pattern:** every slice adds a `test/test_cross_*.pas`, compiled
  for the target AND x86-64, outputs compared via `tools/run_target.sh <arch>`.
  Wire it into the target's Makefile rule (`test-arm32:` etc., before the final
  `@echo`).
- **Commit discipline (user preference):** commit every logical unit; do NOT
  batch. Conventional Commits. End body with the Co-Authored-By trailer. **Never
  push** without explicit confirmation.
- **Progress board:** after any ticket move/edit run
  `tools/progress.sh board-md` then `tools/progress.sh check` (it fails CI if
  BOARD.md is stale). `git mv` between `backlog/ working/ done/` is the only
  status change. **Landmine:** never write `Blocked-by: —` — the literal `—`
  parses as a dangling slug; omit the line when nothing blocks.

## Hard-won landmines (this arc)

1. **ARM32 code must stay 4-byte aligned.** Any `EmitB` (1-byte) or odd-size
   emission into the arm32 code stream misaligns every following instruction →
   `illegal instruction` / garbage. The x86-64 backend is `EmitB`-heavy; an
   **unguarded x86-64 emit path that runs for a cross target is the classic
   cause.** This session's biggest bug: the prologue managed-local zero-init's
   `else if zeroBytes > 0` (x86 `rep stosb`, 19 bytes) had no `TargetArch` guard;
   it only stayed hidden because an `Error` aborted earlier. **When a cross slice
   crashes weirdly, first check `code=` size delta for a non-multiple-of-4, and
   grep the shared path for unguarded `EmitB`.**
   Quick alignment probe (temporary): after a proc emits, `if (TargetArch =
   TARGET_ARM32) and ((CodeLen mod 4) <> 0) then writeln('misalign ', Procs[pi].Name)`.
2. **Diagnosing a cross runtime crash:** `qemu-arm -d in_asm /tmp/bin 2>&1 | tail`
   shows the last translated block + PC. `QEMU_STRACE=1 tools/run_target.sh arm32
   /tmp/bin` shows syscalls + the signal/si_addr. The custom ELF has **no section
   headers**, so `objdump -d` fails — use `objdump -D -b binary -m arm -EL
   --adjust-vma=0x08048000 --start-address=… --stop-address=…` (load base is
   0x08048000; file offset = vaddr − 0x08048000). Beware: literal-pool data words
   disassemble as bogus "undefined" instructions.
3. **Managed string model:** default build = **frozen** (`string` → `tyString`,
   legacy inline `[len:8][data]` struct). `-dPXX_MANAGED_STRING` → `tyAnsiString`
   (heap handle: `[refcount:8][length:8][data][nul]`, data ptr = base+16,
   length at `[handle-8]`, refcount at `[handle-16]`, alloc size = len+17).
   `compiler.pas` uses BOTH (some explicit `AnsiString`). Test string slices in
   the matching mode.
4. **arm32 `IR_LEA` of a scalar `tyAnsiString`** returns the **slot address** in
   write mode but must **load the handle** (slot content) in read mode
   (`not InLValueWrite`) — mirrors the x86-64 read/write gate. Without it
   `Length`/indexing read garbage. (Fixed this session.)
5. **Portable runtime helpers** live in `compiler/builtin/builtinheap.pas` and
   are the preferred way to add cross behavior (one Pascal impl, all targets) vs.
   hand-encoding per target. Added this session: `PXXStrSetLen(strSlot, newLen)`.
   Existing useful ones: `PXXMemZero(dst,n)`, `PXXMemMove`, `PXXDynSetLen`,
   `PXXRecordRelease(addr,desc)`, `PXXVarClear(addr)`, `PXXStrDecRef`. Forward-
   declare new ones in the decl block near the top of builtinheap.pas, and (if
   called from `symtab.inc`/`parser.inc`) forward-declare the arm32 emit helpers
   there too (see `EmitLoadVarAddrArm32`, `EmitLoadDataRefArm32` forward decls in
   `symtab.inc`).
6. **`TSymbol` field landmine** (from memory): do NOT add fields to `TSymbol`
   (MAX_UFIELD overflow breaks self-host). Use parallel arrays.

## Key file map for cross codegen

- `compiler/parser.inc` — `EmitProcPrologue` param-copy (per-`TargetArch`
  branches ~line 5720+), managed-local **zero-init** loop (~5973+), proc
  epilogue call (~6109).
- `compiler/symtab.inc` — `EmitProcEpilog` (per-target branches ~3190+; arm32
  managed-local **release** loop ~3232), `EmitManagedLocalCleanup` (x86-64
  only), `ParamSize`/`AllocParam` (~1322/1332), `SymNeedsZeroing` (~1005),
  `TypeIsAggregate`/`TypeIsOrdinal` (~1074-1095).
- `compiler/ir_codegen_arm32.inc` — arm32 IR→machine. `IREmitNodeArm32` big
  `case` (~399); special-call dispatch in the `IR_CALL`/`pi<0` block (~879+,
  errors at ~1007 = current wall family); `EmitArm32CopyBytes` (~372);
  `EmitLoadVarAddrArm32` (~121); `EmitVarHelperCallArm32` (~237).
- `compiler/ir_codegen386.inc`, `ir_codegen_aarch64.inc` — i386 / AArch64
  equivalents (same structure; ports of arm32 slices go here).
- `compiler/ir_codegen.inc` — x86-64 backend = the reference semantics to mirror
  (e.g. SetLength/string-store/IR_LEA gates).

## Recommended next steps (in order)

1. **Current arm32 wall (line 32676) = `tkSysOpen` and the raw-syscall builtin
   family** — see "Where things stand" above for the full porting recipe. After
   those five, re-run the cross compile and repeat the instrument→identify→port
   loop for the next specialId. The instrument trick (proven this session):
   in `ir_codegen_arm32.inc` at the `builtin/special call not yet supported`
   Error site, `writeln('DBG j=', j)` before it, rebuild seed, re-run
   `--target=arm32 compiler/compiler.pas`. Map `j`: `Ord(tk…)` (count the
   `TTokenKind` enum in `defs.inc` from `tkEOF=0`), or the `100/101/102/200/
   203–206/999=SPECIAL_IN` specials. Find the x86-64 handler in `ir_codegen.inc`
   (`specialId = …`) and port. Prefer a portable `builtinheap.pas` helper when
   one exists (how SetLength-string and LoadFile were done this session).
2. **Port managed-aggregate-locals to i386 + AArch64** (close that ticket):
   add their `zeroBytes > PTR` zero-init branch in `parser.inc` (mirror the arm32
   loop / or call `PXXMemZero`), and the variant/record **release** in their
   `EmitProcEpilog` branches in `symtab.inc` (mirror the arm32 block just added).
   Unit-test via `test_cross_managed_aggregate_locals.pas` against each target
   (they fail earlier `compiler.pas` walls, so unit tests are the gate, not the
   full self-compile). NB the x86-`rep stosb` guard fix already protects them.
3. **Keep grinding arm32 walls** toward a full `compiler.pas` cross-compile, then
   wire the `make cross-bootstrap-arm32` gate described in
   `feature-cross-bootstrap-selfhost.md`.

## State checkpoints

- Branch: `master`. Tree clean at handover. All commits this session are local
  (not pushed — awaiting user confirmation per preference).
- `compiler/pascal26` is the current self-hosted seed (rebuilt + fixedpoint-clean
  after the last commit).
- ESP32 self-host is an explicit **non-goal** (RAM); noted on
  `feature-cross-bootstrap-selfhost.md`. The bootstrap gate is Linux cross only.
