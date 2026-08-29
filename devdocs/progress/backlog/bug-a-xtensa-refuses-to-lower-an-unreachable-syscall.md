---
track: A
prio: 45
type: bug
blocked-by: []
summary: "xtensa codegen errors with 'unsupported node in IR codegen: syscall' on a __pxxrawsyscall call that is statically unreachable on that target, which makes an otherwise-portable RTL unit uncompilable. Inconsistent with the ESP PAL's own pattern of refusing unsupported operations at RUNTIME rather than failing the build."
status: backlog
owner: unassigned
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
