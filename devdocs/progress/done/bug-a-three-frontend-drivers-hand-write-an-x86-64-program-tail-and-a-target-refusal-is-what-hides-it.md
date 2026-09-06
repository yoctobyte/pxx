---
slug: bug-a-three-frontend-drivers-hand-write-an-x86-64-program-tail-and-a-target-refusal-is-what-hides-it
title: "Rust, Zig and Erlang emit a literal x86-64 `call main; exit_group` tail; the x86-64-only refusal is the only thing stopping it running"
track: A
prio: 50
type: bug
status: done
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

## 2026-09-06 (frankA) — the seam, read out of the code rather than guessed

Sized before editing, because the first estimate ("route the tail through
`EmitExitReg`") was too small. What each driver's entry stub actually owes:

| step | who owns it | already shared? |
| --- | --- | --- |
| save sp to `BSS_INITIAL_RSP` | every frontend | **no** — the slot is allocated by `EmitProgramPrologue` (`frontend_prologue.inc:73`), the WRITE is per-driver |
| `call __pxx_run_initializers(sp)` | C only, today | mechanism generic, caller C-only |
| load argc/argv into arg registers | **C only** | n/a — Rust/Zig `main` takes none |
| `call main`, patchable forward | every frontend | emit **no**, patch **YES** (`CPatchStubCall`, cparser.inc:11917, all six targets) |
| finalizer runner around the retval | every frontend | call **YES** (`EmitCallProc` is target-independent); the retval save/restore is per-target |
| `exit_group(retval)` | every frontend | **YES** — `EmitExitReg` (`emit.inc:1610`) already does exactly this on all six |

**So two of the six steps already have shared owners and the drivers do not use
them.** `EmitExitReg`'s own header says it exists because the rule *"was
previously restated by hand in each backend's AN_HALT arm, six copies of one
concept, and TWO of them drifted"* — these are copies seven and eight, and they
were uncounted because a refusal made them unreachable.

**The minimal correct increment**, and it is smaller than the full extraction:
add a shared `EmitEntryCallMainSlot(var callPatch, callAnchor)` — the per-arch
mirror of the `CPatchStubCall` that already exists — then each of the three
drivers becomes `EmitEntryCallMainSlot(...)` + `EmitExitReg`, with
`CPatchStubCall(...)` at the end. Four hand-written x86-64 instructions leave
three files and no new case is added anywhere. `cparser.inc` can adopt the same
slot emitter afterwards; it must not be in the same commit, because its arms
also carry the argc/argv and initializer steps and mixing the two makes the diff
unreadable.

**A SECOND LATENT DEFECT IN THE SAME PLACE, found while sizing this.** Nothing
in the skeleton drivers writes `BSS_INITIAL_RSP` at all — `EmitProgramPrologue`
allocates the slot for every program *"whether or not it reads its arguments"*,
and only a per-arch entry stub writes it. C and Pascal write it; Rust, Zig and
Erlang do not, on ANY target including x86-64. So `ParamCount`/`ParamStr`
reached from those frontends read an unwritten slot. **Not measured** — this is
a code reading, and the x86-64 case may be masked by BSS starting at zero, which
is exactly the shape that reads correct until it does not
([[an-uninitialised-read-is-usually-correct]]). Measure before claiming it; it
is listed here so the entry-stub work does not walk past it.

## 2026-09-06 (frankA) — LANDED: one mirror pair, and what the refusal was hiding

`EmitEntryStubCall` / `PatchEntryStubCall` now sit as adjacent routines in
`symtab.inc`, and `rparser.inc`, `zparser.inc` and `eparser.inc` call them plus
`EmitExitReg` / `EmitExit`. Twelve hand-written x86-64 bytes and three
hand-written rel32 patch formulas left three files, and no new `case TargetArch
of` was added anywhere.

**`PatchEntryStubCall` MOVED, and the move is the load-bearing half.** It was
`CPatchStubCall` in `cparser.inc`, which is included BEFORE the other three
drivers — so they could always have called it, right up until someone builds
with `PXX_NO_CFRONT`, which the compiler supports and reports on
(`compiler.pas:2242`). A shared routine reachable only while an unrelated
frontend is compiled in is borrowed, not shared. Also renamed: the `C` prefix
was accurate where it lived and would have been a lie afterwards.

### x86-64 is behaviour-identical and NOT byte-identical, deliberately

The four spot fixtures print exactly what the Makefile rows expect
(`test_rust_else_if` rc=20, `test_rust_advanced`, `test_zig_skeleton`,
`test_erlang_skeleton`). The BYTES differ, because `EmitExitReg` emits
`48 89 C7` (`mov rdi,rax`) where the hand-written tail emitted `89 C7`
(`mov edi,eax`) — the same exit status, since the kernel takes the low byte.
Recorded rather than smoothed over: anyone byte-comparing an x86-64 Rust or Zig
binary across this commit should expect a diff in the entry stub and nowhere
else.

**Two behaviour changes come free with the shared patcher, and both are fixes.**
`PatchEntryStubCall` calls `RecordEntryRoot(procIdx)` and, on the rel32 targets,
`RecordCodeRefAt`. The three drivers did neither: their `call main` had no
call-graph edge (so a reachability pass reads `main` as unreachable — the exact
thing `RecordEntryRoot`'s comment says it exists for) and no `CodeRef` (so the
site would not be re-aimed if a pass compacted the code between the stub and the
body). Neither was reachable as a live bug today; both were one pass away.

### What the refusal was hiding — measured, with the refusal temporarily lifted

Same experiment as the one that filed this ticket, re-run on the adopted
compiler. Before: every non-x86-64 binary died before its first syscall.
After:

| | i386 | aarch64 | arm32 | riscv32 |
| --- | --- | --- | --- | --- |
| Rust `else_if` (exit 20) | **rc 20** | **rc 20** | **rc 20** | **rc 20** |
| Rust `advanced` (4 lines) | **identical** | **identical** | **identical** | compile fail |
| Zig `skeleton` (8 lines) | **identical** | **identical** | **identical** | compile fail |
| Erlang `skeleton` | SIGSEGV | SIGILL | SIGILL | compile fail |

"identical" is against the native run's output, compared whole, not eyeballed.

**So the entry stub was the whole of it for Rust and Zig, and it is NOT the whole
of it for Erlang.** The Erlang binary now REACHES `main` and prints — i386 gets
`fact(5) is 1` (native: `120`) and part of the next line before it faults, which
is a wrong value and then a crash INSIDE the body. That is a different defect
and it is only visible now that the tail stopped hiding it: with the old tail
the program died before its first syscall on every target, so nothing it printed
could be observed. **The two riscv32 compile failures are frontend-level and
also newly visible** for the same reason — the refusal ran before either could
be reached.

**Narrowing the refusals is the next commit and is deliberately not this one.**
It changes what the compiler ACCEPTS, so it wants its own test rows; and the
honest narrowing is per frontend, not one edit repeated three times — Rust to
five targets, Zig to four (riscv32 excluded, compile failure), Erlang to x86-64
alone with the ticket for the body defect filed beside it. Rewriting all three
refusals identically is what produced this ticket in the first place.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 6f0ee4be7.
