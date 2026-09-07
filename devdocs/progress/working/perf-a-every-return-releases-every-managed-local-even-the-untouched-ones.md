---
track: A
prio: 70
status: working
type: perf
blocked-by: []
summary: "MEASURED, two independent methods agreeing. `EmitManagedLocalCleanup` releases EVERY managed local at EVERY return, whether or not that path ever touched it, and the sweep is emitted INLINE at each return. Two separable costs, and conflating them will misdirect the fix: (1) RUNTIME — the full sweep EXECUTES on every call, measured linear at 3.87ns per local per call even when every slot is nil, which is ~4.5% of a compile for ParseFactorCore's 532 locals alone; (2) CODE SIZE — 308,112 release call sites binary-wide = ~36% of the compiler's 10.2MB .text. A shared epilogue fixes (2) and NOT (1): the sweep still runs in full. (1) needs per-path liveness. (2) applies to FIVE backends: wasm32 already has the shared epilogue because structured control flow forced it (franka-29, measured), which makes it an existence proof rather than an exception. (1) applies to all SIX. MEASURED 2026-09-06 (was flagged unexplained): the model reproduces 3.772 against 3.821 real, and it decomposes as prologue nil-init store 0.526 (14%) + epilogue load 0.262 (7%) + THE CALL/RET PAIR 2.984 (79%). franka-29 was right that the helper body is cheap -- that body costs 0.879 inlined; the cost is getting there and back. An inline nil-test at the call site takes it 3.772 -> 1.667, a 56% runtime saving with NO liveness. MEASURED 2026-09-07 BY TWO METHODS THAT FAIL DIFFERENTLY: ~98% of the swept slots are COMPILER-MINTED UNNAMED TEMPS, not locals anybody wrote -- 98.4% by direct count (ParseFactorCore: 10 named vs 609 unnamed tk=23 syms in the IR) and 98.2% by subtraction (757 released slots off the binary, 14 declared off the source). So per-path liveness over USER locals addresses 14 of 757 slots, 1.8% of the worst sweep, and cost (1) is a question about temps. NOT settled: whether temps can be skipped -- :13838's 'does not outlive the statement' is about the temp's VALUE, while the release loop needs a claim about OWNERSHIP of what it references, and skipping without that is a leak no value assertion catches. Note the prologue store is a THIRD cost that neither fix (1) nor (2) touches, and it is PER-SLOT ON ALL SEVEN TARGETS (measured 2026-09-07 by return-count separation, no disassembler needed) -- so one liveness analysis serves both halves. wasm32's release term is 0.062 B/slot/return, the first actual MEASUREMENT of its shared epilogue rather than an inference, and it still pays the full per-slot prologue. WARNING: the compiler's `code=` is page-quantised (65536 on aarch64, where it reads 196376 for both N=4 and N=532) and on wasm32 reports 3582 flat while the code section grows 13707 bytes -- use artefact size, never `code=`, for anything per-slot. Found from the Track P ticket perf-p-parsefactorcore-walks-a-92-arm-name-chain-per-factor, whose premise this refutes for the third time."
owner: frank-subcoord
---

# Every return releases every managed local, including untouched ones

`EmitManagedLocalCleanup` (`compiler/symtab.inc:12212`, the x86-64 arm;
`EmitManagedLocalCleanupForTarget` in `ir_codegen.inc:13643` for the other five)
loops `for i := Procs[CurProc].ScopeBase to SymCount - 1` and emits, per scalar
`tyAnsiString` local:

```
mov rax, [rbp+off]        ; symtab.inc:12316
call AnsiStrReleaseAddr   ; symtab.inc:12317
```

It is reached from `EmitProcScopeExitCleanupForTarget`, which
`EmitProcEpilog` calls, and `EmitProcEpilog` is emitted **inline at every
return** — its own comment says so: *"Reached by every return (early Exit and
fall-through both go through EmitProcEpilog)."*

## The measurement — `ParseFactorCore`, the worst case

Binary `p26-g-O2` built `-O2 -g` from `compiler/pascal26` at `a1536a832`
(`code=10178328B`, **identical to the plain default build**, so `-g` did not
change codegen and this is the shipping configuration). Workload: a zero-byte
`.npy`, i.e. parsing `pylib.pas` + `pyeval.pas`. `wall=1.87 user=1.81` — pure
user CPU, so the `<outside .text/vdso>` bucket is noise and every share below is
renormalised on in-`.text` samples, per `tools/pxxprof`'s own warning. It swung
17.0% / 23.2% / 47.3% across three identical runs; the renormalised numbers
moved 0.43pp.

`ParseFactorCore` is **9.92% / 9.94% / 10.35%** of in-`.text` samples over three
runs — i.e. **unchanged** from the 9.44% that opened the Track P ticket, so
`440c822e6` did not remove it.

Its extent is **1,146,385 bytes**, agreed by two independent symbol sources
(DWARF, and the compiler's own `.map`, 4143 entries, exactly one of which lands
in the range). Disassembled:

- **80,385** `call AnsiStrRelease` sites, in **exactly 150 runs of exactly 532**
  — mean = median = max. 532 string locals, 150 return points, every return
  releasing all 532.
- That chain is **84% of the function's bytes** and **36.1% of the samples that
  land in it**.

## The independent confirmation, which is what separates the two costs

A function with N `AnsiString` locals that assigns exactly one of them and
returns, 2M calls, min of 3 interleaved rounds:

| N locals | ms |
| --- | --- |
| 4 | 218 |
| 64 | 653 |
| 256 | 2192 |
| 532 | 4300 |

Linear: **3.87ns per local per call** (~11.6 cycles — `mov`/`call`/`test`/`je`/
`ret`), paid for slots that are **nil and were never touched**. The release
thunk's own fast path is `test rax,rax; je` — it is already as cheap as a call
can be, which is why the fix is not in the thunk.

Cross-check against the profile: 41,032 `ParseFactorCore` calls x 532 slots x
3.87ns = **84.5ms of 1870ms = 4.5%** of the compile. The sampling method said
~3.6% on the chain's own instructions plus a share of the release thunk's 8.1%.
**Two methods that fail differently, agreeing.**

### This is why a shared epilogue is only half a fix

The scaling table's teardown is ~6.4KB and contiguous — i-cache resident, no
150-fold duplication — and it still costs 3.87ns per slot. So the cost is the
**executed** releases, not the duplicated code. Emitting the sweep once and
jumping to it would cut ~36% of `.text` and change the runtime very little.
Cutting the runtime needs the sweep to skip slots that cannot be non-nil on the
path being taken.

## Scope, binary-wide

**308,112** `call AnsiStrRelease` sites in the whole compiler. At 12 bytes per
`mov`+`call` that is ~3.7MB of 10.18MB `.text` — **~36%**.

## What this does NOT say

Nothing here is a leak and nothing is wrong: releasing an untouched nil slot is
correct, just unnecessary. **Any fix must keep the sweep conservative** — the
guards in `EmitManagedLocalCleanup` are load-bearing and each was a real leak
(`not IsArray` on the AnsiString and Variant arms, both measured). A liveness
pass that is wrong in the *other* direction is a leak, not a slowdown, and
`test_open_array_no_leak.pas` shows an output assertion cannot see one:
use `tools/assert_no_leak.sh`.

## Gate

Track A's, plus the sharp oracle the Track P ticket named: `compiler.pas` in,
`cmp` the two emitted binaries. A cleanup change must not alter one emitted byte
for a program whose paths all touch every local.

## Corrections and open questions (franka-29 + frankZ, 2026-09-04)

**Cost (2) is FIVE backends, not six — and wasm32 is the existence proof.**
franka-29 first told me wasm32 was a sixth instance, then measured it and
corrected themselves in their own voice, which is the version to trust.
`WasmEmitManagedLocals` has exactly three call sites and none is per-return
(entry zero-init, the normal epilogue, the exception pad). wasm has structured
control flow, so every `Exit` converges on one end block and there is nowhere to
duplicate a sweep *to*. One function, eight AnsiString locals, N early `Exit`s:

| N exits | 1 | 20 | 60 |
| --- | --- | --- | --- |
| wasm32 | 3525B | 3525B | 3525B |
| x86-64 | 65304B | 69400B | 73496B |

**So the shape this ticket proposes for (2) is already built on the one backend
whose language forced it.** Cost (1) is unchanged there: wasm32 still releases
every managed local whether touched or not.

**The 3.87ns per nil slot is UNEXPLAINED, and saying so is the point.**
franka-29's pushback, which is correct: the release thunk's fast path is
`test rax,rax; je`, a couple of cycles — so ~11.6 cycles per untouched slot is
not the branch. And it is not instruction fetch either, because the scaling
table's own teardown is 6.4KB, contiguous and i-cache resident, and costs the
same per slot as the 965KB duplicated version. **Neither of us has measured what
it actually is.** Recorded as an open question rather than left implied, because
*"a shared epilogue barely touches runtime"* is a measured fact sitting next to
an unmeasured explanation, and the second reads as settled if nobody says it is
not.

An attempt to close it here failed and is recorded so nobody repeats it: I
compared 532 nil slots against 532 assigned ones (607ms vs 12455ms per 200k
calls). **Confounded and unusable** — the assigned arm performs 532 extra
assignments per call, so it measures assignment cost, not release cost. It does
not tell you anything about the epilogue.

**A sharper form of the liveness warning, from franka-29 hitting it the other
way tonight.** The stated hazard was that a liveness pass erring toward skipping
leaks, and an output assertion cannot see a leak. There is an EARLIER failure
than that: **a probe that never reaches the arm at all also passes, with every
row correct, and reads as confirmation.** franka-29 nearly wired a class-
hierarchy `is`/`as` test as the guard for a VMT fix — TRUE and FALSE rows, all
right answers — which passes identically on a compiler with no arm for the op,
because `ir.inc` routes class targets through a runtime RTTI walk and only
interface targets reach the instruction under test. The liveness-shaped version
of that mistake: **a test whose managed locals are all in the TOUCHED set proves
nothing about the skip decision.** Build the probe from locals that are provably
never assigned, and assert with `tools/assert_no_leak.sh`, not with output.

## 2026-09-06 — the 3.87ns is MEASURED now. It is the call/ret, and 14% of it was never the epilogue

Measured by frank-subcoord on plexus, no compiler edits, so this collides with
nothing in `EmitManagedLocalCleanupForTarget`.

### Step 1 — reproduce the ticket's own row in Pascal, on this box

N AnsiString locals, exactly one assigned, 2M calls, min of 3 interleaved:

| N | wall | marginal |
| --- | --- | --- |
| 4 | 189.3 ms | — |
| 64 | 628.9 ms | 3.663 ns/slot/call |
| 256 | 2062.3 ms | 3.733 ns/slot/call |
| 532 | 4171.6 ms | **3.821 ns/slot/call** |

Against this ticket's 3.87. **The row reproduces**, so what follows is about the
model and not about the box. Compiler `48c9f5942757` at `06041222e`; Xeon
E5-2620 v2, 2.10GHz nominal.

### Step 2 — read what is actually emitted, both ends

The pxx ELF writer emits no section headers, so `objdump -d` is silent and has
to be driven as `-b binary -m i386:x86-64 --adjust-vma=0x400000`. Per slot:

```
prologue:  movq   $0x0,-0x8d0(%rbp)        <- 11 bytes, ONE PER MANAGED LOCAL
epilogue:  mov    -0x8d0(%rbp),%rax
           call   0x400192
helper:    test %rax,%rax ; je out ; cmpq $0x40000000,-0x10(%rax) ; jae out
           decq -0x10(%rax) ; jne out ; <slow path> ; out: ret
```

**The prologue nil-inits every managed local, one store each.** That store
scales with the same N as the release, so it is *inside* this ticket's "per
local per call" number by construction — and neither franka-29's analysis nor
mine had separated it. It is a THIRD cost, and neither fix (1) nor fix (2)
touches it.

### Step 3 — a C model in that exact shape, calibrated against the real number

`volatile void*` slots, one zero-store each, then the epilogue variant; the
helper transcribed instruction-for-instruction from the disassembly above.
Verified by `objdump`: 532 zero-stores, 532 stack loads, 532 calls (and 532 `je`
in the inline arm). N=532, 2M calls, min of 9 interleaved:

| variant | wall | ns/slot |
| --- | --- | --- |
| as-is: store + load + call | 4013.0 ms | **3.772** |
| inline nil-test at the call site | 1773.6 ms | 1.667 |
| store + load, no call | 838.4 ms | 0.788 |
| store only | 559.2 ms | 0.526 |

**3.772 modelled against 3.821 measured — 1.3%.** The model is the thing.

### The decomposition

| component | ns/slot | share |
| --- | --- | --- |
| prologue nil-init store | 0.526 | 14% |
| epilogue load | 0.262 | 7% |
| **the call/ret pair** | **2.984** | **79%** |

**franka-29 was right and it does not explain the number.** `test rax,rax; je`
*is* a couple of cycles — and that is the helper's BODY, which costs 0.879
ns/slot when the same work is inlined at the call site. The 3.87 is not what the
callee does. **It is getting there and back**: 2.984 ns/slot ≈ 6.3 cycles at
2.1GHz for one `call`/`ret`, 1064 taken branches per invocation alternating
between two widely separated code regions in a ~12KB straight-line body. That is
consistent with the ticket's other observation rather than against it — the
6.4KB contiguous teardown costs the same per slot as the 965KB duplicated one
because **neither is an i-cache miss and both pay the same call/ret**.

### What it implies for the fix, as a measurement and not a prescription

An inline `test; je` at each call site, calling only when non-nil, takes the
model from 3.772 to 1.667 ns/slot — **56% of total runtime, and 65% of the
epilogue** — with no liveness analysis at all. frank-coord-core's caveat is
recorded and is the load-bearing one: **there is no nil test at any call site
today on any of the six register backends** (the helper does it internally,
after the call), so this ADDS the first one and is a bigger emitter change than
its size suggests. The load, however, happens either way — that is what the
`store + load, no call` row is for, and it costs 0.262 ns/slot.

The remaining 0.526 ns/slot of prologue nil-init is untouched by both fixes and
needs the same liveness information fix (1) does.

**Not claimed:** that the inline test is correct, cheap to emit, or worth it on
any particular backend. That is the owner's call on their function.

## 2026-09-07 — the prologue store is per-slot on ALL SEVEN targets, and two instruments had to be thrown away first

The 3.87ns decomposition above is an **x86-64** measurement, so the 14% prologue
share is a claim about one target until measured elsewhere. It generalises.

**The separator, and it needs no disassembler:** the zero-init is emitted **once
per procedure**, the release **at every return**. So vary the return count and
the release term moves while the store term does not. `code(N,R) = base +
N*store + R*N*release`, solved from three builds: `(4,1)`, `(532,1)`, `(532,5)`.

| target | release B/slot/return | prologue store B/slot | per-slot store? |
| --- | --- | --- | --- |
| x86-64 | 13.47 | 9.80 | yes |
| i386 | 17.32 | 13.71 | yes |
| aarch64 | 27.31 | 16.44 | yes |
| arm32 | 32.72 | 21.58 | yes |
| riscv32 | 21.17 | 9.86 | yes |
| xtensa | 11.55 | 11.72 | yes |
| wasm32 | **0.06** | 25.90 | yes |

x86-64 corroborates the disassembly: measured 9.80/13.47 against the actual
11-byte `movq $0x0,disp32(%rbp)` and 12-byte `mov`+`call`.

**So any liveness analysis that skips a slot's release should skip its zero-init
too, on every backend — one analysis, both halves.** (frank-coord-core's
framing; this is the measurement that says it generalises.)

**And wasm32 is the interesting row.** Its release term is 0.06 B/slot/return —
131 bytes total for four extra returns across 532 slots, which is the four branch
sequences and nothing per-slot. **That is the shared epilogue, and this is the
first measurement of it rather than an inference from "wasm32 already has it".**
It also shows wasm32 still pays the full per-slot prologue: **where the epilogue
is already shared, the zero-init is the entire remaining per-slot code cost.**

### Two instruments discarded on the way, both of which printed confident numbers

**1. The compiler's own `code=` is page-quantised, and on aarch64 the quantum is
larger than the whole signal.** Every `code=` gap on every ELF target is a
multiple of 4096. On aarch64 it is 65536, and `code=` reads **196376 for N=4 and
196376 for N=532** — flat across a 528-local difference. A first pass through
this table read that as "aarch64 does not emit a per-slot store". It emits one;
at N=3000, past the quantum, it is 16.44 B/slot. **The instrument did not error.
It reported a constant, which is a perfectly plausible answer to the question
being asked.**

**2. `code=` on wasm32 tracks neither the code nor the file.** It reads **3582B
for N=4 and 3582B for N=532** while the module's actual code section grows 65929
-> 79636 (13707 bytes, 25.96 per slot). The first reading of that flat 3582 was
*"0.00 bytes/slot/return — the shared epilogue, confirming the ticket
independently"*. It confirmed nothing: a shared epilogue still scales the
prologue, so a row flat in **both** N and R is vacuous, not a finding. The
control that separates them is sweeping **N**, which a return-count experiment
does not do by construction. Parsing the module's section table is what settled
it.

Both are the vacuous-green shape this ticket's own `check_pal(2)` note describes,
met twice in one measurement. Use **artefact size** (or the wasm code section),
never `code=`, for anything per-slot.

## 2026-09-07 — cost (1) is a question about COMPILER-MINTED TEMPS, not about user locals

The ticket's liveness argument has been weighed against an unmeasured assumption:
that the swept slots are the locals a programmer wrote. **In the worst frame,
98.2% of them are not.**

### The frame, identified without symbols

Release call sites in `compiler/pascal26` come in maximal consecutive runs, one
run per return. Reading them off the binary (`objdump -D -b binary
-m i386:x86-64 --adjust-vma=0x400000`, because the ELF writer emits no section
headers):

- **349,322** release sites in **20,479** runs, up from the ticket's 308,112.
- The largest ordinary frame: **757/758 slots x 140 returns**. (The +-1 pair is
  one procedure; a couple of returns release one slot fewer.)

That frame is `ParseFactorCore`, identified from an **independent** source
rather than assumed: its body carries **138 `Exit` statements plus a
fall-through**, against the 140 returns measured in the binary. It was 532 when
this ticket was filed; it is 757 now.

### What those 757 slots actually are

`ParseFactorCore` declares **206 local names** in its `var` block. By type:
149 `Integer`, 20 `Boolean`, 19 `TTypeKind`, **14 `AnsiString`**, 3 `Int64`,
1 array of `TTypeKind`. Only the AnsiStrings are managed.

**So 14 of the 757 released slots are named in the source. The other ~743 are
compiler-minted unnamed temps** — `ir_codegen.inc:13808` calls them "the HIDDEN
MANAGED LOCALS this body's parse/lowering minted ... every other unnamed local
created after the prologue's EmitManagedLocalsZeroInit already ran".

**Stated as the bound it is:** 757 is measured from the binary and 14 from the
source; **743 is a subtraction, not a count.** It assumes every release site
corresponds to a scalar `tyAnsiString` slot, which is what this ticket's own
mechanism section says the loop emits.

### Why that changes which fix is worth building

**Per-path liveness over the locals a programmer wrote would address 14 of 757
slots — 1.8% of the sweep in the worst frame.** The win is in the temps, and
the compiler already knows two things about them that it does not use here:

1. **It can identify them exactly**, with no new analysis — the zero-init pass
   beside this one already selects on `Syms[i].Kind = skLocal` and
   `Syms[i].Name = ''` (`ir_codegen.inc:13841`).
2. **It has already written down their live range:** *"an unnamed temp does not
   outlive the statement that minted it"* (`:13838`).

**NOT CLAIMED, and it is the correctness question for whoever implements:** that
those temps can simply be dropped from the scope-exit sweep. That comment
justifies re-scanning for ZEROING; whether anything releases a temp within its
statement is unverified here, and skipping the release without that is a leak —
which, per this file's own note on assertion classes, **no output assertion
would catch.**

### The cost is concentrated, which makes a narrow fix worth more than a broad one

| frames of >= N slots | release sites | share of all | returns |
| --- | --- | --- | --- |
| 400 | 197,771 | **56.6%** | 278 |
| 100 | 288,506 | 82.6% | 839 |
| 50 | 296,728 | 84.9% | 949 |
| 10 | 320,919 | 91.9% | 2,108 |

Median run length is **1**; mean 17.1; max 1,515. **Over half of every release
site in the compiler is emitted at 278 return points.** A fix that only helped
frames above a few hundred slots would still take most of the cost, and a
per-procedure opt-in would be cheap to validate.

### What this does not settle

Body-wide, not per-path (frank-coord-core's caveat, and it is the right one):
`SymWrittenInProtectedSpan`-shaped counting answers "is this symbol written
anywhere in the body", and IR index ranges follow lowering order rather than
control flow. That is a strict UPPER bound on the per-path count. Here the bound
already decides the direction — 14 named slots is small however you count the
paths — but it does not decide the temps, which is where the work now is.

### 743 was a subtraction; here is the count, and it agrees

Flagged above as a bound, and frank-coord-core was right to press on it. The IR
dump prints unnamed symbols as `[sym=]` and carries the type kind, so the split
can be COUNTED rather than derived. `tk=23` is `AnsiString`, confirmed against a
probe with known declarations.

`PXXDBG='a.ir:*'` over `compiler.pas`, `ParseFactorCore`'s section, distinct
`store_sym` targets with `tk=23`:

| | distinct syms |
| --- | --- |
| NAMED | **10** |
| UNNAMED (compiler-minted) | **609** |
| unnamed share | **98.4%** |

Against **98.2%** from the independent subtraction (757 released slots off the
binary, 14 declared off the source). **Two methods that fail differently, one
digit apart.** The first can be wrong by miscounting release sites or
declarations; the second by the IR dump omitting a store. Neither can produce
the other's error.

The symbol indices corroborate the mechanism rather than just the ratio: the
named locals occupy **3345..3516** and the temps a contiguous block **above**
them at **3531..5103** — which is `ScopeBase..SymCount-1` with temps appended
during the parse, exactly as `ir_codegen.inc:13808` describes.

**A smaller finding inside the small population:** only **10** of the **14**
declared AnsiStrings are ever written anywhere in the body. Four named locals
are dead on every path, unconditionally, and are released 140 times each.

### The correctness question, sharpened (frank-coord-core's, and it is the right cut)

`:13838` — *"an unnamed temp does not outlive the statement that minted it"* — is
a claim about the temp's **VALUE**. The zero-init pass is entitled to it, because
re-zeroing something dead is harmless. **The release loop needs a different
claim: that ownership of what the temp REFERENCES was transferred or dropped
inside that statement.** One does not imply the other, and a temp holding the
only reference to a string at statement end, skipped by the sweep, is a leak that
every value assertion passes.

**So nobody should build temp-skipping off that comment.** What settles it is not
reading harder: build with temps excluded from the release sweep and run
`tools/assert_no_leak.sh` over a corpus that actually mints them. That is the one
instrument that can see this failure class. Flat live bytes means the claim is
real; live bytes scaling with iterations means a bigger bug than this ticket.

## 2026-09-07 — TEMPS CANNOT BE DROPPED FROM THE SWEEP. Measured by building it.

frank-coord-core, running the experiment the section above names. **The
direction is dead, and it is dead by measurement rather than by reading the
comment more carefully.**

One refinement to how that experiment was framed: the section above says
*"live bytes scaling with iterations means a bigger bug than this ticket"*.
It scaled, and it is NOT a bug — the leak is CAUSED by the experimental
change, not revealed by it. The tree is correct today; what the scaling
refutes is the proposed optimisation. Worth stating because someone reading
that line and this table together would otherwise go looking for a defect
that is not there.

Built exactly the change — unnamed locals excluded via `SymSkipScopeExitRelease`,
which after the seven-copy refactor is one line covering all seven backends —
and ran a program that mints temps rather than declaring them
(`test/test_unnamed_managed_temps_are_released.pas`, wired as a census row):

| iterations | temps SWEPT | temps SKIPPED |
| --- | --- | --- |
| 20 000 | `live=5` | `live=75189` |
| 80 000 | `live=3` | `live=309011` |

**4.11x the leak for 4x the work — proportional, which is the signature of a
per-call leak and not of a fixed residue.** ~3.8 of the ~19 temps that body
mints per iteration hold the ONLY reference at scope exit. Allocation totals are
identical in both columns (375931 / 1545047), so nothing about what the program
allocates changed; only what it gives back did.

The experiment was reverted and the restored compiler is byte-identical to the
pre-experiment binary, so nothing here is in the tree except the test.

### Why the comment reads like permission and is not

`ir_codegen.inc:13838` — *"an unnamed temp does not outlive the statement that
minted it"* — is TRUE, and it is a claim about the temp's **VALUE**. That is
exactly what entitles the ZERO-INIT pass beside it to re-scan: re-zeroing
something already dead is harmless. The release loop needs a different claim,
about **OWNERSHIP of what the temp REFERENCES**. The two are not the same and
one does not imply the other, which is why a careful reader gets this wrong.

### What it means for the two candidate fixes

- **`98.4% temps` is not an opportunity, it is a warning.** The sweep is ~98%
  temps and ~98% of it is load-bearing. Any fix that skips slots must prove
  ownership per slot, not lifetime per statement.
- **It moves against the inline nil-test's transferability, mildly.** The 1.667
  ns/slot was measured on an all-nil frame, on the reasoning that temps are
  already nil at the epilogue so the branch predicts perfectly. A meaningful
  share of them are NOT nil — they hold the last reference. How that maps from
  allocations to SLOTS is not established here and should not be guessed; it is
  a smaller effect than the 56%, and it is the direction that costs rather than
  the one that flatters.
- **Per-path liveness over user locals is still 10 of 619** and still not worth
  building on its own.

A test now guards the direction, because the next reader of `:13838` will reach
the same conclusion and an output assertion will not stop them: every `WriteLn`
in that program is correct with the releases removed.

## 2026-09-07 — thresholds for the frame-size-gated inline nil-test, and the tension nobody had priced

Measured for frank-coord-core to pick from. **The inline nil-test makes cost (2)
WORSE, and cost (2) is this ticket's other half** — release sites are ~36% of
`.text`. That trade had not been quantified on either side.

**Byte cost, measured not assumed:** the calibrated model's per-slot span is
**24.95 B/slot** as-is against **30.01 B/slot** inlined — **+5.06 bytes per
site**. That matches pxx's own encoding independently: `test %rax,%rax` is 3
bytes and a short `je` is 2.

Against 349,322 release sites and an 11,046,680-byte `.text`:

| threshold | sites | share | returns touched | `.text` growth |
| --- | --- | --- | --- | --- |
| every site | 349,322 | 100.0% | 20,479 | **+15.81%** |
| >= 10 | 320,919 | 91.9% | 2,108 | +14.53% |
| >= 50 | 296,728 | 84.9% | 949 | +13.43% |
| >= 100 | 288,506 | 82.6% | 839 | +13.06% |
| >= 200 | 223,110 | 63.9% | 366 | +10.10% |
| >= 300 | 204,844 | 58.6% | 297 | +9.27% |
| **>= 400** | **197,771** | **56.6%** | **278** | **+8.95%** |
| >= 600 | 197,239 | 56.5% | 277 | +8.93% |

**Cost is strictly 5 bytes per site, so coverage and size move together: every
1% of release sites covered costs 0.158% of `.text`.** There is no efficiency
sweet spot — the threshold is a **blast-radius** choice, not an efficiency one.

**T=400 is the natural ceiling going up:** 600 gains nothing over 400 (56.5% vs
56.6%), so above ~400 the frames run out. 278 return points carrying 56.6% is a
small, auditable set, and the sub-threshold control population is large —
**20,201 returns / 151,551 sites (43.4%) must come out byte-identical**, which
is the A/B drawn from the population the change is NOT meant to touch.

### The two fixes compose, and the ORDER matters

A shared epilogue emits the sweep **once per procedure** instead of once per
return. That does not merely fix cost (2) — **it collapses the inline test's own
size cost**, because the +5 bytes would then be paid per slot rather than per
slot per return.

Concretely, on the frame measured above: `ParseFactorCore` is
`758 x 61 + 757 x 79 = 106,041` release sites today. Behind a shared epilogue it
is **~758**. The inline test there costs ~530,000 bytes today and ~3,800 after.

**NOT MEASURED, and I tried and threw the attempt away:** the fleet-wide version
of that ratio. Grouping release runs into procedures by address adjacency fails,
because short in-statement temp releases interleave between a procedure's
epilogue sweeps — the method split `ParseFactorCore`'s known 140 returns into
groups of 4 and 5, and would have reported a confident and meaningless "1.3x".
Caught only by checking it against the one frame whose return count is known
independently. **So the concrete case stands and the aggregate does not.**

**The implication is an ordering, not a number:** doing the shared epilogue
first makes the inline nil-test close to free in code size, while doing the
inline test first spends up to 15.81% of `.text` on something the shared
epilogue would then have made cheap.

## 2026-09-07 — the design I am building, and why the ordering flipped

frank-coord-core, taking the emitter work. **frank-subcoord's threshold table
changed the order and the argument is theirs:** cost is strictly linear in
sites, so there is no efficiency sweet spot in the inline nil-test — every 1% of
coverage costs 0.158% of `.text`, and the threshold is purely a blast-radius
choice. Meanwhile a shared epilogue makes the inline test's own +5.06 B/site
collapse from *per slot per return* to *per slot*: in `ParseFactorCore`, ~530KB
becomes ~3.8KB. **Doing the sharing first makes the nil-test nearly free; doing
the nil-test first spends up to 15.81% of `.text` on something the sharing would
have made cheap.** So the sharing goes first.

### NOT "funnel every return through one epilogue" — a per-procedure thunk

Every early `Exit` calls `EmitProcEpilog` inline today (`ir_codegen386.inc:5614`,
`_arm32:4768`, `_aarch64:5017`, `_riscv32:3761`, and the Pascal/C frontends'
own sites), which is why 20,479 returns emit 349,322 release sites. Restructuring
all of that into one exit point is a control-flow change across six backends.

The contained version: **emit the sweep ONCE per procedure, out of line, and
`call` it from each return.** `EmitProcScopeExitCleanupForTarget` becomes the
call; the body moves to a thunk.

**The shape already exists in this file and does not have to be invented.**
`EmitProcCleanupLandingPadForTarget` is exactly a per-procedure out-of-line
block with a patched jump around it, and
`EmitProcCleanupFrameSkipForTarget` already dispatches that patched
unconditional jump across all six register targets. The thunk is the same
shape with a `call` instead of a fall-through.

Cost accounting, so it is not assumed:

- **Code:** `ParseFactorCore` goes from 106,041 release sites to ~758 plus one
  call per return. That is the whole of cost (2).
- **Runtime:** one extra call/ret per RETURN — **~2.1 ns, and under 3 in the
  worst case** — against a sweep that already pays ~2.98 ns per SLOT per
  return. On a 757-slot frame that is one part in 757 either way. It does not
  fix cost (1) and does not claim to.

  **The 2.984 figure does NOT apply here and this draft quoted it wrongly for
  an hour.** That number was measured in the sweep's own regime: 532 DISTINCT
  call sites strung across a ~12KB straight-line body, where the front end is
  the bottleneck. A thunk is the opposite regime — one target, called
  repeatedly, hot in i-cache, perfectly predicted — and measured directly
  (200M iterations, min of 7 interleaved, empty noinline callee against a
  compiler barrier) it is **2.064 ns**. frank-subcoord caught their own number
  being reused outside the regime that produced it. The honest range is 2.06 to
  2.98 and nearer the low end: the thunk is called from ~140 different return
  sites so return addresses vary, but pushes and pops stay matched so the
  return-stack buffer handles it. Quote the range, not either endpoint.
- **wasm32 is untouched**: it already shares, measured at 0.062 B/slot/return.

### How it lands, and the control

One backend per commit, the method the seven-copy refactor established. The
difference: on the target being converted, byte-identity is NOT available by
construction — the whole point is that the bytes change. So per step:

- the **six other targets** stay byte-identical, which bounds the blast radius
  to the arm actually touched. If a sub-threshold object moves, the step is
  wrong rather than interesting.
- the **converted target** needs behaviour: `PXX_ALLOW_FULL_SUITE=1` rather than
  quick, `tools/assert_no_leak.sh` over a temp-minting corpus (a sweep reached
  by `call` that fails to run is a leak, and no output assertion sees it), and
  the four frontend probes.

The leak instrument is not optional here for the reason this ticket already
carries: a sweep that is emitted once and then never CALLED prints every correct
answer.

**And it is run BEFORE each conversion on the same corpus, not only after.**
An absolute `live=5` after the change is flat for an unknown reason; `live=5`
before and `live=5` after, same corpus same bound, is flat for the right one.
Baseline on `test/test_unnamed_managed_temps_are_released.pas` at
`e86101766`: `allocs=375931 frees=375926 live=5`.

## 2026-09-07 — x86-64 LANDED. 31.9% off the compiler binary, and my first leak check passed for the wrong reason

The sweep is emitted once per body, out of line, and CALLed from the second
return onward. `EmitProcScopeExitCleanupForTarget`, gated on `TARGET_X86_64`;
the other six targets take the old inline path untouched. One backend, one
commit, as planned.

**Size, on the artefact and not on `code=`:** the compiler builds itself from
**11594364 to 7895676 bytes, −3698688, −31.9%.** The padded `code=` figures for
the same pair are 11058968 and 7360280 and **must not be quoted** — this run
produced a clean live demonstration of why: on `fires.pas` below, the base and
thunked binaries have **identical `code=73496B` and differ byte-for-byte**.
Same padded length, different content. That is frank-subcoord's caveat
(`9eb48c283`) reproducing on the first corpus I pointed it at.

**Runtime:** unchanged in kind — one call/ret per return, ~2.1 ns and under 3 in
the worst case, against a sweep that already pays ~2.98 ns per slot per return.
See the correction above for why the 2.984 figure does not apply to the thunk.

### The control that mattered, and it is the one that nearly did not run

I took the pre-conversion leak baseline frank-subcoord asked for, on
`test_unnamed_managed_temps_are_released.pas` and on the `mgd.pas` corpus. Both
came back **exactly flat**: `allocs=375931 frees=375926 live=5` and
`allocs=31686 frees=31680 live=6`, before and after, same bound.

**Both were flat because the thunk never fired in either.** `cmp` says the
before and after binaries for both corpora are **byte-identical** — neither
corpus contains a procedure with two returns and three releasable slots, so
neither compiled a single instruction differently. A flat leak count across two
identical binaries is not a measurement of anything.

This is exactly the shape frank-subcoord's own suggestion was aimed at, and the
suggestion is what caught it: an absolute `live=5` after the change reads as a
pass, and only having the BEFORE run on the same corpus made me ask why the two
numbers were not merely close but character-for-character equal. The answer was
that I had built a control out of the wrong population — the third instance this
week of a guard drawn from a population the question is not about.

So the corpus is now `fires.pas`: four managed locals, three return points,
20000 iterations. The thunk demonstrably fires on it (the binaries differ), and
the census is **`allocs=45116 frees=45114 live=2` before and after**, with
`FIRES OK 213336` from both. That is flat for the right reason.

### What was verified

| check | result |
| --- | --- |
| self-host fixedpoint | `converged after 2 round(s)` — real recompute, not the stamp |
| `tools/gate.sh quick` | GREEN, 20 rows, incl. `self-host fixedpoint` and `-O3 backend parity` |
| leak, corpus that fires the thunk | `45116/45114/live=2` before AND after |
| x86-64 A/B (positive control) | `identical=11 differs=28` — the change is real and visible |
| four frontend probes (npy/c/rs/zig) | all print `aaa` |
| six other targets, byte-identity | i386/arm32/aarch64/riscv32 38-0, wasm32 30-0, xtensa 28-0 — **0 differ anywhere** |
| exceptions + 3 returns, 5000 unwinds | identical census, `EXC OK ok=80000 caught=5000` from both |
| `-O0 -O1 -O2 -O3` on `fires.pas` | `FIRES OK 213336` at all four |

The cross-target rows are the ones that make "one backend per commit" a claim
rather than an intention: the thunk is gated on `TargetArch = TARGET_X86_64`, and
the other six recompile **byte-for-byte unchanged** against the pre-change
compiler. The x86-64 column differing on 28 of 39 built files is the other half
-- a control that only shows identity cannot tell a correctly-gated change from
a change that does nothing.

### Two things the design gained from the seven-copy refactor landing first

`ManagedSweepSlotCount` asks `ScopeExitReleaseAction` the same question the
emitter asks, so the count that decides whether to place a thunk cannot drift
from the code that gets placed. Against the old seven-copy tree there was no
single predicate to ask and this would have been an eighth copy of the skip
logic.

And the threshold is on RELEASABLE slots, not on declared locals: `SXR_NONE`
slots emit nothing, so counting symbols would have sized the thunk against work
it never does.

### Why a call, when the landing pad next door reaches its copy by a jump

The pad never comes back — it re-raises. A normal return does, and each return
runs a different epilogue tail, so the shared block has to return to its caller.
That is also the one hazard the pad does not have: **a call has already moved
rsp by 8 and the sweep makes calls of its own**, so the thunk opens with
`sub rsp, 8` and closes with `add rsp, 8` to restore the mod-16 residue the
inline sweep would have seen. All the sweep's own addressing is rbp-relative,
which a call does not disturb.

### The staleness guard, and why there is no per-body reset

The three arrays are indexed by proc and validated against `Procs[p].BodyAddr`.
A nested procedure has its own index, so an inner body can never reach an outer
body's thunk, and a body emitted twice finds its recorded address below the new
`BodyAddr` and rejects it. Zero means "none recorded" and BSS is zero-initialised,
so no frontend's body emitter needs a save/restore — which is the part that would
have been easy to get wrong in five places, and a stale address here does not
crash, it calls into the middle of whatever body now occupies that range.

### Next

- The other six targets, one commit each, in the same shape.
- Then the frame-size-gated inline nil-test at T=400.

## 2026-09-07 — NO SITE-COUNT PENALTY (frank-subcoord). Four wrong numbers, each caught by a shape check, and a refusal to quote the fifth

I asked whether the thunk's call/ret gets more expensive when one target is
called from ~140 different return sites rather than from one in a tight loop —
the regime neither of the two existing figures covers. frank-subcoord built five
models. **Four produced a number and every number before the last was wrong**,
each caught by inspecting the SHAPE of what was emitted rather than by the number
looking implausible:

1. 140 identical `case i: thunk(); break;` → **−21.215 ns**. gcc MERGED the
   identical cases; there was one call site, not 140.
2. Unique per-case bodies to stop the merge → **−0.582 ns**. `objdump` showed
   `jmp <thunk>`: gcc TAIL-CALLED it. No call/ret pair existed anywhere.
3. Work after the call to forbid the tail call (verified 140 `call`, 0 tail-`jmp`)
   → **−0.173 ns**. The 140-way indirect dispatch cost ~20 ns/iteration and the
   out-of-order window swallowed the call whole.
4. Cheap dispatch, sweeping site count → positive at low counts, **negative at
   64+ and non-monotonic**.
5. Arms padded to byte-identical size (a 5-byte `nop` with the same `"memory"`
   clobber, both switch functions exactly 5931 bytes by `nm`, identical layout
   and scheduling barrier, the only difference being the control transfer) →
   **the negatives survived**.

| sites | with (ms) | without (ms) | ns/call-ret |
| --- | --- | --- | --- |
| 1 | 1266.5 | 1068.6 | 0.990 |
| 2 | 1322.6 | 1077.3 | 1.226 |
| 8 | 1313.6 | 1097.4 | 1.081 |
| 32 | 1752.3 | 1438.8 | 1.568 |
| 64 | 2097.0 | 1901.7 | 0.976 |
| 128 | 2379.1 | 2749.4 | **−1.852** |
| 140 | 2894.3 | 3420.3 | **−2.630** |

**The negative reproduces** — 496 ms in model 4 and 526 ms in model 5, two
independently generated binaries with different layouts, one under load and one
idle, 200M iterations each. The arm carrying 140 extra call/ret pairs is
reproducibly FASTER than the arm carrying 140 nops of identical width.

**They declined to hand me a number from it, and that is the right call:** a
model in which strictly more work is reproducibly faster is not measuring the
cost of that work. This is the guard-failure family's newest member — not a
guard that cannot fail, but **a harness whose output has the wrong SIGN and is
still perfectly reproducible.** Reproducibility is not validity, and averaging
or re-running would have hardened the wrong answer.

**What it does establish, which is the question I asked:** across every model
that produced a readable number, **the delta never grows with site count** —
flat to 32, wrong-signed past it. Three structurally different models, none
shows a penalty, two show the opposite sign. The mechanism consistent with that
is the return stack buffer: with call and ret matched the return is predicted
off the RSB rather than off the return address, so site multiplicity costs
nothing on the return side, and a direct call's target is fixed. **Named as the
explanation consistent with the measurement, not as something measured.**

**The one number worth keeping:** models 4 and 5 agree closely at ≤32 sites
(0.98/1.23/1.08/1.57 against 0.99/1.25/1.04/1.29) despite being different
binaries — so **~1.0–1.6 ns marginal for one call/ret inside a body already
doing other work**, against 2.064 ns exposed in a tight loop. In a real body the
call/ret partly hides in slack that is already there. That leaves the ticket's
**"~2.1 ns, and under 3 in the worst case"** conservative in the right
direction, so it stands rather than being replaced by something indefensible.

Disclosure carried from their report: model 4's run was contaminated (archive
work during timing, the hazard CLAUDE.md names); model 5 was clean and agreed,
which is why the reproducibility claim is trusted and the absolute values are
not.

### The instrument that settles it needs no model, and it is now built

A/B the REAL compiler on a real workload. Both binaries are the same program —
**`compiler/compiler.pas` compiled by the pre-thunk compiler and by the thunked
one** — so they differ only in whether their own managed-local sweeps are inline
or thunked. That is the exact regime with nothing between the measurement and
it, and it captures what no model can: the I-cache effect of −31.9% on the
binary, which on this evidence could dominate the call/ret cost outright and has
the same sign as those negative rows.

**The precondition that makes it trustworthy: A and B must produce BYTE-IDENTICAL
output**, since they are the same program. Verified on `hello.pas`, `arrays.pas`
and on `compiler.pas` itself; `ab_time.sh` refuses to report a timing pair
unless that holds, so a number can never be quoted for two programs that
disagree.

There is no flag — the thunk is unconditional on x86-64 — so the no-thunk build
is `50e25f5f0^`.
