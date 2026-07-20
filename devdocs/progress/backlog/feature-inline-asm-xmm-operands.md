---
prio: 45  # auto — blocks every float asm kernel; the encoder work is already done, only the operand parser is missing
track: A
---

# Pascal inline asm cannot name XMM registers (no float asm kernels)

- **Type:** feature — **Track A** (`compiler/asmfront.inc`; the asm frontend).
- **Status:** backlog — filed 2026-07-20.
- **Found by:** Track E, building
  [[feature-demo-mandelbrot-asm-autozoom]] — the ticket asks for an SSE2
  double-precision escape kernel in inline asm; it cannot be written today.

## Symptom

```pascal
function EscapeAsm(cre, cim: Double; maxit: Integer): Integer;
begin
  asm
    xorpd xmm0, xmm0
    movsd xmm6, cre
  end;
end;
```
```
pascal26:9: error: asm: unknown instruction: xorpd ()
  near:  asm xorpd xmm0  xmm0 >>> xorpd xmm1
```
The instruction is reported as unknown *with empty operands* — the mnemonic
table is fine, the operands failed to parse, so the instruction reaches the
encoder with zero operands and falls off the end of the form dispatch.

## Cause

`AsmRegLookup` in `compiler/asmfront.inc` recognises GP registers only:
`rax..r15` (size 8) and `eax..r15d` (size 4). There is no `xmm0..xmm15` arm.
Every float mnemonic therefore fails at operand-parse time.

Note this is *only* the frontend gap — the rest of the chain already handles SSE:

- `compiler/asmenc.inc` (~line 119) already resolves `xmm0..xmm15`, flagging
  them with **size 16**, which is exactly the convention the encoders expect.
- `compiler/asmtext.inc` (~line 596ff) already encodes `movsd movss addsd subsd
  mulsd divsd addss subss mulss divss comisd ucomisd cvtsd2ss cvtss2sd xorps
  xorpd pxor`, plus `movq` xmm<->gp/mem and `cvtsi2sd` / `cvttsd2si`, in
  reg-reg, reg-mem and mem-reg forms.
- `compiler/asmtext_386.inc` has the 32-bit counterpart.
- `compiler/asmdisasm_x64.inc` already disassembles them.

So this is plausibly a small change: give `AsmRegLookup` an `xmm0..xmm15` arm
returning `size = 16` (mirror asmenc.inc's loop, which builds the name by
`AppendChar` rather than string `+` — deliberate, for self-compile), and make
sure the size-16 kind flows through the frontend's operand-kind classification
into the existing `k0/k1` dispatch rather than being treated as a GP width.

## Scope to check while doing it

- Named Pascal locals/params as the memory operand (`movsd xmm6, cre`) — the GP
  path already resolves a local to `[rbp+disp]`; the SSE reg-mem forms take the
  same `mb/md` pair, so it should fall out, but verify.
- aarch64 / arm32 / i386 frontends have the same question for their float
  registers (`d0..d31`, `s0..s31`, x87) — file or fix per target as appropriate;
  x86-64 is the one this ticket blocks.
- The `xmm8–15` caller-save discipline in
  `devdocs/dev/optimization-architecture.md` ("hand-written asm that writes
  xmm8–15 must save them") applies to whatever a user then writes; a test that
  exercises it would be worthwhile.

## Acceptance

- A Pascal function with an `asm` block that uses `xmm` registers compiles and
  runs — e.g. an SSE2 double escape-time loop whose results are identical to the
  portable Pascal kernel over a test grid.
- A `test/test_asm_sse.pas` covering reg-reg, reg-mem (named local), mem-reg
  store, and `ucomisd` + `ja` as a loop condition.
- Track A gate: `make test` + self-host byte-identical.

## Links
[[feature-demo-mandelbrot-asm-autozoom]] (the blocked consumer) ·
`compiler/asmfront.inc` (`AsmRegLookup`) · `compiler/asmenc.inc` (already has the
names) · `compiler/asmtext.inc` (already has the encodings).

## Log
- 2026-07-20 — Filed from Track E. The demo ships with an Int64 Q4.28
  **integer** asm kernel instead (GP registers, works today) and falls back to
  the portable Double kernel past fixed-point depth; the SSE kernel the ticket
  originally wanted waits on this.
