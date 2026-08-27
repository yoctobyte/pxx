---
track: A
prio: 25
type: bug
blocked-by: []
status: done
owner: ""
summary: "`--target=riscv32` on a program with an external cdecl symbol fails with `target esp32: external (dynamic) symbols not yet supported`. The user typed riscv32, the message says esp32, and the two are different things — riscv32 is a hosted Linux target in its own right, not only the ESP32-C3 profile. One shared arm, one hard-coded name."
---

# A riscv32 diagnostic names the target as esp32

```
$ pascal26 --target=riscv32 -O0 uses_fabs.pas out
pascal26:2: error: target esp32: external (dynamic) symbols not yet supported
  in: compiler/builtin/softfloat.pas
```

`compiler/elfwriter.inc:1849`:

```pascal
if (TargetArch = TARGET_XTENSA) or (TargetArch = TARGET_RISCV32) then
begin
  if ExternalCount > 0 then
    Error('target esp32: external (dynamic) symbols not yet supported');
```

One arm serves two architectures and hard-codes one of their names. The
restriction itself is real and deliberate — neither backend emits a dynamic
segment, so a `cdecl external` cannot be resolved — but a user compiling for
**hosted riscv32 Linux** is told about a chip they are not targeting, and
`--target=riscv32` is a first-class target with its own qemu rows in the test
suite, not merely the ESP32-C3 profile's spelling.

Two smaller things wrong with the same line, worth fixing together since it is
being touched:

- **It does not say what to do.** "not yet supported" without naming the
  alternative (build the dependency in, or use a target that emits a dynamic
  segment — i386 / arm32 / aarch64 / x86-64 all do).
- **The `in:` line points at `softfloat.pas`**, an RTL unit the user never
  wrote, because that is where the first external happened to be. The symbol
  that triggered it is not named, so there is nothing to grep for.

## Shape

`Error('target ' + TargetArchName(TargetArch) + ': external (dynamic) symbols
are not supported on this target (' + <symbol> + '); link the dependency in
statically or build for a target with a dynamic segment')` — or the equivalent
if no arch-name helper exists yet, in which case adding one is the better fix
since this will not be the last message to want it.

Found 2026-08-24 while sweeping -O levels across targets.

## Gate

Track A's, plus the message naming riscv32 when riscv32 was asked for and xtensa
when xtensa was. No behaviour change — this is a diagnostic.
---

# Outcome — FIXED, 2026-08-27

All three complaints, since the line was being touched anyway.

## The target name

The ticket suggested a `TargetArchName` helper *"or the equivalent if no arch-name
helper exists yet, in which case adding one is the better fix"*. There was none —
`SocName` existed for the chip axis and nothing for the ISA. Added
`TargetArchName` and `TargetDisplayName` beside it in `defs.inc`.

**And a second bug found while testing it.** Naming the SoC was not enough:
`--target=riscv32` still reported `esp32c3`, because `compiler.pas` *defaults*
`TargetSoc` from the ISA. So the first attempt swapped one wrong chip name for
another — the ticket's exact complaint, one layer down.

Fixed with `SocExplicit`, mirroring the `PlatformExplicit` that already exists
for the same reason: a **derived** value must not be echoed back as though the
user chose it. `TargetDisplayName` prefers the SoC only when it was NAMED.

| user typed | before | after |
| --- | --- | --- |
| `--target=riscv32` | `target esp32` | `target riscv32` |
| `--target=xtensa` | `target esp32` | `target xtensa` |
| `--target=esp32c6` | `target esp32` | `target esp32c6` |
| `--target=esp32s2` | `target esp32` | `target esp32s2` |

## The other two

- **Names the symbol.** `first one: fabs` — `ExternalProc[0]` is a proc index,
  so the name was one lookup away. The `in:` line still points at
  `softfloat.pas`, which is honest (that *is* where the external is declared),
  but there is now something to grep for.
- **Says what to do.** *"this backend emits no dynamic segment, so link the
  dependency in statically or build for a target that has one (x86-64, i386,
  arm32, aarch64)"*.

## Verified

`test/test_target_name_in_external_refusal.pas`, wired into `test-core` as a
compile-fail test against **three** `--target` spellings, each grepped for its
own name, plus the symbol name. Hand-substituted and run, since the quick tier
does not reach `test-core`.

`gate.sh quick` GREEN; Pascal conformance 346/0/170/34, C conformance 220/0,
fgl 7/7.

## Log
- 2026-08-27 — resolved, commit c26978ffe.
