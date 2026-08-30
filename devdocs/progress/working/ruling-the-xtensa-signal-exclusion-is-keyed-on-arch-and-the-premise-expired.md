---
slug: ruling-the-xtensa-signal-exclusion-is-keyed-on-arch-and-the-premise-expired
track: A+S
prio: 55
type: ruling
status: working
found: 2026-08-30
owner: frankS
---

# RULING: reversing the xtensa signal-runtime exclusion is DERIVABLE, not a Track U fork

frankS filed `feature-a-a-signal-runtime-for-HOSTED-xtensa-the-exclusion-predates-the-profile`
and correctly declined to reverse a **recorded deliberate decision** on its own authority,
asking whether that call is mine or Track U's.

**It is neither a guess nor a fork. It derives, and I am ruling it rather than escalating**
— rule 1 of the coordinator's operating rules: escalating a question the code already
answers spends the same scarce resource as guessing at one it does not.

## The derivation, in full, so it can be disputed on its steps

1. `EmitSignalRuntimeForTarget` falls through for xtensa on purpose, with the reason
   recorded twice: *"FreeRTOS is not a Unix and has no signal runtime at all."*
2. **That sentence reasons from ARCH to PLATFORM.** It was written when the two were the
   same thing for xtensa, and the hosted profile made them different. Under
   `--platform=posix` an xtensa binary is an ELF running on Linux under qemu, with
   `rt_sigaction` at 226. The premise is not wrong; it **expired**.
3. **The tree already contains the resolution for the identical situation.** riscv32 is
   both an ESP target and a hosted one, and it gates on the platform — `if not EspBareBoot
   then` — never on the arch. So there is a model, in-tree, tested, that this can copy.
4. **The ESP position is untouched.** CLAUDE.md's Track S rule is *"ESP is not a Unix —
   FreeRTOS gives tasks, not processes — so 33 PAL entry points are refused even under
   IDF."* That is a statement about the **ESP platform**, and a `not EspBareBoot` gate
   preserves it exactly. Hosted xtensa under `--platform=posix` is not ESP, and nothing in
   the refusal set moves.

So this is not "reverse a design decision". It is **a refusal keyed on the wrong axis** —
the same shape as a comment asserting an invariant its implementation lacks, one level up:
a *guard* whose predicate tests arch when the property it protects is platform. Fixing the
axis is not a reversal of the original judgment; it is what the original judgment already
means now that the two axes have separated.

**If anyone disputes a step above, THEN it is a U ticket** — dispute the derivation, not
the conclusion, and name the step.

## Authorized in principle; NOT dispatched yet, and the reason is file contention

frankS priced it honestly and its estimate is the binding constraint, not the decision:
`EmitSignalRuntimeXtensa` (riscv32's equivalent is ~155 lines of hand-encoded stub), the
dispatcher arm in `ir_codegen.inc`, the refusal in `pasparser_expr.inc`, and
`EmitDefaultSignalInstallForTarget`. **Three shared Track A/P files, a session of work.**

`pasparser_expr.inc` is a Track P file and frankA is working the `pasparser_*` set right
now. Dispatching this on top of that is the collision the letters exist to prevent — and I
nearly caused one tonight by answering a file-ownership question from state I had not
refreshed. **The slot opens when the P files are free**, with a proper scoped grant naming
all four files, not before.

## Why it is worth doing rather than shelving for being big

It is worth **more** than the ticket it grew out of, which is the argument for doing it:
the three `SA_SIGINFO` refusals are gated on the same fact — `pasparser_expr.inc` refuses
on `TargetArch = TARGET_XTENSA` because the runtime does not install `SA_SIGINFO`, and
every other hosted target does. **One runtime closes four programs and collapses two of the
seven tail categories into one ticket.** That is the root-cause-over-microfix trade in its
favourable direction: fewer cases, not more.

frankS also recorded that it has **not verified past the compile gate** — nothing can run
until the runtime exists, so a second blocker behind this one is possible. That caveat is
load-bearing and must survive into whoever takes it.

## The trap named in the ticket, repeated here because it is the dangerous kind

`test_signal_default_revert_b336` matches on hosted xtensa today and is wired into
`test-xtensa`. **It installs no handler** — it raises SIGTERM with the default disposition
and dies 143, which needs `kill`, not the signal runtime. So it is **a green row in the
signal family that is not evidence any of the signal family works**, and it is already in
the suite. frankS flagged it against its own just-landed work, which is the direction that
almost never happens.

## Addendum 2026-08-30 (frankS): THE FILE LIST IS MISSING ONE, and it is in a third lane

Measured, not reviewed: `grep -rn "not a Unix\|FreeRTOS" compiler/*.inc`.

The ruling names `EmitSignalRuntimeXtensa`, `ir_codegen.inc`,
`pasparser_expr.inc` and `EmitDefaultSignalInstallForTarget`. There is a **fifth
site**, carrying the refusal and its justifying comment **verbatim**:

| file | line | guard |
| --- | --- | --- |
| `compiler/pasparser_expr.inc` | 4382 | `if TargetArch = TARGET_XTENSA then Error(...)` |
| `compiler/pyparser.inc` | 45973 | `if TargetArch = TARGET_XTENSA then Error(...)` |

Same comment in both, down to the wording: *"Every hosted Linux target now
installs with SA_SIGINFO; only xtensa/ESP is left out, and deliberately —
FreeRTOS is not a Unix and has no signal runtime at all."*

**Why the duplicate is correct and still a hazard.** Per
`the-substrate-is-ast-and-ir-not-the-parser`, each frontend owns its own parser
and its own refusals — so two copies is the intended design, not drift. The
hazard is the ordinary one: *fix one arm, grep for the sibling*. A session that
implements the runtime and updates only the Pascal site leaves **NilPy programs
on hosted xtensa still refused**, by a comment whose premise the same commit just
retired. Silent, and only reachable by someone writing NilPy for hosted xtensa.

**It changes the contention analysis, which is what the ruling gates on.**
`pyparser.inc` is Track **N**, carved out and disjoint from the `pasparser_*`
set frankA holds — so this widens the grant by one file without widening the
collision surface. The blocking constraint stays exactly what the ruling says it
is: the P files.

## The mechanism behind this ruling generalises, and it has already been seen once tonight

The ruling's step 2 is the whole finding: *"that sentence reasons from ARCH to
PLATFORM. It was written when the two were the same thing for xtensa, and the
hosted profile made them different."*

That is not one comment. **The hosted xtensa profile separated two axes that had
always been one, and every claim written before it that used "xtensa" to mean
"ESP/FreeRTOS" expired at that moment without being edited.** A second instance
was found and falsified independently the same night, in `test-xtensa`:

> *"no runner: windowed images link through xtensa-esp-elf-gcc"*

— the stated reason there is no executed windowed row. Hosted windowed programs
run today under plain `tools/run_target.sh xtensa`
([[bug-a-the-xtensa-windowed-abi-is-compiled-twice-and-executed-never]]).

Two instances, different files, different lanes, neither noticed at the time.
The cheap sweep for the rest is the grep above plus `EspBareBoot` (26 sites) vs
`TargetArch = TARGET_XTENSA` — the first is the correct axis and riscv32's model,
the second is the one that expires. **This addendum does not claim the remaining
sites are wrong**; several arch checks are genuinely about the instruction set.
It claims only that the axis is worth checking per site, and that nothing has.

## Addendum 2 (frankS, 2026-08-30): the NilPy site is corrected, and the AXIS DID NOT MOVE

Under `grant-pyparser-xtensa-refusal-site-to-franks` [N p50], `pyparser.inc`'s
copy of the refusal now states the live reason instead of the expired one. **The
guard is unchanged**, and that is deliberate — it is the one thing about this
ruling that is easy to get backwards.

Step 2 of the derivation is right: the comment reasons arch→platform and expired
when the profile split those axes. But re-keying the guard on `not EspBareBoot`
**today**, ahead of the runtime, does not correct a wrong axis — it opens a hole.
`EmitSignalRuntimeForTarget` has **no xtensa arm at all** (measured: x86-64,
aarch64, arm32, i386 unconditional; riscv32 gated `not EspBareBoot`; xtensa
absent), so hosted xtensa has no handler either. Flipping the axis first would
accept `__pxxSig*` on hosted xtensa and answer out of a handler that was never
installed — a plausible wrong value in code that dispatches on it, which is what
the refusal exists to prevent.

**So the axis moves in the same commit as `EmitSignalRuntimeXtensa`, in all five
sites at once, and not before.** Whoever takes the runtime inherits both parser
sites as part of it; `pasparser_expr.inc` is untouched here because it is
frankA's file and the contention this ruling gates on is exactly that.

The generalisation is worth keeping separate from this ticket: **an expired
premise does not imply the guard it justifies is wrong.** Here the true reason
was *broader* than the stated one, so the stale comment was hiding a refusal that
is correct on both platforms rather than one that is wrong on one. The cheap
check is the one above — ask what the guard protects and whether it exists yet,
not just whether the sentence beside it still parses.

## Addendum 3 (frankS, 2026-08-30): re-ran the evidence at HEAD before building. The PREMISE holds; the FILE LIST and the CONTENTION GATE do not.

Dispatched by the coordinator with the instruction to re-run this ticket's own
evidence first, on the reasoning that **a ticket whose subject is an expired
premise is the most likely kind to have had its own premise expire while it sat.**
All measurements below at **HEAD = 5e6230ebc**, clean tree.

### 1. The central claim SURVIVES its re-check — do not flip the axis yet

Addendum 2's measurement is still true at HEAD. `EmitSignalRuntimeForTarget`
(`ir_codegen.inc:812`) dispatches x86-64 / aarch64 / arm32 / i386 unconditionally,
riscv32 under `if not EspBareBoot then`, and **has no xtensa arm at all**.
`EmitDefaultSignalInstallForTarget` (`:830`) likewise: five per-arch install
blocks, no xtensa. So the refusal is still protecting a runtime that does not
exist, on both platforms, and re-keying it on `not EspBareBoot` ahead of
`EmitSignalRuntimeXtensa` would still open the hole addendum 2 describes.

This is the outcome the dispatch was hoping to rule out and it did not happen:
**no close-on-evidence is available.** The ruling stands as written.

The port model also holds — `EmitSignalRuntimeRISCV32` measures **156 lines**
(`ir_codegen_riscv32.inc:47`), against the ruling's estimate of ~155.

### 2. The contention gate HAS expired, and it names the wrong file

The ruling gates dispatch on one sentence: *"The slot opens when the P files are
free."* That was the binding constraint when written. It is not now.

Both shared-file edits this work requires are in **`ir_codegen.inc`** — the
dispatcher arm at `:812` and the default-install arm at `:830`. That file is
held **whole-file by frankA** for `EmitParamSpillsForTarget` (coordinator,
2026-08-30). `pasparser_expr.inc:4382` is still needed and still Track P, but it
is no longer the *binding* blocker; `ir_codegen.inc` is, and the ruling does not
mention it as contended ground at all.

Same species as the ruling's own finding, one level out: **a gate keyed on a file
set that stopped describing the collision.** The ruling did not get this wrong —
it expired, exactly as its own step 2 says premises do.

### 3. The file list misses TWO more sites, in a file nobody has named — and one of them is a MEASUREMENT, not an edit

Addendum 1 raised the count from four to five (`pyparser.inc`). Measured now:
`grep -n "unreachable: the parser refused" compiler/*.inc`.

| file | line | what |
| --- | --- | --- |
| `compiler/ir.inc` | 3953 | `UContextPCOffset` → `else Result := -1` |
| `compiler/ir.inc` | 3993 | `UContextSPOffset` → `else Result := -1` |

Both carry the sentinel comment *"unreachable: the parser refused this target
already"*, and the header at `:3945` carries the expired sentence a third time:
*"xtensa never reaches here — the parser refuses every `__pxxSig*` on it, because
FreeRTOS has no signal runtime at all."*

**These are not two more comment edits, and that is the finding.** The five live
entries in those tables were **measured by probe**, and the header says so in
terms that forbid the cheap route: a program was faulted two ways under each
target's qemu (by writing `$DEAD0000` and by calling it), every `ucontext` word
equal to the sentinel was dumped, and the answer cross-checked against the
kernel's struct definitions so two independent sources agree. i386's SP offset
could not be settled by the dump at all — `gregs[REG_ESP=7]` and
`gregs[REG_UESP=17]` hold the same value at fault time — and took a differential
to decide.

So hosted xtensa needs its own probe run for both offsets. **By this ticket's own
recorded standard they cannot be read off a header**, and that work is not in the
ruling's estimate.

**And the `-1` is a live wrong-value hazard the moment the guard moves.** Its
"unreachable" justification *is* the parser refusal that this work removes — so
the commit that lifts the refusal makes the sentinel reachable in the same
breath, and a handler would rewrite at offset `-1`. That is precisely the
plausible-wrong-value failure the refusal was protecting against, relocated
rather than removed. It is the same shape as addendum 2's finding and it lands on
the same commit boundary: **the offsets must be measured and filled in the same
change as the axis flip, or the flip is worse than the refusal.**

Revised scope: **seven sites, in five files, across three lanes (A / P / N), plus
one qemu probe run.** Ordering dependency worth stating because it may be
circular: dumping xtensa's `ucontext` needs a signal delivered to a handler, and
installing a handler is the runtime this ticket is building — so the probe may
not be runnable before `EmitSignalRuntimeXtensa` exists in some throwaway form.
Not yet established; flagged rather than assumed.

### 4. The trap named in the ruling has a counterpart that IS real evidence

The ruling warns that `test_signal_default_revert_b336` is a green row in the
signal family that proves nothing about the signal family (it installs no
handler; it dies 143 on the default disposition, which needs `kill`).

Its opposite exists and should be the acceptance check here: **`test_signal_sp_rewrite`
runs on all five targets** and is described as the guard that makes a wrong
`UContextSPOffset` entry *"fail loudly rather than quietly clobbering an unrelated
register."* A new xtensa row there is what would make item 3's measured offsets
trustworthy. Naming it now so the eventual landing is not gated on re-deriving
which test carries the property.

### Status: NOT blocked on a decision — blocked on one file, and the ask is with the coordinator

`ir_codegen_xtensa.inc` (the 156-line port target) is mine and clear.
`ir_codegen.inc` is frankA's. Per the coordinator's standing instruction I have
not taken it on my own read; sequencing request sent.

## Addendum 4 (frankS, 2026-08-30): the port's two biggest unknowns are MEASURED, and both came back favourable

Coordinator dispatched the `ir_codegen_xtensa.inc` port body (the file is mine and
clear; `ir_codegen.inc` stays frankA's and is untouched). Before writing 156 lines
of hand-encoded stub, two facts the port rests on and which nothing in the tree
answered. Both measured under `qemu-xtensa`, compiler binary **sha256 2f88481adc6b**,
self-host fixedpoint verified (`converged after 2 round(s)`) at **HEAD 6e20c989f**.

### 1. The ABI fork does not exist — Call0 is the DEFAULT, measured

`compiler.pas:862` initialises `XtensaABI := XTENSA_ABI_CALL0`; `:1142`/`:1147` are
the `--xtensa-abi=` overrides. So hosted xtensa is **Call0 unless asked otherwise**,
and a Call0-only signal runtime serves the default path rather than a corner of it.

That settles what looked like a design fork by measurement: the runtime follows
`TargetHasProcCleanupFrame`'s existing shape — **Call0 gets it, windowed keeps
refusing** — and the windowed question stays the separate S ticket it already is.
No Track U escalation needed.

### 2. The kernel DOES enter a plain Call0 Pascal proc as a handler — end to end

This was the real risk: xtensa Linux userland is conventionally windowed, and the
kernel's `setup_frame` is written for it. If a Call0 proc could not be entered, the
whole port would have needed a windowed spill preamble and the ticket would have
been a campaign rather than a session.

Probe (`scratchpad/xhandler.pas`, no compiler change): build a `struct sigaction` by
hand, install it through `__pxxrawsyscall(226, ...)`, fault by dereferencing nil, and
have the handler `Halt(7)` rather than return — so the ENTRY question is answered
without depending on the trampoline/restorer answer as well.

```
sigaction=0
faulting
HANDLER ENTERED
exit=7
```

Three facts fall out of that one run:

- **`rt_sigaction` on xtensa is 226**, confirmed by a working install and not merely
  by an errno signature. This corroborates the ruling's own step 2, which asserted
  226 — it was right, and is now measured rather than asserted.
- **The `struct sigaction` layout is riscv/arm64-shaped**: `{handler(0), flags(4),
  mask(8,12)}` with `sigsetsize = 8` and **no SA_RESTORER slot**. The riscv32 model's
  contract transfers; i386/arm32's does not.
- **Call0 entry works.** No windowed preamble, no register-spill dance.

### 3. How 226 was pinned, since the obvious probe is ambiguous

Worth recording because the first answer was wrong-looking and the second
discriminator is the reusable part. Scanning 0..459 for the sigsetsize signature
(`size=8 -> 0`, `size=7 -> -EINVAL`) returns **two** numbers, 226 and 227:
`rt_sigprocmask` validates a sigsetsize too.

The separator is the FIRST argument. With a nil `set`, `rt_sigprocmask` ignores
`how` entirely, while `rt_sigaction` always validates the signal number:

| n | `n(100, nil, buf, 8)` | verdict |
| --- | --- | --- |
| 226 | `-22` (EINVAL) | **rt_sigaction** — it validated the signal |
| 227 | `0` | rt_sigprocmask — `how=100` ignored under a nil set |

A nil `act` throughout means the scan cannot arm a handler by accident.

### 4. Still open: three numbers, and the ucontext offsets

`getpid`, `kill` and `sigaltstack` are not yet pinned — xtensa's table is its own
(`write=13`, not the generic 64; the tree knows only read/write/close/openat/fchmod)
and a resumable scan is still walking. `sigaltstack` matters most: it is half of the
stack-overflow-SIGSEGV property that
`bug-a-four-hosted-targets-install-signal-handlers-without-an-altstack` exists for,
and SA_ONSTACK without it is inert.

The `ir.inc` ucontext offsets (addendum 3) remain unmeasured, and the circularity
flagged there is now **partly broken**: a handler can be entered without any of this
ticket's runtime existing, so a probe CAN read a ucontext before
`EmitSignalRuntimeXtensa` lands. What it still needs is a few instructions to park
the kernel's `a4` where Pascal can read it — far less than the runtime, and the
altstack-scan trick (dump a known buffer and match the sentinel) may avoid even that.
Not yet attempted; recorded so the next session does not re-derive it.

## Addendum 5 (frankS, 2026-08-30): xtensa's signal syscall numbers, measured — four pinned, one narrowed, and one self-correction

The port cannot be written without these and **not one of them is in the tree**:
xtensa carries its own table (`write` = 13, not the generic 64) and the tree knows
only read/write/close/openat/fchmod. All measured under `qemu-xtensa`, compiler
sha256 **2f88481adc6b**, HEAD `6e20c989f`. No compiler source touched.

| call | n | how it was pinned |
| --- | --- | --- |
| `rt_sigaction` | **226** | a working install, end to end (addendum 4), not an errno signature |
| `rt_sigprocmask` | **227** | the `n(100, nil, buf, 8)` separator — ignores `how` under a nil set |
| `sigaltstack` | **224** | installed a real altstack and read it back: `sp` matches, `size` = 32768 |
| `kill` | **123** | the ONLY candidate accepting a non-positive pid |
| `getpid` | **{120, 126, 127}** | narrowed, **not pinned** — see the correction below |
| `rt_sigreturn` | *(225)* | **inferred, NOT measured** — see the caveat below |

### `kill` = 123, and why three candidates answered alike

A scan for `{kill(self,0) -> 0, kill(999999,0) -> -ESRCH}` returns **123, 124 and
215**: `tkill` and `tgkill` share that signature exactly. The separator is a
**non-positive first argument**, which only `kill(2)` accepts — pid 0 means "my
process group", -1 means "everything I may signal", while tkill/tgkill validate a
tid > 0:

| n | `n(0, 0)` | `n(-1, 0)` | verdict |
| --- | --- | --- | --- |
| **123** | 0 | 0 | **kill** |
| 124 | -22 | -22 | tkill — validates tid > 0 |
| 215 | 0 | -22 | tgkill-family |

`sig = 0` throughout, so the whole scan is a permission check that signals nothing.

### The self-correction: `getpid` is NOT 150, and the oracle was the thing that was wrong

Recorded because the failure is reusable, not because the number matters.

I pinned `getpid = 150` against what I called an oracle: the shell backgrounded the
run and `$!` gave a pid that 150 returned exactly. **`$!` was the `timeout`
process, which is qemu's PARENT** — so 150 answered the oracle because 150 is
`getppid`, and the match was real, sound, and about the wrong process.

It survived because it agreed with an independent measurement. What killed it was
a **second** independent measurement disagreeing: the full scan's stable-positive
list showed *seven* numbers answering pid-shaped values, which cannot all be
`getpid`. Re-run with the qemu process as a **child** of a `setsid` leader, so that
sid, pgid, pid and ppid are four distinct numbers, the candidates split cleanly:

| candidates | answered | is |
| --- | --- | --- |
| 129 | the leader's pid | `getsid`/`getpgrp` |
| **120, 126, 127** | qemu's own pid | **the getpid family** |
| 149, **150**, 151 | qemu's parent | the `getppid` family |

Three still answer the process's own id — `getpid`, `gettid` and most likely
`set_tid_address`, which are **indistinguishable in a single-threaded process by
construction**. Any of the three would work operationally in the `.dfl` path, since
all three feed `kill` the right number; recording the wrong *name* in the comment
beside it is the defect to avoid, so it stays narrowed rather than guessed.

> The lesson is not "check the oracle". It is that **an oracle can be precise,
> reproducible and about a different subject than you think**, and the only thing
> that catches that is a second measurement whose shape is different — here, a
> count that came out too large.

### `rt_sigreturn` = 225 is INFERRED and must not be used as measured

A blind no-arg scan crashes at **225**, which is what calling `rt_sigreturn`
outside a signal context does, and 224/226/227 bracket it as a contiguous signal
block. That is a good story and it is **not a measurement**. Nothing in the port
needs it — the kernel supplies the return path itself (addendum 4, and the return
test below) — so it is recorded as a hypothesis and no code should cite it.

### Return-from-handler WORKS, and the first test that said otherwise was confounded

The dispatch stub returns to resume the interrupted program, exactly as riscv32's
does through the kernel trampoline. First test: install a SIGSEGV handler, fault,
return without fixing anything, count re-entries. It **died 139 on the first
return**, which reads as "the return path is broken on xtensa".

It is not. **SIGSEGV is blocked inside its own handler**, so the re-fault takes the
default action and force-kills — that happens whether the return path works or not,
so the test could not answer its own question. Re-run with `SA_NODEFER`
(`0x40000000`) so the signal is not blocked on re-entry:

```
sigaction=0
ENTRIES=3
exit=0
```

Three entries and a clean exit: **`ret` out of a Call0 handler unwinds correctly on
hosted xtensa.** Had the first result been written into this ticket it would have
been a wrong root cause of exactly the kind
`devdocs/dev/root-cause-over-microfix.md` is about — a plausible story, a real
crash, and the wrong mechanism.

### Where the port stands

Everything the stub needs is now known except one name among three:

- entry ABI: Call0, kernel enters a plain Pascal proc — **measured**
- `struct sigaction`: riscv/arm64-shaped, no SA_RESTORER, sigsetsize 8 — **measured**
- return path: works — **measured**
- install / altstack / re-raise numbers: 226 / 224 / 123 — **measured**
- `getpid`: one of three, all operationally equivalent here — **narrowed**

Remaining before the stub is correct rather than plausible: xtensa has no `auipc`,
so materialising the dispatch stub's own address (riscv32 does it with
`auipc+addi`, x86-64 with call/pop, aarch64 with `adr`) needs the `call0 .next`
idiom, which lands the address in `a0` and therefore has to be framed around the
install stub's own return address. `EmitGlobRef`/`EmitDataRef` relocate DATA
addresses only, and `ProcAddrFix` is keyed by proc index, so neither serves a raw
code offset. That is the one piece of the port with no in-tree model.

## Addendum 6 (frankS, 2026-08-30): the one piece with NO in-tree model — xtensa has no `auipc`

Written **before** the stub, at the coordinator's instruction, because this is the
piece a later reader will assume was solved the usual way. It was not, and it
cannot be.

The install stub must put the **dispatch stub's own absolute address** into the
`sa_handler` field. Every other backend has a one-instruction idiom for it:

| target | idiom | why it does not transfer |
| --- | --- | --- |
| x86-64 | `call +0` then `pop rdx` (`EmitCodeAbsToRdx`, ir_codegen.inc:496) | x86-only |
| aarch64 | `adr x10, dispatch` (ir_codegen_aarch64.inc:276) | no `adr` on xtensa |
| riscv32 | `auipc t0, 0` + `addi` (ir_codegen_riscv32.inc) | **xtensa has no `auipc`** |

And neither in-tree relocation serves it:

- `EmitGlobRef` / `EmitDataRef` (via `XtensaEmitLitHeader` + `l32r`) relocate
  **data** addresses — BSS and the data segment. A code offset is not either.
- `ProcAddrFix` (the `IR_PROCADDR` arm, ir_codegen_xtensa.inc:3831) is keyed by
  **proc index** and patched to `entry + BodyAddr`. `SigDispatchAddr` is a raw code
  offset inside the runtime blob, not a procedure, so it has no index to key on.

**The idiom that does work, and its two traps.** `CALL0` sets `a0` to the address of
the instruction following it (`PC + 3`), which makes `call0 .next` the xtensa way to
read the PC. Both traps are in `EncodeXtensaCall0` and both are load-bearing:

1. **The target must be 4-aligned** — `CALL0` encodes a WORD offset
   (`target = align4(PC) + 4 + imm18*4`), and the encoder raises rather than
   truncating. `call0` is a 3-byte instruction, so the natural fallthrough at
   `PC + 3` is *not* aligned and a pad byte is required.
2. **`a0` is `PC + 3`, not the aligned target** — the return address and the jump
   target differ by the padding. The delta added afterwards must be computed from
   `PC + 3`, not from where control actually resumes. Getting this backwards
   misplaces the handler address by one to three bytes, which installs a handler
   pointing mid-instruction — a fault at signal-delivery time, arbitrarily far from
   the cause, and only on the path that a signal actually arrives on.

`addi`'s immediate is **-128..127**, so a delta beyond that needs
`EmitLoadConstXtensa` into a scratch register and an `add` rather than a single
`addi`. At the sizes involved that is the expected case, not the exception.

Third constraint, from the same encoder: `a0` is also the install stub's **own**
return address, so the `call0` must be framed — saved before and restored after —
or the stub cannot return to its caller.

**Related, and the reason `XtensaRelCheck` exists at all:** every xtensa PC-relative
field silently wraps on overflow, and the repo has already paid for it once — an
ESP-IDF image encoded a `j` as `262581 mod 262144 = 437` and landed
mid-instruction inside an unrelated routine
(`bug-a-xtensa-pc-relative-encoders-silently-truncate-an-out-of-range-offset`).
The check is in the encoders now, so this stub inherits the protection; it is
recorded here because "the offset silently targets a different valid address" is
the same failure class as the `-1` sentinel and the recalled syscall number, and
this ticket has now met it three times in three different disguises.
