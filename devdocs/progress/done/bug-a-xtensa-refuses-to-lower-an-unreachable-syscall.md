---
track: A
prio: 45
type: bug
blocked-by: []
summary: "xtensa codegen errors with 'unsupported node in IR codegen: syscall' on a __pxxrawsyscall call that is statically unreachable on that target, which makes an otherwise-portable RTL unit uncompilable. Inconsistent with the ESP PAL's own pattern of refusing unsupported operations at RUNTIME rather than failing the build."
status: done
owner: frankS
---

# xtensa refuses to lower a syscall that cannot be reached on xtensa

- **Type:** bug — Track A (`ir_codegen_xtensa.inc`), Track S campaign.
- Found 2026-08-28 (Track B) while re-checking `feature-random-library`'s
  cross-target claims. Filed rather than worked around: `lib/rtl/random.pas` is
  written correctly and must stay that way.

## Repro

```
$ cat ru.pas
program ru;
uses random;
begin
  XoshiroSeed(1);
  if XoshiroNext = 0 then WriteLn(0);
end.

$ pinned --target=xtensa --platform=esp -Fulib/rtl -Fulib/rtl/platform/esp ru.pas ru.o
pascal26:292: error: target xtensa: unsupported node in IR codegen: syscall
```

The same command with `--target=riscv32 --platform=esp` **succeeds**, so this is
xtensa-specific rather than a general ESP-profile gap.

## Why the code is already correct

`lib/rtl/random.pas`'s tier 2 is guarded by data, not by conditionals:

```pascal
function SysGetRandom: Integer;
begin
  Result := -1;                                    { bare-metal targets }
  {$ifdef CPUX86_64}  Result := 318; {$endif}
  ...
  { CPU_XTENSA (ESP32): no getrandom; use HW RNG register (tier 1) }
end;

function OSEntropyBytes(buf: Pointer; n: Integer): Boolean;
begin
  sn := SysGetRandom;
  if sn < 0 then begin OSEntropyBytes := False; Exit; end;
  r := __pxxrawsyscall(sn, ...);
```

On xtensa `SysGetRandom` returns -1 and the function exits before the syscall.
**The call is statically unreachable there**, and the unit's design mandate is
explicitly that per-arch detail stays out of the `.pas`. Wrapping the call in
`{$ifdef}` to make the compiler happy is the compiler-appeasement workaround
CLAUDE.md forbids, so the platonic code stays and this ticket carries the defect.

## Why it is a defect and not a correct refusal

Refusing an operation the hardware cannot perform is right in general. The
question is *when*, and the repo already has an answer: the **ESP PAL refuses 33
entry points at RUNTIME** with `PAL_ERR_UNSUPPORTED` rather than failing the
build, precisely so that POSIX-shaped code meets an honest error instead of
being uncompilable. Codegen refusing `syscall` at compile time contradicts that
pattern and has a worse consequence — it takes a whole portable unit out of the
target rather than one call.

xtensa is the **primary** ESP target (the S2/S3 hardware), so a library that
cannot be compiled there is more costly than the same gap on riscv32.

## Fix sketch

Lower `syscall` on xtensa to a stub that returns the unsupported error (or traps)
rather than erroring at codegen — the same shape the PAL already uses. That keeps
genuinely-reachable misuse detectable at runtime while letting unreachable calls
compile away.

Worth deciding rather than guessing: whether the stub should trap loudly or
return `-PAL_ERR_UNSUPPORTED`. The PAL's precedent is the latter, and a silent
wrong VALUE is not a risk here because every caller of `__pxxrawsyscall` in tree
checks the result.

## Also found, and NOT this ticket

`feature-random-library` claims "riscv32 cannot build this unit at all", citing
atomics. Measured today: it builds fine under `--target=riscv32 --platform=esp`.
The atomics refusal appears only for **hosted** riscv32 (`mstatus`/machine-mode
CSR access, which a user-mode program does not have). That claim is corrected in
that ticket rather than here.

## Gate

Track A's: `make compiler/pascal26` (which is the self-host fixedpoint) plus the
repro above compiling, plus cross where xtensa is touched.

## Resolution (frankS, 2026-08-29)

Fixed in `compiler/ir_codegen_xtensa.inc`: `IR_SYSCALL` now lowers to
"evaluate the args, then answer `-38`" instead of falling through to the
`else Error`.

### Root cause — xtensa was the ONLY backend with no `IR_SYSCALL` case

Not an ESP-profile gap and not a deliberate refusal. `ir_codegen386`,
`_aarch64`, `_arm32` and `_riscv32` all have an `IR_SYSCALL:` case;
xtensa had none, so the op fell to the catch-all `Error` at the bottom of
`IREmitNodeXtensa`. The omission was already visible as an inconsistency
*inside the file*: the statement-level walker at the foot of the same unit
lists `IR_SYSCALL` among the value nodes to skip ("consumed by its parent"),
i.e. the surrounding code was written expecting a value case that was never
added.

### The design question the ticket flagged — settled from evidence, not guessed

The ticket asked whether the stub should trap loudly or return
`-PAL_ERR_UNSUPPORTED`, and called it worth deciding rather than guessing.
It did not need to become a Track U item, because two measurements settle it:

1. **`PAL_ERR_UNSUPPORTED` is `-38`, and `lib/rtl/platform.pas:93` documents
   it as "Linux ENOSYS, used as the portable 'not here'".** So returning it
   is not adopting a local convention — `-ENOSYS` is *literally* what a kernel
   answers for a syscall number it does not implement. The PAL's 33 refused
   entry points and the correct errno are the same value by construction.
2. **xtensa has no configuration in which a Linux syscall could succeed.**
   `util.inc:88` spells the dual roles out: riscv32 is bare ESP32-C3 **or
   hosted Linux**, which is exactly why riscv32's `ecall` is right — it is
   real in the hosted role. xtensa's two roles are bare metal and
   IDF/FreeRTOS-linked, and neither has a Linux kernel under it. So the
   asymmetry with riscv32 is principled, not a remaining gap: there is no
   xtensa spelling of this op that could ever succeed.

This is deliberately **not** the `IR_FRAME` precedent (`defs.inc:816`), where
xtensa Errors at lowering rather than "lie with a plausible-looking pointer".
That case has no honest answer available on a windowed-register machine;
this one does, and `-ENOSYS` is it.

Args are still emitted and their values discarded — they are arbitrary
expressions and may have side effects.

### Verified (binary `253ca28560fa`, self-host fixedpoint, converged 1 round)

- The ticket's repro now compiles on xtensa; riscv32 output is unchanged
  byte-for-byte in size (`code=357768B data=2840B`, identical pre/post).
- Emitted code inspected rather than assumed: both the unreachable case
  (`random.pas`) and a directly reachable `__pxxrawsyscall` contain exactly
  one `22 AF DA 32 AF FF` = `movi a2,-38 ; movi a3,-1`. The `a3` word confirms
  the 64-bit path is taken, so the `Int64` result is correctly sign-extended;
  riscv32 objects contain the pattern zero times.
- Arg side effects preserved, cross-checked against riscv32 as the reference
  backend: swapping a constant arg for one call costs +0 bytes on xtensa vs
  +4 on riscv32 (a 3-byte `call0` replaces a 3-byte `movi`, hence zero), and a
  second call costs +60 vs riscv32's +64. Dropped args would have made all
  shapes identical; they do not.
- `test_esp_bare`, `test_esp_class`, `test_esp_exception` still build on xtensa.
- `tools/gate.sh quick`: every step PASS except the pre-existing Track R
  `rparser.inc:2786` duplicate forward
  (`bug-r-a-duplicate-forward-in-rparser-breaks-the-fpc-seed-build`), which is
  unrelated to this change and not Track S's to touch.

### Follow-up left for Track B, not done here

The ticket's closing note — that `feature-random-library` wrongly claims
riscv32 "cannot build this unit at all" — is confirmed still true: the unit
builds fine under `--target=riscv32 --platform=esp`. Correcting that claim
belongs in that ticket and is not touched here.

## Log
- 2026-08-29 — resolved, commit cf72dd641.
