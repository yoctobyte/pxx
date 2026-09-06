---
slug: bug-a-three-frontend-drivers-hand-write-an-x86-64-program-tail-and-a-target-refusal-is-what-hides-it
title: "Rust, Zig and Erlang emit a literal x86-64 `call main; exit_group` tail; the x86-64-only refusal is the only thing stopping it running"
track: A
prio: 50
type: bug
status: backlog
owner: ""
created: 2026-09-06
found-by: frankA
tags: [cross-target, frontend, entry-stub, i386, aarch64, arm32, riscv32]
blocked-by: []
summary: "MEASURED 2026-09-06 by disabling the refusal locally and rebuilding: with `TargetArch <> TARGET_X86_64` no longer refused, the Rust and Zig frontends COMPILE CLEAN for i386, aarch64 and arm32 (Zig also riscv32) -- parser, layout, IR, codegen and the shared entry stub are all already target-agnostic -- and every one of those binaries dies before its first syscall. SIGILL at the program tail, and the faulting bytes are `e8 09 00 00 00 / 31 ff / b8 e7 00 00 00 / 0f 05` sitting in an AARCH64 text section: x86-64 `call main; xor edi,edi; mov eax,231; syscall`. rparser.inc:5799-5802, zparser.inc:2019-2029 and eparser.inc:543-546 emit those four instructions UNCONDITIONALLY, with no `case TargetArch of`. cparser.inc has the same four at 12080/12095 but inside a per-arch case, which is why C crosses. These are the seventh and eighth hand-written copies of the concept `EmitExit`/`EmitExitReg` exists to own -- EmitExitReg's own header records that it was created because the rule 'was previously restated by hand in each backend's AN_HALT arm, six copies of one concept, and TWO of them drifted'. THE REFUSAL IS LOAD-BEARING AND MUST NOT BE LIFTED FIRST: it is not stale conservatism, it is the only thing converting a crashing binary into an honest error. This is the residual that RERANKS the Rust and Zig halves of [[bug-a-pascal-nilpy-rust-and-zig-over-align-an-8-byte-member-on-i386]] from live defects to latent ones."
---

# The x86-64 program tail three drivers write by hand

## The measurement, and how it was taken

Local probe only, reverted: the two `Error('... only the x86-64 target is
supported by the skeleton')` lines (`rparser.inc:5774`, `zparser.inc:1983`)
replaced with a no-op, `make compiler/pascal26` converged, matrix run, tree
restored with `git checkout HEAD -- ` and rebuilt back to `0426b285ba35`.

| source | x86_64 | i386 | aarch64 | arm32 | riscv32 |
| --- | --- | --- | --- | --- | --- |
| `.rs` | runs | compiles, **SIGSEGV** | compiles, **SIGILL** | compiles, **SIGILL** | `PXXWriteDecW not found` |
| `.zig` | runs | compiles, **SIGSEGV** | compiles, **SIGILL** | compiles, **SIGILL** | compiles, **SIGILL** |

The Zig row is the one that isolates it: `pub fn main() void { var x: i64 = 7;
_ = x; }` does no I/O, touches no RTL, and still dies on every non-x86-64
target while exiting 0 on x86-64. **So the gap is the entry/exit path, not the
library surface.**

`qemu-aarch64 -strace` puts the fault at `0x40029c` with **no syscall issued at
all**, against the Pascal control which reaches `exit_group(0)` normally. The
bytes there:

    e8 09 00 00 00    call rel32
    31 ff             xor edi, edi
    b8 e7 00 00 00    mov eax, 231
    0f 05             syscall

x86-64, in an `EM_AARCH64` object.

## Where they come from

    rparser.inc:5799-5802    unconditional
    zparser.inc:2019-2029    unconditional
    eparser.inc:543-546      unconditional
    cparser.inc:12080/12095  inside `case TargetArch of TARGET_X86_64: ... TARGET_I386: ...`

The C driver is the control: same four instructions, wrapped in a per-arch case,
and C crosses to every target. The Rust driver's own comment says it plainly —
*"Rust's body is three instructions, and this driver writes them itself rather
than getting them from a parse"*.

`EmitExitReg` (`emit.inc:1610`) is the routine that owns this: it issues
exit_group with the code in each target's natural result register, and **its
header exists because this exact duplication already bit us once** — *"six
copies of one concept, and TWO of them drifted"*. These are copies seven and
eight, uncounted because nothing could reach them.

## What to do, and the order matters

1. **Do not lift the refusal first.** It is doing real work: it turns a binary
   that compiles clean and then crashes into an error with a name on it. A green
   bought by removing it would be worth less than the red.
2. Route the tail through the shared per-arch emitters — `EmitCallProc` for the
   call (already target-independent; `cparser.inc:12089` uses it for the
   finalizer runner) and `EmitExitReg` for the exit — in all three drivers.
3. **Then** narrow the refusal to what is still genuinely unsupported, per
   frontend and per target, rather than deleting it. `.rs` on riscv32 stops
   earlier and for a different reason (`PXXWriteDecW not found`, the `println!`
   int-to-text path), so riscv32 is not covered by this fix for Rust.
4. Only after that does the i386 half of
   [[bug-a-pascal-nilpy-rust-and-zig-over-align-an-8-byte-member-on-i386]]
   become reachable for R and Z, and its `TypeAlign` -> `TypeFieldAlign`
   substitution become something a test can go red or green on.

## Acceptance

A relation, not a constant: **a program whose result is its exit code must
produce the same exit code on every target the frontend accepts.** No expected
width, no per-target literal, and the pre-fix control is free — every
non-x86-64 row above is a crash today.

Seven further frontends refuse identically (`aparser`, `fparser`, `lparser`,
`gparser`, `wparser`, plus `bparser` and the stackful-generator backend); this
ticket covers only the three whose tail is measured to be x86-64 machine code.
