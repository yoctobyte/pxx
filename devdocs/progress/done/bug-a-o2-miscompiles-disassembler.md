---
prio: 70  # auto — blocks making -O2 the default (a stated goal); a real codegen miscompile
---

# -O2 miscompiles the x86-64 disassembler (`WriteDisassemblyX64`)

- **Type:** bug (codegen — optimization) — **Track A**
  (`compiler/asmdisasm_x64.inc`, `compiler/ir_codegen.inc` regcall/inline).
- **Status:** done
  -O2 ([[feature-optimization-levels]]). The -O2-default flip was REVERTED
  (unpushed) because of this.

## Symptom
A compiler **built at -O2** emits garbage from its `-S` disassembler path; a
compiler built at -O0 (or -O1?) emits correct disassembly. The compiler produced
is otherwise self-host byte-identical and passes c-testsuite 220/220 + quick —
because self-compile never invokes the compiler's OWN `-S` path, so the
miscompile hid until `make test-asm` (which disassembles hello and greps for
`call`/`ret`) ran against an -O2-built compiler.

## Exact repro
```sh
# clean O0 compiler disassembles hello correctly:
compiler/pascal26 -O0 compiler/compiler.pas /tmp/cc_o0
/tmp/cc_o0 -S test/hello.pas /tmp/good
grep -cE '^    call |^    ret$' /tmp/good.s   # -> 235   (correct)
grep -c   '^    db '           /tmp/good.s    # -> 0

# O2-built compiler disassembles hello into garbage:
compiler/pascal26 -O2 compiler/compiler.pas /tmp/cc_o2
/tmp/cc_o2 -S test/hello.pas /tmp/bad
grep -cE '^    call |^    ret$' /tmp/bad.s     # -> 0     (WRONG)
grep -c   '^    db '           /tmp/bad.s      # -> 6     (raw-byte fallback: decode desynced)
```
The `-S` OUTPUT level is irrelevant — the bug is in the disassembler CODE when
compiled at -O2, so both `-O0 -S` and `-O2 -S` from the O2-built compiler are
garbage. `make test-asm` (Makefile ~379-383) is the gate that catches it.

## Where to dig
`WriteDisassemblyX64` (`asmdisasm_x64.inc`) is a large routine: a byte-fetch
cursor over `.text`, many locals, big `case` dispatch on opcode bytes, ModRM/SIB
decode. That profile is a stress case for the two -O2-only passes:
- **regcall r14/r15 param residency** (`ir_codegen.inc`, feature-callconv-
  register-args) — a param kept in a callee-saved reg that is not spilled/
  restored across a call, or aliased with the byte cursor, would desync the
  decode (matches the "db fallback" = cursor read the wrong byte).
- **inline slice 2b** (straight-line stmt bodies) — an inlined helper (e.g. a
  byte-read or ModRM sub-decoder) whose locals collide with the caller's.
Attack: bisect by building the disassembler unit alone at -O2 vs -O0 and diffing;
or instrument the byte cursor position at the first divergent instruction, O0 vs
O2. Suspect a param/local that is address-taken OR live across a call being
promoted to a callee-saved reg without the save/restore (the classic regcall
hazard).

## Acceptance
- An -O2-built compiler's `-S` output matches the -O0-built compiler's byte for
  byte (or at least passes `make test-asm`).
- `make test` green with an -O2-built compiler → then the -O2-default flip
  (OptLevel := 2, self-host -O2 fixedpoint, ~1.34x faster / ~11% smaller — all
  already measured) can re-land safely.

## Context — the reverted -O2-default work (re-apply after this fix)
Measured and proven EXCEPT this bug: OptLevel default 0→2, self-host -O2
fixedpoint byte-identical, make test-opt OK, c-testsuite 220/220, cross hello
4 targets. The missed-fold tripwire (`IROptWarnMissedFold`) must also be gated to
dev/measurement runs (NOT -Werror) when -O2 is default — inline produces foldable
BINOPs on every compile; see [[feature-revive-const-fold-identity-pass]]. Re-do
those together once the disassembler miscompile is fixed.

## Log
- 2026-07-10 — resolved, commit HEAD.
