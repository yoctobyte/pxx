---
slug: bug-a-aarch64-passes-a-variadic-float-in-an-fp-register-so-glibc-reads-zero
title: "aarch64: a float in a VARIADIC argument tail is passed in an FP register, so a real C callee reads 0.00 — and every argument after it is wrong too"
track: A
prio: 55
type: bug
status: open
created: 2026-09-03
found-by: frankB
owner:
blocked-by: []
summary: "`sprintf(buf, '[%.2f]', 3.5)` through a dynamic import of the target's own glibc prints `[0.00]` on aarch64 and `[3.50]` on arm32, x86-64 and fpc 3.2.2. With a following integer, `'[%d %.2f %d]', 1, 3.5, 2` gives `[1 0.00 0]` — THE ARGUMENT AFTER THE FLOAT IS LOST AS WELL, which is the signature of a slot-counting disagreement rather than a value bug. AAPCS64 §6.4.2 puts every VARIADIC argument, floating-point included, in the general registers and then the stack; pxx appears to route a double into v0 as it would for a fixed parameter, so the callee reads the untouched general slot. INVISIBLE TO EVERY pxx-vs-pxx TEST because pxx's own crtl `sprintf` reads it back from the same wrong place: the identical C program built with pxx's crtl instead of `--system-libs` prints `[3.50]` on aarch64, self-consistently and wrongly. THE ORACLE IS A DYNAMIC CALL INTO THE TARGET'S REAL GLIBC and it needs no cross compiler and no linker — see the note below, which also corrects my own claim of an hour ago that aarch64 has no constructible oracle."
---

# The measurement

```pascal
program d1;
function sprintf(buf: Pointer; fmt: PChar): Integer; cdecl; varargs; external 'libc.so.6';
function puts(s: PChar): Integer; cdecl; external 'libc.so.6';
function fflush(f: Pointer): Integer; cdecl; external 'libc.so.6';
var b: array[0..127] of Char;
begin
  sprintf(@b[0], PChar('[%.2f]'), 3.5);        puts(@b[0]);
  sprintf(@b[0], PChar('[%d %.2f %d]'), 1, 3.5, 2); puts(@b[0]);
  fflush(nil);
end.
```

| build | row 1 | row 2 |
| --- | --- | --- |
| fpc 3.2.2 (x86-64) | `[3.50]` | `[1 3.50 2]` |
| pxx x86-64 | `[3.50]` | `[1 3.50 2]` |
| pxx arm32 | `[3.50]` | `[1 3.50 2]` |
| **pxx aarch64** | **`[0.00]`** | **`[1 0.00 0]`** |

`tools/run_target.sh aarch64` for the cross rows. **arm32 is the control that
matters**: same rig, same qemu, same real glibc, and it is correct — so this is
not the harness, the sysroot or the emulator, it is aarch64's variadic argument
placement.

**Row 2 is the sharper one.** The trailing `2` prints as `0`, so the callee and
the caller disagree about how many slots the float consumed, not merely about
where its bytes are. That is what AAPCS64 §6.4.2 describes: in a call to a
variadic function every argument in the variadic part is passed as if it were an
integer argument — general registers, then the stack — and the FP register bank
is not used at all. Passing the double in `v0` leaves the general slot the callee
reads untouched and shifts everything after it.

Not verified: which site does it. `ABIA64CdeclArgSlot` and the variadic arms in
`ir_codegen_aarch64.inc` (the ones testing `ProcVariadic`) are where to look, and
the fix has to know the FIXED parameter count to know where the variadic part
starts.

# Why no existing test could see it

**pxx's own `crtl` reads the argument back from the same wrong place.** The
equivalent C program compiled by pxx *without* `--system-libs=c`, so that
`sprintf` comes from `lib/crtl`, prints `[3.50]` on aarch64 — correct-looking,
and it proves nothing, because both halves were built by the same compiler out
of the same belief. That is precisely the self-consistency
`bug-a-c-a-by-value-struct-parameter-is-passed-as-a-pointer-to-every-c-abi-callee`
exists to show is worthless for a calling convention, and here it is with a
worked example.

# THE ORACLE — and a correction to my own note of an hour ago

`bug-a-an-aggregate-argument-is-a-pointer-by-construction-on-aarch64` and
`bug-a-c-the-variadic-struct-abi-is-still-a-pointer-on-aarch64-arm32-and-riscv32`
both say their first deliverable is an oracle, and I added a note to both
(`2dd981a7b`) concluding that the missing piece is a LINKER. **That note is
correct about a static mixed link and it is incomplete as an answer to "is there
an oracle", which is the question those tickets actually ask.**

A mixed **link** is not required. A mixed **call** is, and it already works:

- **`~/.cache/pxx-cross/aarch64/lib/` and `.../arm32/lib/` hold a complete
  glibc** — `libc.so.6`, `libm.so.6`, `ld-linux-aarch64.so.1`, the nss modules —
  installed by `tools/install_qemu.sh`, and `run_target.sh` already points
  `QEMU_LD_PREFIX` at it.
- pxx can already emit a **dynamic import** for those targets
  (`external 'libc.so.6'`), and it resolves and runs.
- So a pxx-compiled caller and a **gcc-compiled glibc** exchange arguments
  across a real ABI boundary, with the observable being the callee's own
  formatted output. No cross gcc, no cross ld, no lld, nothing to install.

That is a genuine external reference for **any ABI question expressible as a
call into libc**: variadic tails (this ticket), by-value aggregates
(`struct`-taking libc entry points are thin on the ground, but `qsort`'s
comparator, `memcpy`'s sizes and the `printf` family cover argument placement,
promotion and slot counting), and float ABI. It does NOT cover a pxx-compiled
CALLEE receiving from a gcc-compiled caller — for that direction the linker
really is needed, and `qsort` with a pxx comparator is the exception that
reaches it through a function pointer.

**riscv32 and xtensa are not covered either way**: both refuse dynamic symbols
outright (`target riscv32: external (dynamic) symbols are not supported on this
target`), and there is no sysroot for them.

I am leaving the linker note where it is on both tickets and adding a pointer to
this section rather than rewriting it, because it is true about the thing it
describes; what was wrong was letting it stand as the answer to a question with a
cheaper answer.
