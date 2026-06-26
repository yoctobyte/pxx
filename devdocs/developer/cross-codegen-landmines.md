# Cross-codegen landmines

Hard-won gotchas for the non-x86-64 backends (i386 / ARM32 / AArch64 / RISC-V /
Xtensa). Durable, git-tracked home — append here when a cross-target bug costs
real diagnosis time, so the next agent (or the next you) doesn't re-pay it.
Progress/state lives in `devdocs/progress/`; this file is *timeless gotchas only*.

---

## ARM32: code must stay 4-byte aligned

ARM instructions are fixed 32-bit and must be 4-byte aligned. **Any odd-size
emission into the arm32 code stream corrupts every following instruction** →
`illegal instruction`, null-deref, or a segfault far from the real site.

The classic cause is **an unguarded x86-64 emit path running for a cross
target.** The x86-64 backend is `EmitB` (1-byte) heavy; a shared site in
`parser.inc` / `symtab.inc` / `ir.inc` that emits x86 bytes without a
`TargetArch` guard will silently mis-emit on arm32.

**Worst instance (2026-06-13):** the prologue managed-local zero-init in
`parser.inc` ended with `else if zeroBytes > 0` = x86-64 `lea/xor/mov/rep stosb`
(**19 bytes**), no `TargetArch` guard. It stayed hidden only because an `Error`
for `zeroBytes > TARGET_PTR_SIZE` on non-x86 aborted before reaching it. Adding a
real arm32 branch let the flow fall through to the x86 block → 19 stray bytes →
total misalignment.

**Rule:** guard every x86 `EmitB`-sequence with `TargetArch = TARGET_X86_64`, and
give each cross target its own branch. Cross backends emit only via `EmitI32`
(and the typed encoders); never leak an `EmitB` into them.

### Diagnosis recipe (proven)

1. **Smell test:** compare `code=` size against a working variant. A
   **non-multiple-of-4 delta** (e.g. the 19-byte stosb) is a smoking gun.
2. **Pinpoint the proc** with a temporary check after proc emission in
   `parser.inc`:
   ```pascal
   if (TargetArch = TARGET_ARM32) and ((CodeLen mod 4) <> 0) then
     writeln('misalign after ', Procs[pi].Name);
   ```
3. **Crash PC / last block:** `qemu-arm -d in_asm /tmp/bin 2>&1 | tail`.
4. **Signal + fault address:** `QEMU_STRACE=1 tools/run_target.sh arm32 /tmp/bin`.
5. **Disassemble** — the emitted ELF has **no section headers**, so `objdump -d`
   yields nothing. Use raw-binary mode:
   ```
   arm-linux-gnueabi-objdump -D -b binary -m arm -EL \
     --adjust-vma=0x08048000 --start-address=0x… --stop-address=0x… /tmp/bin
   ```
   Load base is `0x08048000`; file offset = `vaddr - 0x08048000`. Literal-pool
   data words (frame offsets, ELF header) disassemble as bogus `<UNDEFINED>`
   instructions — ignore them. Real misalignment shows as adjacent "instructions"
   that are valid opcodes **shifted by 1–3 bytes** (e.g. `ldr`/`b` pair offset by
   one byte).

---

## Other known cross gotchas (one-liners; expand when bitten)

- **Prefer portable helpers.** Add behavior as a Pascal routine in
  `compiler/builtin/builtinheap.pas` (one impl, all targets) rather than
  hand-encoding per target. Examples: `PXXMemZero`, `PXXMemMove`, `PXXDynSetLen`,
  `PXXStrSetLen`, `PXXStrLoadFile`, `PXXRecordRelease`, `PXXVarClear`,
  `PXXStrDecRef`. Forward-declare new ones in the decl block at the top of
  builtinheap.pas; if called from `symtab.inc`/`parser.inc`, forward-declare the
  arm32 emit helpers there too.
- **ARM32 `IR_LEA` of a scalar `tyAnsiString`** returns the slot **address** in
  write mode but must **load the handle** (slot content) in read mode
  (`not InLValueWrite`) — mirror the x86-64 read/write gate. Otherwise
  `Length`/indexing read garbage.
- **VFP `s0`/`d0` alias (ARM32 floats):** `s0` is the low half of `d0`. Converting
  into `s0` corrupts a live `d0`. Use a scratch (`s8`/`d4`) — see the `Frac`
  intrinsic in `ir_codegen_arm32.inc`.
- **`PWord` is `^Int64`** (8-byte access) even on 32-bit targets — writing a
  pointer-sized slot via `PWord` writes 8 bytes; fine where the runtime expects
  it (matches `PXXDynSetLen`/`PXXStrSetLen`), but watch payload truncation when a
  field is genuinely 4 bytes.
- **No lazy proc emission on cross targets:** all procs are emitted, so
  `FindProc('PXXFoo')` resolves even if only reached at runtime. (x86-64 differs.)
- **`COMPILER_INC` staleness:** after editing the compiler, rebuild the seed
  (`./compiler/pascal26 compiler/compiler.pas /tmp/pcN && cp /tmp/pcN
  compiler/pascal26`) before re-running cross compiles, or you test stale code.
- **Managed string model:** default build = frozen (`string` → `tyString`, inline
  `[len:8][data]`); `-dPXX_MANAGED_STRING` → `tyAnsiString` heap handle
  (`[refcount:8][length:8][data][nul]`, data ptr = base+16). `compiler.pas` uses
  both. Test string slices in the matching mode.
- **ELF has no section headers** (single `RWE` LOAD at `0x08048000`): standard
  section-based tooling won't read it; use binary-mode disassembly (above).

---

## Workflow invariant (so a fix is real)

After any compiler change: rebuild the seed, then the **fixedpoint gate must
hold** — `/tmp/pcN compiler/compiler.pas /tmp/pcN2 && cmp` byte-identical — and
the relevant `make test-<arch>` + `make test-core` stay green. Every cross slice
adds a `test/test_cross_*.pas` oracle (target output vs x86-64 via
`tools/run_target.sh`) wired into the target's Makefile rule.
