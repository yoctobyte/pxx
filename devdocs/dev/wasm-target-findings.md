# wasm32 as a target — what it actually costs us

Measured 2026-08-27, re-verified against `master@8787cfe42`, during the scoping
session that opened `feature-target-wasm` and
`refactor-a-target-dispatch-chains-fail-open`.

> **Correction, same day.** The first version of this note was written against a
> checkout 379 commits behind `master` and claimed the compiler had no single
> answer for pointer width. **It does** — `TARGET_PTR_SIZE`, `defs.inc:1758`,
> read at 129 sites. That claim came from a grep that only looked for
> `function TargetPtrSize` and so could never have matched a variable. Caught by
> frank1-80. Everything else below was re-measured on `master` and holds.

This is a **findings note, not a plan.** The development plan lives on the
`wasm` branch (`devdocs/dev/wasm/PLAN.md`), because the work is being done in a
standalone checkout. What is here is the part every track should be able to read
without leaving `dev`: the numbers, and the two places the work escapes a
backend file.

`devdocs/developer/frontends-and-targets-strategy.md` has the older
*rationale* for wasm ("reloop + emit + WASI, bounded, park it"). It is still
right about the shape and it undercounts two things. Those two are the point of
this note.

## The IR side: 76 ops, and 17 are the whole risk

| bucket | count | what it is |
| --- | --- | --- |
| mechanical transliteration | ~50 | consts, loads/stores, binop, index/field, args, sets, variants, records, dyn arrays, strings, RTTI. Register → wasm local; addressing mode → explicit `i32.load` / `i32.store`. |
| control flow → restructure | 5 | `IR_BLOCK`, `IR_IF`, `IR_LABEL`, `IR_JUMP`, `IR_JUMP_IF_FALSE`. wasm has structured control flow only. |
| code addresses → table indices | 5 | `IR_PROCADDR`, `IR_CALL_IND`, `IR_VIRTUAL_CALL`, `IR_VMTADDR`, `IR_IMTADDR`. |
| exceptions → redesign | 7 | `IR_EXC_ENTER/LEAVE/MATCH/MATCH_HIT/STORE/CLEAR`, `IR_RAISE`. |
| **already refused on non-x86 targets — free** | 9 | `IR_SYSCALL`, `IR_ASM`, `IR_CLONE`, `IR_COSWITCH`, `IR_YIELD`, `IR_SET_SIGNAL`, `IR_ATOMIC`, `IR_IO_LOCK`, `IR_IO_UNLOCK`. |

The last row matters and is easy to miss. `thread_emit.inc` and
`coroutine_emit.inc` are already `if TargetArch = ...` chains that simply do not
emit for xtensa/riscv32; `IR_SET_SIGNAL` is documented x86-64-Linux-only.
wasm falls into an existing hole at zero cost. Threads and coroutines are not a
wasm problem — they are already a five-of-six-targets problem.

Why the mechanical bulk really is mechanical: **wasm locals are an infinite
typed register file.** A wasm backend transliterates `ir_codegen_riscv32.inc`
more cleanly than any other pair in the tree — no register allocator, no spill
logic, no encoder tables, no addressing modes.

## Escape #1 — VMT slots hold code addresses, and wasm has none

`elfwriter.inc:1937` — *"Method-pointer fixups: patch the 32-bit code address
into each VMT slot"*, via the fixup list described at `emit.inc:105` (*"Every
VMT slot and every RTTI [entry] ... patched to the entry address of
Procs[procIdx]"*).

In wasm, code is not in linear memory and has no address. A function pointer is
a **table index**, and every indirect dispatch is `call_indirect` against a
*type index*. So a VMT slot must hold an index, not an address.

The good news is that the mechanism is centralized: one fixup list, one patch
site in the writer. The change is *what a fixup resolves to*, not where it is
applied. But it is a shared-file change in Track A's ground, not a new file —
which is why it is written down here rather than left in the backend's own
notes.

**Open question — ANSWERED 2026-08-27, and the answer is favourable.** Does
anything rely on `IR_PROCADDR` values being *comparable* or arithmetic-able
rather than merely callable? Table indices break ordering and arithmetic.

Grepped `lib/`, `examples/`, `compiler/` for casts of `@proc` to an integer
type, ordered comparison of procvars, and arithmetic on them. **The only hits
are in `lib/rtl/scheduler.pas`** (`Int64(@CoStart)` written into a hand-built
stack frame as a return address, four times, one per architecture). Nothing
compares procvars with `<`/`>`; nothing does arithmetic on one.

That single consumer is the coroutine stack-frame builder — **already out of
scope for wasm** (`IR_COSWITCH` / `IR_YIELD` are in the already-refused bucket,
and `coroutine_emit.inc` is a per-target chain that emits nothing for
unrecognised targets). So the risk is contained to code wasm cannot run anyway.

**Table indices are viable.** Assignment, calling, and comparison against nil
all work if index 0 is reserved as the null function reference.

## Escape #2 — exceptions are a hand-rolled setjmp/longjmp

`exception_emit.inc` saves the callee-saved registers, `rsp` and a return
address, and jumps back into a live frame. wasm has no addressable call stack
and no way to jump to a saved address. This does not port; it gets redesigned.

Two routes, and the cheap one composes with the control-flow work:

- **Pending-flag threading** (recommended for v1). In a `br_table` dispatch
  layout a longjmp *within* a function is `$label := N; continue` — free. Across
  functions it is an early return plus a check after each call, branching to the
  frame's landing label. No engine proposal, no version dependency.
- **The wasm EH proposal** (`try_table` / `throw`). Genuinely shipped now, but
  the legacy-vs-final opcode split is live fragmentation, and it needs the
  protected region to be a structured block — which fights the flat IR.

## The shared-file tax — smaller than first reported, and differently shaped

**Correction.** Pointer width is *not* the problem: `TARGET_PTR_SIZE` exists and
is consulted at 129 sites. And the ~180 raw `TargetArch` references
(`ir_codegen.inc` 83, `symtab.inc` 47, `cparser.inc` 31, `elfwriter.inc` 27,
`lexer.inc` 19) are mostly *legitimately* per-arch codegen — five ISAs need five
encoders.

`util.inc:87` (`TargetIsEspClass`) already performed the one collapse worth
performing, and its comment documents **13 sites it deliberately refused**,
because `(xtensa or riscv32)` there means four different things. That refusal is
the most useful prior art on this subject and should be read before anyone
proposes a sweep.

What survives as a real hazard for a 7th target is narrow: several chains
**fail open**. `lexer.inc:936` runs `if TargetArch <> TARGET_X86_64 then begin`
and then an `if`/`else if` over the five non-x86-64 targets **with no final
`else`**. wasm32 would enter that block, match nothing, and be configured with
no CPU defines at all — silently. Filed as
`refactor-a-target-dispatch-chains-fail-open` (prio 50, backlog).

**This does NOT block the wasm target.** A wasm32 target says its pointer width
the same way every other target does — `TARGET_PTR_SIZE := 4` in the
`compiler.pas:1508` arm. The chains are something to fix on the way past, not a
gate in front.

## The PAL side: a bigger refusal surface than ESP, and inverted

~90 `Pal*` entry points in `lib/rtl/platform.pas`. Under **WASI preview1**,
roughly **35 work and ~55 refuse**:

- **work** — all file I/O via preopens (`path_open`, read/write/seek/stat/
  readdir/mkdir/rename/unlink/symlink/truncate/sync), clocks, sleep, yield,
  args, environ, random.
- **refuse (~26)** — the entire socket set. Preview1 has only
  `sock_recv/send/accept/shutdown`: no `socket()`, no `bind`, no `connect`.
- **refuse (~10)** — fork / vfork / execve / wait4 / kill / signals / pipe.
- **refuse (~8)** — uid/gid/chmod/chown/umask; there is no permissions model.
- **refuse (~4)** — mmap/mprotect/munmap; the heap grows via `memory.grow`.
- **refuse** — dlopen/dlsym, and chdir/getcwd (preopens only, no cwd).

**It is an inversion of ESP, not a repeat.** ESP has sockets (lwIP) but no
processes and no real filesystem; WASI has a filesystem but no sockets and no
processes. The PAL already models exactly this — a third backend directory and
`PAL_ERR_UNSUPPORTED`, the same deliberate-refusal pattern Track S established,
at roughly the size of `esp/platform_backend.pas` (1,035 lines).

Pin to **preview1**. Preview2 / the component model is a moving target and buys
nothing here.

## What the limitation costs *our own* code

Grepped across `lib/`, `examples/`, `test/`:

| needs | files |
| --- | --- |
| sockets (`PalSocket`/`PalConnect`/`PalBind`/`PalListen`) | 27 |
| processes (`PalVfork`/`PalExecve`/`PalWait4`) | 16 |
| `PalMmap*` | 2 |

Those do not run under wasm — not "run slowly", do not run. A wasm target is
excellent for **compute + file I/O** and useless for anything networked.

Which is the argument for anchoring the whole effort on **the compiler itself**:
single-threaded, file I/O only, no sockets, no fork. It is the one large program
that fits the platform exactly, and its correctness is checkable absolutely.

## A third "byte-identical" — state it carefully

CLAUDE.md's claims-discipline table has two rows. This work would add a third,
and it is neither of the existing two:

| claim | what is identical | to what |
| --- | --- | --- |
| self-host fixedpoint | the **binary** | our own previous output, at the default `-O` |
| zlib / C corpora | the program's **output** | a gcc-*built* zlib's output |
| **wasm-hosted compiler** | the **emitted output bytes** | the *native* compiler's emitted bytes, same input |

It is *output* parity across two hosts of the same compiler. It is not a
self-host fixedpoint and must never be written as one.

## Keeping the branch merge-free: register on `master` first

The branch is cheap because it is ~85% new files. The other 15% is not codegen,
it is **registration** — teaching existing dispatch chains that a 7th target
exists — and that is exactly the part that conflicts on every merge.

Measured from `bd49a59535c3`, the commit that introduced riscv32 **and** xtensa
together: **~270 lines across 9 shared files** (`symtab.inc` 97, `parser.inc`
70, `emit.inc` 34, `compiler.pas` 20, `lexer.inc` 18, `elfwriter.inc` 12,
`ir_codegen.inc` 10, `exception_emit.inc` 7, `defs.inc` 2). One target is less.

Landing that registration on `master` **before** the branch accumulates work —
as a skeleton that Errors, with no codegen — means the branch touches zero
shared files until Phase 4. Filed as
`feature-a-wasm32-target-registration-skeleton`.

## Sizing, anchored to comparable artifacts in-tree

| item | lane | size | comparable |
| --- | --- | --- | --- |
| `ir_codegen_wasm32.inc` | A (new file) | ~3-4k | `ir_codegen_riscv32.inc` = 3,891 |
| `wasmenc.inc` + module writer | A (new file) | ~1-1.5k | `elfwriter.inc` = 3,740; wasm sections are far simpler |
| `asmtext_wasm.inc` (WAT) | A (new file) | ~500 | peers are 420-918 |
| `br_table` dispatch + exception threading | A (new file) | ~500 | the design risk lives here |
| VMT fixup → table indices | **A (shared)** | small | escape #1 |
| dispatch-chain `else` audit | **A (shared)** | small | filed separately, NOT a prerequisite |
| `lib/rtl/platform/wasi/` | B (new dir) | ~1k | `esp/platform_backend.pas` = 1,035 |

Roughly **7-9k lines, ~85% in new files that cannot destabilize an existing
lane**, plus two contained shared-file changes in A.

## Two notes on the platform that will bite whoever writes the backend

- **Address 0 is valid linear memory.** `nil^` does not trap; it reads offset 0.
  This is the one bug class where wasm is *worse* than x86. Reserve the first
  page and emit explicit nil checks under a debug flag.
- **The shadow stack has no guard page.** wasm's own call stack traps on
  exhaustion (good), but the linear-memory frame stack will run into the heap
  silently. Explicit limit check in the prologue, at least under `-g`.

Against that, wasm validates the whole module before running and traps on
out-of-bounds linear memory — so every codegen type error is a precise load-time
error instead of a segfault three functions later, and the target doubles as a
sanitizer for the RTL.
