---
track: A
summary: "RTL-over-libc lowering mode — route runtime primitives through a system C library instead of raw syscalls"
type: feature
prio: 55
---

# RTL-over-libc — the portability force multiplier

- **Type:** feature (Track A — RTL lowering / codegen / linking). Portability campaign.
- **Status:** done — the LOWERING landed (`3a0ed43fb`): `--rtl-libc` routes
  compiler-generated kernel entries through a thunk calling libc's `syscall()`,
  measured 75 raw kernel-entry instructions down to 1 on `test/hello.pas`.
  (This line previously read "acceptance instrument landed, no compiler changes
  made", which was true of the 2026-08-17 park and was left standing after the
  code landed. It sent a reader sizing `feature-port-openbsd-libc` to conclude
  the lowering did not exist. The remainder is split out as
  `feature-rtl-libc-frontend-sites-and-thread-errno`.)
- **Owner:** frankA
- **Opened:** 2026-07-17, from the OS-portability mapping session. Full analysis in
  [`devdocs/dev/portability-axes.md`](../../dev/portability-axes.md).
- **Related / unblocks:** [[feature-port-openbsd-libc]] (falls out immediately),
  [[feature-port-windows-pe]] (same "call the system lib" lowering, + PE writer),
  [[feature-port-macos]] (blocked on hardware, but same lowering). Sibling:
  [[feature-port-freebsd-native]] (the raw-syscall path that does NOT need this).
  North star: [[ir-as-substrate]].

## Why

pxx is libc-free on Linux because Linux has a stable, public raw-syscall ABI — the
**exception** among OSes. Every other mainstream OS (OpenBSD, macOS, Windows) makes a
**system C library** the supported kernel boundary. The generalizable capability that
unlocks all of them is **one lowering mode**, not per-OS special cases:

> Wire the RTL primitives (`write`/`read`/`open`/`mmap`/`munmap`/`exit`/`brk`/
> `nanosleep`/…) to **C-library entry points** (`write(2)`, `mmap(3)`, `_exit`, …)
> instead of emitting the raw `syscall` instruction.

pxx already dynamic-imports external `.so`s through the PLT (the C frontend links C
libraries; `elfwriter.inc` emits `PT_DYNAMIC`/`DT_NEEDED`/interp). So this is *wiring
existing machinery to the RTL's own primitives*, not a new subsystem.

## Design

- A platform/ABI switch (`--platform=<os>` or the existing PAL axis — see
  [[project_pal_platform_axis_step1]]) selects **syscall-emit** vs **libc-call** for
  the RTL primitive set.
- In libc-call mode, each primitive lowers to a call to the named libc symbol
  (imported via `DT_NEEDED libc.so` + PLT), with the platform's C ABI (SysV amd64 on
  ELF platforms; MS x64 comes with [[feature-port-windows-pe]]).
- Error convention becomes libc's: `-1` + `errno` (TLS `__errno_location`) instead of
  Linux's negative-rax — the RTL's error checks branch on the mode.
- Keep the primitive *set* identical; only the lowering of each changes. Everything
  above the primitives (managed strings, heap, exceptions) is untouched.

## The switch reaches UP into codegen, not just the RTL library (2026-07-21 scout)

Sizing the Windows target surfaced a subtlety worth pinning here: raw `syscall` lives in
**two** places, and the lowering switch must cover both — it is not purely an
`lib/rtl/*` edit.

1. **RTL primitives (the library half — expected).** `lib/rtl/pxxcio.pas` is the single
   IO chokepoint (fd 1, `__pxxrawsyscall`), plus `ansiterm.pas:192`. libc/kernel32 mode
   swaps these. Straightforward.
2. **Emitted program startup (the codegen half — easy to miss).** The compiler emits a
   raw `syscall` instruction into the program's **own `_start` stub**:
   `compiler/emit.inc:116` `EmitwriteSyscall` (i386 `int 0x80` `:118`, aarch64 `svc`
   `:105`), `EmitSyscall`=`0F 05` at `emit.inc:80`, `SYS_WRITE=1` at `defs.inc:601`.
   This is **codegen**, below the RTL — in libc/DLL mode it must emit a `CALL` to an
   imported symbol (Windows: `kernel32!WriteFile`/`ExitProcess`, needing the
   [[feature-port-windows-pe]] IAT), not a `syscall`. So the flag threads into `emit.inc`,
   not only `lib/rtl`.
3. **Bypass modules (out of THIS ticket's primitive set — flag separately).**
   `lib/rtl/palthread.pas`, `palsync.pas`, `baseunix.pas:122`, `random.pas:225` call
   `__pxxrawsyscall` directly (clone/futex/mmap/getrandom/termios), bypassing pxxcio.
   These are a per-OS **model** port, not a lowering flip (futex ≠ Win events), and are
   deferred — Windows single-threaded first (see [[feature-port-windows-pe]]).

The "zero `syscall` instructions" acceptance grep below already implies #2; this note
just names *where* so the implementer patches `emit.inc` and doesn't stop at `lib/rtl`.

## Acceptance

- With libc-call mode on for a Linux host (proving the mode against a known-good
  kernel *before* trusting it on a new OS), a hello-world + a heap/string/exception
  torture test produce **byte-identical program OUTPUT** to the raw-syscall build.
- The emitted binary contains **zero `syscall` instructions** (all kernel access via
  libc PLT) — verify with a disassembly grep. This is the property that makes
  [[feature-port-openbsd-libc]] compliant with `pinsyscalls` by construction.
- Gate: `make test` + self-host byte-identical (raw-syscall mode is the default and
  must stay bit-for-bit unchanged — libc mode is opt-in behind the flag).

## 2026-08-17 (frank2, Track A) — PARKED after landing the acceptance instrument. No compiler changes in the tree.

Stopped deliberately at a green point rather than pushing a codegen change
through overnight. **Nothing is half-applied**: the only thing landed is a new
tool, so `master` is clean and the self-host gate is untouched.

### The acceptance criterion as written cannot fail — fixed first

> *"The emitted binary contains zero `syscall` instructions — verify with a
> disassembly grep."*

The obvious spelling of that is:

    objdump -d <binary> | grep -c syscall

and it prints **0 for every pxx binary ever built**, including one making 57 raw
syscalls. pxx writes ELFs with **program headers only and no section headers**,
and `objdump -d` disassembles *sections*. It does not error or produce visibly
empty output — it prints a three-line header and a zero.

So this ticket's acceptance test would have passed on day one and kept passing
no matter what the compiler did. Caught only because I checked whether the
instrument could distinguish a raw build from a libc one *before* trusting it —
today's recurring lesson arriving a fourth time.

**Landed `tools/syscall_scan.py`**: reads the program headers directly,
disassembles each executable `PT_LOAD` as raw bytes at its true vaddr, counts
the kernel-entry mnemonic for the ELF's own `e_machine`, and **refuses to report
a count it could not measure** (no exec segment, unknown machine, empty
disassembly are all errors, never 0). Per-arch mnemonics, because the
instruction is only spelled `syscall` on x86-64 — grepping that word alone
reports a clean zero on every cross target, the same silent pass one level down.

Measured baselines to work against:

| binary | kernel-entry instructions |
| --- | ---: |
| pxx hello-world (`WriteLn`) | **57** |
| pxx + one `external 'libc.so.6'` call | 55 |
| `/bin/true` (ordinary libc-linked binary) | **0** |

`/bin/true` at 0 is the control worth keeping: it is the target state, and it
proves the tool does not simply always find syscalls.

### Sizing — what is and is not ready

**Already works, measured:** a Pascal program can call libc through the PLT
today with no compiler change at all —

```pascal
function libc_write(fd: Integer; buf: Pointer; n: PtrUInt): PtrInt;
  cdecl; external 'libc.so.6' name 'write';
```

compiles, links, and runs. So the import machinery this ticket assumed is
genuinely present and does not need building.

**The real chokepoint is narrower and better than the ticket's plan.** All 62
`__pxxrawsyscall` call sites across 11 RTL units funnel through ONE intrinsic →
`AN_SYSCALL` → **`IR_SYSCALL`, a single IR op with an arg chain**
(`ir.inc:6107`). Lowering *that* to a libc call covers every RTL primitive at
once **without touching `lib/rtl` at all** — which is strictly better than the
ticket's per-primitive mapping and much smaller.

Suggested shape for whoever continues, not yet implemented:

- lower `IR_SYSCALL` in libc mode to a call of libc's `syscall(3)` — the
  signature is a 1:1 match (`long syscall(long nr, ...)`);
- **keep the raw error convention** by mapping libc's `-1`/`errno` back to
  `-errno` at that one site. Then no RTL error check changes, and program output
  is byte-identical by construction rather than by inspection;
- `emit.inc`'s `_start` stub (`EmitwriteSyscall`, `SYS_EXIT_GROUP` at `:225`)
  is the separate half the ticket already flags, and is what stands between 55
  and 0.

**The unsized piece, and why I stopped:** in libc mode the compiler must emit
PLT imports for `syscall` (and `__errno_location`) that **no Pascal `external`
declared**, i.e. synthesise a dynamic import from codegen. I could not size that
confidently tonight, and it is `emit.inc`/`elfwriter.inc` — Track A's most
gate-sensitive ground, with the self-host fixedpoint riding on it. Guessing at
it overnight is exactly the trade this ticket's own "land incrementally, never a
long-lived branch" note warns against.

### Also worth correcting in this ticket

The `--platform=` axis already exists (`PLATFORM_POSIX` / `PLATFORM_ESP`,
`compiler.pas:365`), so the switch is a new value on an existing axis, not a new
flag mechanism.

### Note on file ownership

`tools/syscall_scan.py` is new and is not in Track T's named set
(`testmgr.py`, `twatch*`, `fuzz.sh`, `pasmith*`, `tstate/**`) — it sits beside
the other general probes like `gcc_diff_probe.sh`. Flagged rather than assumed.

## Notes

- **This does not replace raw syscalls.** Linux and FreeBSD stay raw-syscall (their ABI
  rewards it, keeps the libc-free identity). libc mode is for the OSes that mandate it.
- Land incrementally behind the flag; never a long-lived branch (same discipline as the
  experimental frontends).

## 2026-08-30 (frankA) — re-claimed; exposure measured, the unsized piece sized, and the design proven from Pascal before any compiler change

### File exposure — it does NOT reach `ir.inc`

Measured because the parked note points at `ir.inc:6107` and `ir.inc` is held by
another lane. `IR_SYSCALL` has **3** references in `ir.inc` and **none of them
matter here**: `:255` is the debug-name string, `:540` is an IR *validator* arm
(`IRRequireNode(IRA[i], 'syscall number arg')`), `:7220` is the AST→IR
*constructor*. All three concern the node's existence and shape; this ticket
changes only how it is **lowered**, which lives entirely at
**`ir_codegen.inc:4888`**. The grep count is 3 and the relevant count is 0 —
worth stating, because reporting the grep number would have sequenced this work
behind a lane it does not touch.

| file | exposure |
| --- | --- |
| `ir.inc` | **none** (3 refs, all irrelevant to lowering) |
| `ir_codegen.inc` | the lowering, ~4888 |
| `emit.inc` | the `_start` stub's raw syscall — increment 2 |
| `elfwriter.inc` | see below: probably nothing |
| `defs.inc` / `compiler.pas` | the mode flag |

### The "unsized piece" is smaller than it looked

frank2 parked because *"the compiler must emit PLT imports for `syscall` and
`__errno_location` that no Pascal `external` declared, i.e. synthesise a dynamic
import from codegen"*, and could not size it. Traced: the import tables are
driven entirely by **`ExternalProc[]` / `ProcLibrary[]`**, populated by ordinary
`Procs[]` entries carrying `ProcExternal := True`, `ProcLibrary := InternStr(lib)`,
`ProcExtName := InternStr(sym)` (`pasparser_proc.inc:1325`), with
`RegisterExternal(procIdx)` (`symtab.inc:11711`) handing out the GOT/PLT slot at
call-emission time. So synthesising an import is **manufacturing one `Procs[]`
entry and reusing the existing external-call emitter** — not new `elfwriter`
machinery. `elfwriter.inc` may need no change at all.

### The design is proven end-to-end from Pascal, with no compiler change

Rather than reason about the ABI, the whole lowering was written as ordinary
Pascal `external` declarations and run:

```pascal
function c_syscall(nr, a0, a1, a2: PtrInt): PtrInt; cdecl;
  external 'libc.so.6' name 'syscall';
function c_errno_loc: Pointer; cdecl;
  external 'libc.so.6' name '__errno_location';
```

| call | result |
| --- | --- |
| `c_syscall(1, 1, @s[1], Length(s))` | wrote `via libc syscall`, returned **17** = the byte count |
| `c_syscall(1, -7, ...)` (bad fd) | returned **-1**, `errno` = **9** (EBADF), so `-errno` = **-9** |

Both halves confirmed:

1. **The register mapping is a shift, not a remap.** libc's `long syscall(long
   nr, ...)` takes the number as its FIRST C argument, so the raw convention
   (nr in rax; args in rdi, rsi, rdx, r10, r8, r9) becomes the SysV C
   convention by moving every argument one place right. No per-primitive table.
2. **The error convention maps at one site.** Raw returns `-errno`; libc returns
   `-1` and sets `errno`. `if result = -1 then result := -errno` at the single
   lowering site reproduces the raw convention exactly, so **no RTL error check
   changes and program output is byte-identical by construction** rather than by
   inspection — which is what makes the acceptance criterion structural.

### The inherited instrument re-verified, and its baselines have moved

`tools/syscall_scan.py` is what every acceptance claim here rests on, and it was
written by a session that is gone with its own bug-fix story attached, so its
numbers were re-established rather than assumed:

| binary | frank2, 2026-08-17 | measured now |
| --- | ---: | ---: |
| pxx hello-world | 57 | **73** |
| `/bin/true` (control) | 0 | **0** |

The 57 → 73 drift is the RTL growing over two weeks, not a tool fault. Two
properties re-checked directly, because they are the ones being relied on:

- **It refuses rather than reporting 0** — a non-ELF file and a `.pas` file both
  produce `not an ELF file`, never a count.
- **It disassembles rather than byte-greps.** Independent cross-check: a naive
  `0f05` byte count over the whole file gives **73** for the pxx binary (agreeing)
  but **1** for `/bin/true`, where the tool correctly reports **0**. It is
  rejecting a byte pair that is not an instruction, which is exactly the
  discrimination a grep cannot make and the reason the original `objdump`
  criterion was vacuous.

### Plan

1. **Increment 1** — mode flag + lower `IR_SYSCALL` to the synthetic `syscall`
   import with the errno fixup, x86-64 only. Expected effect: 73 → a small
   non-zero (the `_start` stub remains).
2. **Increment 2** — `emit.inc`'s `_start` stub, which is what stands between
   that residue and 0.

Raw-syscall stays the default and must stay bit-identical; libc mode is opt-in.

## Increment 1 landed — `IR_SYSCALL` lowers to libc, and a scope correction

`--rtl-libc` (opt-in, x86-64) lowers `IR_SYSCALL` to libc's `syscall(3)` with the
errno mapping. Four small pieces, no `elfwriter.inc` change, no `lib/rtl` change:

- `defs.inc` — the mode flag and two synthetic proc-index caches
- `compiler.pas` — `--rtl-libc`
- `symtab.inc` — `EnsureLibcSyscallProcs`, which manufactures the two imports as
  ordinary external `Procs[]` entries (this is all an import IS here; the
  existing `RegisterExternal` path then emits DT_NEEDED and the PLT slot)
- `ir_codegen.inc` — the lowering plus two alignment helpers

### Measured

| program | raw | `--rtl-libc` | output |
| --- | ---: | ---: | --- |
| hello-world | 73 | 67 | identical |
| file I/O + heap + string growth + exceptions | 195 | **105** | **byte-identical** |

And the property that matters most: **raw-mode output is byte-identical to the
pinned v394 binary** (`53800fbeb0b66e11`) for both programs. The default path is
untouched, which is the condition this ticket has to meet before anything else
about it is interesting.

### Scope correction: the switch reaches FOUR files, not two

The ticket's 2026-07-21 scout note says raw `syscall` lives in **two** places —
RTL primitives (via the intrinsic) and the `_start` stub. Measured, that is
incomplete: the compiler ALSO emits the raw instruction directly through
`EmitSyscall` (`emit.inc:193`) at **42 call sites**:

| file | `EmitSyscall` call sites |
| --- | ---: |
| `ir_codegen.inc` | 19 |
| `symtab.inc` | 13 |
| `exception_emit.inc` | 6 |
| `emit.inc` | 4 |

That is why hello-world only moved 73 → 67: the RTL's 61 intrinsic sites funnel
through `IR_SYSCALL` and are now lowered, but the compiler's own builtin/runtime
emissions do not go through the IR at all. It is also why the heavier program
moved much further — more of its kernel traffic comes through the RTL.

### Increment 2 is smaller than that table suggests

`EmitSyscall` is a **single choke point**, and its callers set up the *raw*
convention (rax = nr, then rdi/rsi/rdx/r10/r8/r9). So all 42 sites convert at
once by doing the conversion inside `EmitSyscall` — a register rotation into the
SysV slots (`r11 <- r9`, `r9 <- r8`, `r8 <- r10`, `rcx <- rdx`, `rdx <- rsi`,
`rsi <- rdi`, `rdi <- rax`, in that order, which has no read-after-write
conflict) followed by the same aligned call. **No caller changes.** Doing it
there rather than duplicating the lowering is the `normalise-dont-special-case`
answer, and it would let increment 1's `IR_SYSCALL` arm collapse back into the
raw pops plus one `EmitSyscall`.

**The hazard to settle first, and it is a real one.** The raw `syscall`
instruction clobbers only `rax`, `rcx` and `r11`; a C call clobbers every
caller-saved register. Any `EmitSyscall` caller that sets up an argument
register once and issues two syscalls, or that relies on `rdi`/`rsi`/`rdx`/
`r8`/`r9`/`r10` surviving, breaks silently under the libc path. The conservative
fix is to push/pop the six raw-convention registers around the call inside
`EmitSyscall`, preserving the raw contract exactly at ~12 extra instructions per
syscall — acceptable for a portability mode. **Whether any of the 42 callers
actually depends on that is unmeasured**, and it should be measured rather than
assumed in either direction before increment 2 lands.

## Increment 2 attempted, reverted, and it found a latent compiler bug

The plan was right and the implementation worked: convert at `EmitSyscall`'s
single choke point so all 43 sites lower at once with no caller change, with the
six raw-convention registers pushed/popped around the C call so the raw contract
is preserved exactly and no caller audit is needed.

It measured beautifully and was still wrong:

| program | raw | increment 1 | increment 2 |
| --- | ---: | ---: | ---: |
| hello-world | 73 | 67 | **9** |
| file I/O + heap + string + exceptions | 195 | 105 | **9** |

...and the second program **segfaulted**. Reverted; increment 1 (`b778c6078`)
stands and is unaffected.

### The cause is not in this ticket's work

Growing `EmitSyscall` from **2 bytes to ~140** overflowed unrelated `rel8` jump
patches that span a syscall. Filed separately as
[[bug-a-a-rel8-jump-patch-truncates-silently-when-its-span-grows]] [A p55],
measured to the byte: a `jns` at `0x41115e` with displacement **-75** against an
intended forward span of **181** (`181 - 256 = -75`), landing mid-instruction at
`0x411115`.

**Two wrong guesses are recorded here on purpose**, because both were plausible
and both cost a rebuild:

1. *"The pushes clobber the 128-byte red zone."* Adding `sub rsp,128` /
   `add rsp,128` around the sequence changed nothing. Wrong.
2. *"The C call destroyed `rbp`."* A breakpoint at the sequence entry showed
   **`rbp` was already nil on arrival** — the sequence never touched it. Wrong,
   and it was the measurement that killed it rather than more reading.

What actually identified it was noticing that `rip` was **mid-instruction**,
which no linear execution can produce, and then *scanning the executable segment
for any rel8 jump targeting that address* — one hit, and its displacement
matched the truncation arithmetic exactly.

### What increment 2 must do instead

**Emit a `call` to one shared out-of-line thunk.** `EmitSyscall` then emits ~5
bytes instead of ~140, so every rel8 span is essentially unchanged and the
landmine is not tripped. The thunk holds the register shift, the aligned call,
the errno mapping and the save/restore, emitted **once** — which also removes the
code-size cost of inlining ~140 bytes at 43 sites.

This is strictly better than what was reverted, and it does not depend on the
rel8 bug being fixed first. It still writes no call site: `EmitSyscall`'s body
and one new thunk emitter, exactly the disjointness the `ir_codegen.inc` grant
rests on.

### The one open question in the thunk design: WHERE to emit it

The thunk itself is settled — the reverted sequence's body, ending in `ret`,
emitted once, with `EmitSyscall` reduced to a 5-byte `call rel32`. What is not
settled is placement, and it is the only reason increment 2 is not landed:

**`EmitSyscall` fires mid-emission**, in the middle of a routine's code, so the
thunk cannot simply be emitted where it is first needed — execution would fall
straight into it. The repo's existing lazy-stub pattern
(`EnableCoroutineRuntime` → `EmitCoroutineRuntime`, `coroutine_emit.inc:23`)
works because it is triggered from a **parse** point, which is always a boundary
between routines. There is no equivalent boundary available inside
`EmitSyscall`.

Three candidate placements, none yet validated:

1. **Lazy, with a `jmp` over the body at first use.** Self-contained, but the
   first site still emits ~140 bytes inline — and if that first site happens to
   be one of the ~30 that a `rel8` patch spans, it trips
   [[bug-a-a-rel8-jump-patch-truncates-silently-when-its-span-grows]] exactly as
   the reverted attempt did. It trades a certain failure for a positional one,
   which is worse, not better, because it would pass on some programs.
2. **Eager, at the earliest code-emission point when the flag is set.** Correct
   by construction, but it needs the program-entry convention to be understood
   first: if the ELF entry is code offset 0, the thunk must be jumped over and
   the entry stays put. Worth confirming against `elfwriter.inc` rather than
   assumed.
3. **Alongside the other runtime stubs**, via a new `EnableLibcSyscallRuntime`
   invoked once from the same parse-time place the coroutine/exception runtimes
   are enabled. Most idiomatic; needs a call site that is guaranteed to run
   before any `EmitSyscall`, which is the part to verify.

**(3) is the most likely answer and (2) is the fallback.** Whoever continues
should settle the placement question FIRST, on its own, before writing the
thunk body — the body is already written and measured in the reverted attempt
and can be lifted from this ticket's history.

Related caution for whoever does it: b4 reports `InternStr` now writes a 24-byte
header at **negative offsets** from `Strs[].Offset` and the entry is 8-aligned
before that write, so anything that reorders or re-bases **data** emission near
`_start` must preserve both. The thunk is code, not data, so this should not
apply — but placement work near program entry is exactly where it would.

## Increment 2 LANDED — `951818104`, one thunk, all 43 sites

Placement question from the entry above is answered: **`compiler.pas`, just
before the ELF writer dispatch.** All code is emitted, `CodeLen` is final, and
the writer derives `dataBase` from it — so the thunk can be appended there and
the recorded rel32 call sites patched with the existing `Patch32`. None of the
three candidates listed above was right; the finalisation point is better than
all of them, and it made the "lazy jmp-over" candidate's positional-failure
hazard moot.

| program | raw | increment 1 | increment 2 |
| --- | ---: | ---: | ---: |
| hello-world | 73 | 67 | **9** |
| file I/O + heap + string + exceptions | 195 | 105 | **9** |

Code size, libc vs raw, `t.pas`: **302,952 vs 302,262 — +690 bytes.** With both
lowerings live it was +7,050, so collapsing `IR_SYSCALL` back into `EmitSyscall`
paid for itself an order of magnitude over.

**Verified, and the verdict never rested on the count.** Default raw-mode output
byte-identical to pinned v394 for both programs; libc-mode output identical to
raw across 9 programs, including the five that crashed under the inline version;
`-O0`/`-O1`/`-O2` all correct. The broken inline build ALSO reported 9, which is
the whole reason each run asserts the program's own output as well.

### Two limits, both loud rather than silent

- **`-O3` is refused with a diagnostic.** `EmitExternalIndirectCall` wraps the
  call in `FloatPoolSave`/`Restore`, which address `[rbp + FxSaveBase]`, and
  `FxSaveBase` is **per function**. In a shared thunk `rbp` belongs to whichever
  caller jumped in, so those stores would land in that caller's frame at another
  function's offset. Lifting the limit means saving the pool at the call site
  instead of in the thunk.
- **The internal branch is rel32, not rel8.** With the float-pool save/restore
  around both calls the span reaches ~143 bytes — the exact overflow this ticket
  tripped once already. This is also the shape the fix for
  [[bug-a-a-rel8-jump-patch-truncates-silently-when-its-span-grows]] should take.

### One fix that works and is NOT explained

Registering the two synthetic imports lazily — at thunk emission, after every
unit's externals — produced a `DT_NEEDED` naming a **unit** (`builtinheap`)
rather than `libc.so.6`, and the program failed at **load**, not at run.
Registering them before the frontend runs fixes it completely.

**The mechanism is not established.** The obvious theory — a parallel array not
grown alongside `Procs[]` — is **wrong**: `EnsureProcCapacity` does grow
`ProcLibrary`. Recorded as unexplained rather than given a plausible story,
because a wrong mechanism in a ticket is worse than an admitted gap. Early
registration is correct by design regardless (an import should exist before the
frontend runs, exactly as a source-level `external` would), so the fix is not
merely empirical even though the failure is unexplained. **If anyone touches
external registration order, this is a latent trap: it fails at LOAD with a
plausible-looking library name, not at compile time.**

## Increment 3 — done (`3a0ed43fb`), and its own scope was wrong twice

Landed. Residual kernel entries **73 → 1**, the one remaining being deliberate
(below). The paragraph this section replaces was wrong in both of its claims,
and how it was wrong is the useful part.

### The scope was built from one idiom, and a grep is one idiom

It said "the residual 9 are the `_start` stub plus `thread_emit.inc` ×3,
`asmfront.inc`, and the frontend sites". Every element of that is false:

- **Not the `_start` stub.** Disassembling the nine showed one
  `arch_prctl(ARCH_SET_GS)` TLS install (`EmitTlsMainInstall`, ir_codegen.inc:928)
  and eight in the signal/fault runtime — `sigaltstack`(131), `rt_sigaction`(13)×2,
  `rt_sigreturn`(15), and the reporter's `write`/`getpid`(39)/`kill`(62)/
  `exit_group`(231). `EmitProgramEntryForTarget` contributes none of them.
- **Not `thread_emit.inc`.** Its stub is emitted only when a program clones;
  a hello-world has none.
- **Nine is not the emitter population, it is one binary's reachable subset.**
  The real population is the **17** `EmitAsmX64([… 'syscall' …])` sites in
  `ir_codegen.inc` alone — kernel entries written as a *mnemonic string*, which
  the grep for `EmitB($0F); EmitB($05)` cannot match. A program using threads,
  fork/exec or more signals pulls in more of them.

The tell was site 1 resolving to `ir_codegen.inc:928` — **a line the enumeration
said did not exist**. The defence generalises: *enumerate from the artefact, not
from the source.* The binary contains every site by construction; a grep contains
every site that matches one spelling.

### The seam, and an exclusion that came free

All 17 funnel through `asmtext.inc:389` → `x64_syscall` (`x64enc.inc:164`), so
the conversion is **one function**, not 17 call sites. User-written inline
`asm … syscall … end` cannot be caught by it: `asmfront.inc` has zero
`EmitAsmX64` uses and reaches `lib/asmcore`'s `AsmEncodeX64` instead. Two
encoders, already separate — the guard this looked like it needed does not exist
because the separation is structural.

`EncB` is dual-mode (`EncToAsmBuffer` → `AsmB` staging, else `EmitB` direct).
The staged path is IR_ASM replay, where `CodeLen` is *not* the instruction's
address, so rerouting must be conditioned on direct mode for correctness — and
that is the same condition policy wants. One condition, two reasons.

### `rt_sigreturn` must stay raw — and this nearly shipped

It takes no arguments and restores the **entire context** from a signal frame at
a **fixed offset from rsp**. The thunk's return address plus six register pushes
move that frame out from under the kernel. Measured: a libc-mode program sent
SIGTERM died with **SIGSEGV (139)** where the default build exits **143**.

Now emitted through a new **`syscall_raw`** mnemonic that never becomes a call,
on any flag. `clone`'s child-stack stub in `thread_emit.inc` is raw for the same
reason — previously true by omission, now true by statement. Anything rsp-relative
or non-returning belongs on `syscall_raw`.

**The near-miss is the reportable part.** Before the signal test this change
showed: syscall count **0**, `hello` correct, div0 identical to default,
self-host converged, and default codegen byte-identical to `pinned`. Six green
signals over a build that segfaults on the first signal it receives. A metric is
never the verdict, and a *perfect* metric is the most persuasive wrong one — the
zero was the thing that made it look finished.

### Verified at `222370c819c9`

| check | result |
| --- | --- |
| self-host fixedpoint | converged after 1 round |
| default codegen vs `pinned` **compiler's output** | byte-identical |
| libc hello | `hello`, rc=0; real `write`/`exit_group` via libc under strace |
| libc div0 | rc=200, message identical to default |
| libc SIGTERM | rc=143 = default (was **139** before `syscall_raw`) |
| residual kernel entries | 73 → **1** = the rt_sigreturn restorer, at the address the kernel is handed as `sa_restorer` |

The second row is the one self-host cannot give: a uniformly-wrong compiler
reproduces itself perfectly, so comparing *emitted programs* against the pinned
binary is the disjoint oracle. (b4 hit the same blind spot the same day from the
other side — `dataBase := AlignTo(dataBase, 4096)` would desync vaddr from file
offset and sail through a fixedpoint.)

### What is left, honestly

Not "done to zero", and it should not be. Still raw, by design: `rt_sigreturn`;
`thread_emit.inc`'s clone stub; user inline asm.

**Tested population, after deliberately widening it** — the first scope line here
said "hello / div0 / signal only" and was too pessimistic, which I found by
running the tests rather than by reasoning:

| program | default | `--rtl-libc` |
| --- | --- | --- |
| hello | `hello`, rc=0 | identical |
| div0 stub | rc=200 + message | identical |
| SIGTERM delivery | rc=143 | identical |
| `test_multithreading.pas` | passes | **passes** |
| `test_io_checks_iplus.pas` (failing I/O → errno) | `ioresult=TRUE caught=1` | identical |

The last two matter most: threads exercise the raw `clone` stub alongside
thunked syscalls, and the I/O test exercises the thunk's **errno fixup**, which
is its most delicate part. Both were in the "untested" bucket an hour ago.

(`test_palthread.pas` fails to compile in **both** modes — pre-existing, not a
libc-mode regression. Noted so the next reader does not re-derive it.)

**Still unconverted:** the frontend sites (`cparser`/`eparser`/`rparser`/
`zparser`). No Pascal program reaches them.

### A latent hazard, reasoned but NOT observed

The `clone` child stub is raw, so a pxx-created thread **inherits the parent's
FS base**. The thunk's errno fixup calls libc's `__errno_location`, which is
FS-relative — so on a pxx thread it resolves to the **main thread's** errno slot.
Within one thread this is invisible (the write succeeds to a valid address and
the read-back is correct); the symptom is a worker's failing syscall silently
overwriting *another* thread's errno.

`test_multithreading.pas` passes, and does not refute this: its syscalls
succeed, so the fixup never fires. **The trigger is a FAILING syscall on a
pxx-created thread**, which nothing tested reaches.

Recorded as a prediction with its exact trigger, not as a bug — it is reasoned
and unobserved, and the counterpart to this ticket's other unexplained item is
the discipline that a story without a measurement does not get written down as
a mechanism. Whoever converts the frontend sites should build that test first.

Track B's `InternStr` caution still applies to any future work that reorders
data emission: the static managed-string header lives at **negative** offsets
from `Strs[].Offset`, 24 bytes are written into `Data[]` before the offset is
recorded, and the entry is 8-aligned before that write.

## Log
- 2026-08-30 — resolved, commit b989b849c.
