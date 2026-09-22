---
track: A
prio: 70
status: working
type: perf
blocked-by: []
summary: "MEASURED, two independent methods agreeing. `EmitManagedLocalCleanup` releases EVERY managed local at EVERY return, whether or not that path ever touched it, and the sweep is emitted INLINE at each return. Two separable costs, and conflating them will misdirect the fix: (1) RUNTIME — the full sweep EXECUTES on every call, measured linear at 3.87ns per local per call even when every slot is nil, which is ~4.5% of a compile for ParseFactorCore's 532 locals alone; (2) CODE SIZE — 308,112 release call sites binary-wide = ~36% of the compiler's 10.2MB .text. A shared epilogue fixes (2) and NOT (1): the sweep still runs in full. COST (2) IS NOW LANDED on all six flat-code backends, one commit each (x86-64 50e25f5f0, i386 3d7cde305, arm32 4a1a80184, aarch64 5f89103c9, riscv32 b1554c59a, xtensa Call0 dde109a7a); wasm32 is not a seventh and has its own ticket. Measured like-for-like on one instrument with TargetHasSweepThunk forced False for the control: compiler.pas release sites 349,581 -> 43,508 (8.03x), code= 11,075,352 -> 7,376,664 (-33.4%), artefact -31.9% -- and the control lands within 0.07% of the 349,322 counted independently by objdump, two instruments that fail differently. THAT DISSOLVES THE T=400 THRESHOLD rather than confirming it: at the measured +5.06 B/site the inline nil-test on EVERY site now costs +2.98% of .text against +15.97% before, i.e. a third of what the T=400 gate cost without the sharing, while covering 100% of sites instead of 56.6%. That recommendation -- build it UNGATED, keep a threshold in reserve only if the BUILT artefact's size cost came in materially above 2.98% -- was followed and its condition did not fire: measured +1.39%. THE BRANCH-WIDTH CAVEAT IS CLOSED and is structural, not a frequency: the per-slot sequence is `mov`+`call` with the argument already in rax, so a nil-test skips exactly one 5-byte `call rel32` and the displacement is 5 on every site in the binary -- cost is exactly 5 B/site, and a 7.23% figure for site-to-site gaps over 127 bytes measures a DIFFERENT quantity (gaps between sweeps, which the branch never spans). THE CHEAP HALF OF (1) IS BUILT ON x86-64 (2026-09-22, frankb-8e): the inline nil-test at the release call site, ungated, on the scalar AnsiString arm -- 4.367 -> 1.886 ns/slot/call, 56.8%, against the 55.8% the calibrated model predicted, and +1.39% of artefact against the +2.98% predicted, so the frame-size threshold's own trigger condition is measured and NOT met and T=400 is retired rather than deferred. The ratio transfers between boxes and the absolute does not: the control marginal reads 4.367 here under load against 3.821 on an idle box, both rows kept. WHAT REMAINS OF (1) IS THE EXPENSIVE HALF AND IT IS STILL UNSTARTED -- the full sweep still RUNS on every return; this removed the cost of ASKING about a slot, not the asking, and per-path liveness over compiler-minted temps is untouched. ALL SIX REGISTER BACKENDS NOW CARRY IT (2026-09-22, frankb-8e), one commit each with the other five byte-identical as the blast-radius bound: x86-64 022739dce, i386 2aa7e7159, arm32 a0f4facd8, aarch64 ec82fc0de, riscv32 63fdda88d, xtensa this commit -- 3 to 8 bytes per site depending on the ISA, and the split between the three arms needing an ABI argument for clobbered flags and the three needing none is exactly whether the architecture HAS condition codes. The ESP size question the middle commits deferred was measured before riscv32 was written (608e0f53c): a bare image is 15x less site-dense than compiler.pas, at whose density the ungated decision was already taken, so no ESP-specific gate is needed. Also still open: the non-string arms (SXR_VAR/SXR_OBJ/interface/array -- a string-slot decomposition does not transfer to a call that does real work), and the prologue nil-init store (0.526 ns/slot on all seven targets, which no fix on this ticket reaches). (1) needs per-path liveness. (2) applies to FIVE backends: wasm32 already has the shared epilogue because structured control flow forced it (franka-29, measured), which makes it an existence proof rather than an exception. (1) applies to all SIX. MEASURED 2026-09-06 (was flagged unexplained): the model reproduces 3.772 against 3.821 real, and it decomposes as prologue nil-init store 0.526 (14%) + epilogue load 0.262 (7%) + THE CALL/RET PAIR 2.984 (79%). franka-29 was right that the helper body is cheap -- that body costs 0.879 inlined; the cost is getting there and back. An inline nil-test at the call site takes it 3.772 -> 1.667, a 56% runtime saving with NO liveness. MEASURED 2026-09-07 BY TWO METHODS THAT FAIL DIFFERENTLY: ~98% of the swept slots are COMPILER-MINTED UNNAMED TEMPS, not locals anybody wrote -- 98.4% by direct count (ParseFactorCore: 10 named vs 609 unnamed tk=23 syms in the IR) and 98.2% by subtraction (757 released slots off the binary, 14 declared off the source). So per-path liveness over USER locals addresses 14 of 757 slots, 1.8% of the worst sweep, and cost (1) is a question about temps. NOT settled: whether temps can be skipped -- :13838's 'does not outlive the statement' is about the temp's VALUE, while the release loop needs a claim about OWNERSHIP of what it references, and skipping without that is a leak no value assertion catches. Note the prologue store is a THIRD cost that neither fix (1) nor (2) touches, and it is PER-SLOT ON ALL SEVEN TARGETS (measured 2026-09-07 by return-count separation, no disassembler needed) -- so one liveness analysis serves both halves. wasm32's release term is 0.062 B/slot/return, the first actual MEASUREMENT of its shared epilogue rather than an inference, and it still pays the full per-slot prologue. WARNING: the compiler's `code=` is page-quantised (65536 on aarch64, where it reads 196376 for both N=4 and N=532) and on wasm32 reports 3582 flat while the code section grows 13707 bytes -- use artefact size, never `code=`, for anything per-slot. WHOLE-PROGRAM, MODEL-FREE (2026-09-07): the thunked build compiles compiler.pas 2.04% and 2.51% faster than the inline build across two runs -- the SAME PROGRAM built two ways, cmp-gated so a pair can never be reported for builds that disagree. That is the -31.9% size win showing up as SPEED, with the call/ret cost INSIDE the figure rather than absent from it; it does not decompose them and nothing here lets it. Found from the Track P ticket perf-p-parsefactorcore-walks-a-92-arm-name-chain-per-factor, whose premise this refutes for the third time."
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

## 2026-09-07 — i386 joins the thunk, and building the constant WRONG is how I learned no test can see it

Second backend, second commit. i386 shares x86-64's `E9`/`E8`/`C3` rel32
encodings, so it shares the placement code; what it does NOT share is the stack
compensation, and the tree warned about exactly that before I could get it
wrong. `EmitSharedThunkPrologue` (symtab.inc:12870) already computes this
arithmetic for the init/fini thunks and says in as many words: *"Same reasoning
as the x86-64 arm, different arithmetic — do not copy the constant."* A `call`
pushes 8 bytes on x86-64 and 4 on i386, so the compensation is `sub rsp,8` and
`sub esp,12` respectively.

**Verified on i386 by RUNNING it, not by cross-compiling and hoping** — this box
executes i386 ELF, so `test_managed_sweep_thunk` ran natively: `SWEEPTHUNK OK
ok=80000 caught=5000`, census `allocs=40103 frees=40101 live=2`, identical to
the x86-64 run in every digit, and identical before and after the change while
the binaries differ. Flat for the right reason, on the target that changed.

Step control: x86-64 output is **byte-identical** across this commit (9-0 on the
named files) — the commit touches i386 and only i386 — while i386 differs on 5
of 9. Both halves, as before.

### THE CONSTANT HAS NO GUARD BEHIND IT, AND I FOUND THAT BY BUILDING IT WRONG

Having written the constant carefully, I asked the question this file demands
about any value: **if the machinery did nothing, would the row still pass?** So I
emitted the x86-64 value (8) on i386 — misaligning every call the sweep makes —
rebuilt, and ran the test natively on i386.

`SWEEPTHUNK OK ok=80000 caught=5000`. Census `allocs=40103 frees=40101 live=2`.
**Identical in every digit, exceptions included.**

So the value is correct by the SysV contract that symtab.inc:12870 and
ir_codegen386.inc:3723 both state, and it is **not correct by measurement**. The
suite passing is not evidence for it and I will not write that it is. Three
independent reasons the corpus cannot reach it: the sweep's callees are
pxx-internal release stubs; neither backend emits a memory-operand
`movaps`/`movdqa` (the x86-64 hits are register-to-register, which has no
alignment requirement); and the external-call path re-aligns for itself with
`and esp,-16` instead of trusting what it was handed.

**This is not hypothetical, which is why the adjustment stays.** What would reach
it is a released interface whose `_Release` runs user code calling an external
function with aligned SSE — and symtab.inc:16362 already records that fault mode
verbatim for GTK/GLib callees. Keeping "the thunk body sees the stack the inline
sweep saw" is a cheaper invariant than auditing every transitive callee forever,
at 6 bytes once per thunk against −31.9%.

Filed as `bug-a-no-probe-can-see-the-sweep-thunks-stack-alignment-constant` with
a differential probe design that needs no inline asm (a refcounted `Destroy`
recording `PtrUInt(@local) mod 16`, compared between a thunked and a non-thunked
build, so there is no absolute expected value to collide with a do-nothing
default). **The argument for doing it BEFORE the remaining five targets rather
than after: each of those adds a constant of its own with the same blind spot.**

## 2026-09-07 — WHOLE-PROGRAM A/B: the thunked build is 2.0-2.5% FASTER, and that is the size win, not a free call/ret

The model-free number, run by frank-subcoord on frank-coord-core's pair. **No
model sits between this and the question** — the two binaries are the SAME
PROGRAM, `compiler/compiler.pas` at `50e25f5f0`, differing only in whether their
own managed-local sweeps are inline or thunked:

```
  A  11594364 bytes  sha256 228fe7725379ad42   compiled by the PRE-thunk compiler (sweeps inline)
  B   7895676 bytes  sha256 19bee89a03e635cf   compiled by the THUNKED compiler
```

Two runs, min-of-7, interleaved, on a verified-quiet box:

```
  run 1   inline 17.130s   thunk 16.780s   -0.350s   -2.04%
  run 2   inline 17.140s   thunk 16.710s   -0.430s   -2.51%
```

A's minimum reproduces to **0.01s** across two independent runs. Five of B's
seven samples fall below A's fastest, so the sign is not in doubt.

**THE AIMING, which is what makes it quotable.** `ab_time.sh` compiles the
workload with both binaries and `cmp`s the output BEFORE it times anything,
exiting 2 rather than reporting a pair for two programs that disagree. Since A
and B are the same program, any disagreement means something moved underneath
the run. It also warms the page cache for both before the first sample, which
matters because they differ in size by 3.7MB.

**WHY NOT `cc_base` VS `cc_thunk` DIRECTLY** (frank-coord-core's design, and the
confound I would not have separated): timing the pre-thunk compiler against the
thunked one conflates three things with the same sign — the I-cache effect, the
fact that the thunked compiler EMITS FEWER BYTES and so does less work per
compile, and the call/ret cost. Same-source/two-builds removes the second.

**WHAT THIS LICENSES, AND WHAT IT DOES NOT.** It licenses exactly one
comparison: *on a real 17-second workload, the footprint win exceeds the
call/ret cost, net -2.0 to -2.5%.* It is **not** evidence that the call/ret is
free — that cost is inside the figure. A later measurement of the call/ret in
isolation returning a POSITIVE number is consistent with everything here.

**Directionally consistent with the unattributed negative one section up.** The
size-matched site-count model went negative at 128 and 140 sites and was refused
on the grounds that a negative cost is not physical for a call/ret. A footprint
effect outrunning the call/ret cost is a mechanism that produces that sign.
Recorded as consistent-with, **not** as the explanation: the model still has an
effect nobody has attributed, and one real-world number agreeing with its sign
does not retire that.

**A FALSE ALARM WORTH RECORDING, because it nearly cost a clean run.** Mid-run,
a peer reported having rewritten `compiler/ir_codegen.inc` nine seconds in and
asked for the measurement to be discarded — the `/bin/sh`-reads-incrementally
hazard, correctly identified. The reasoning was valid at every step and the
referent was a different tree: their sync moved
`/home/neo/frank-coord-core/compiler/ir_codegen.inc` (inode 2114238, mtime
05:23:43) while the workload was `/home/neo/frank-subcoord/…` (inode 1728186,
mtime 04:33:19). Corroborated three ways: nothing under this checkout's
`compiler/` has an mtime after the run started, the reflog's last ref move
predates it by fifty minutes, and the `cmp` precondition passed. **A path is not
a file when every session has its own checkout** — and the near-miss was
discarding a good measurement, not keeping a bad one.

## 2026-09-07 — the sharing has LANDED on all six flat-code backends, and it makes the frame-size gate almost pointless

frank-coord-core. Six commits, one backend each, as the group required:
x86-64 `50e25f5f0`, i386 `3d7cde305`, arm32 `4a1a80184`, aarch64 `5f89103c9`,
riscv32 `b1554c59a`, xtensa Call0 `dde109a7a`. wasm32 is not a seventh and now
has its own ticket
([[refactor-a-wasm32-is-the-one-target-the-shared-scope-exit-sweep-cannot-be-ported-to-as-a-port]])
so it stops reading as pending work here.

**So cost (2) is done, and the threshold table above was measured against a
binary that no longer exists.** Re-measured on ONE instrument with ONE variable —
the same tree, the same `-S` disassembler, `TargetHasSweepThunk` forced to
`False` for the control build, so nothing but the sharing differs:

| `compiler.pas`, x86-64 | release sites | `code=` | artefact |
| --- | --- | --- | --- |
| sharing OFF (control) | 349,581 | 11,075,352 | 11,612,964 |
| sharing ON (HEAD) | **43,508** | **7,376,664** | **7,914,276** |
| | **-87.6%, 8.03x** | **-33.4%** | **-31.9%** |

**The control agrees with the table above to 0.07%** — 349,581 here against
frank-subcoord's 349,322, and the two instruments fail differently: theirs is
`objdump -D -b binary` counting maximal consecutive runs in a built artefact,
this one is the compiler's own `-S` counting `call loc_0x000000aa` in a fresh
build. Neither can produce the other's error, and the sharing-off number lands
where the pre-thunk measurement said it would.

### What that does to the threshold choice — it dissolves it

At the measured **+5.06 B/site**, applying the nil-test to EVERY release site:

| | sites | `.text` growth |
| --- | --- | --- |
| sharing OFF, every site | 349,581 | **+15.97%** (the table above said +15.81%) |
| sharing OFF, T=400 | 197,771 | +8.95% |
| **sharing ON, every site** | **43,508** | **+2.98%** |

**Full coverage behind the thunk is a third the size cost of the T=400 gate
without it, and covers 100% of sites instead of 56.6%.** The threshold was never
an efficiency choice — the table above says so explicitly, cost is strictly
linear in sites — it was a blast-radius cap on a 15.97% `.text` bill. That bill
is now 2.98%.

**So the frame-size gate should probably not be built at all**, and that is a
change to this ticket's own design section two above, which said T=400. A gate
costs: a threshold constant nobody can justify from a measurement, a second code
path at every release site, and a permanent question in review about which side
of it any given frame sits on. What it buys is 2.0 percentage points of `.text`
(2.98% -> ~0.98%) and it gives up 43.4% of the runtime win, which is the win the
whole ticket is about. **Recommendation: build it ungated, and keep the
threshold in reserve as a named constant only if the ungated build's measured
size cost comes in materially above the 2.98% predicted here.**

### The branch width is CLOSED, and it is structural rather than a distribution

I left this open as the number that could overturn the 2.98%: `5.06 B/site`
assumes a SHORT `je`, and a `je` out of rel8 range is 6 bytes rather than 2.
frank-subcoord settled it off the disassembly of the landed compiler
(`19bee89a03e635cf`), and the answer is not a frequency — **there is no shape in
which the branch is long.**

The emitted per-slot sequence is exactly two instructions, stride 12, eight in a
row:

```
41e21b:  48 8b 85 e0 ff ff ff    mov  -0x20(%rbp),%rax     7 bytes
41e222:  e8 6b 1f fe ff          call 0x400192             5 bytes
```

**The argument is already in `%rax`, so nothing sits between the test and the
call.** A nil-test skips exactly one 5-byte `call rel32` and nothing else, so the
displacement is 5 on every site in the binary, unconditionally. **That pins the
cost at exactly 5 bytes, not 5.06** — `test %rax,%rax` 3 plus a short `je` 2 —
and whatever the 0.06 was, it was not branch width.

**The near-miss is the more useful half and it is frank-subcoord's, recorded
because the wrong answer looked clean.** Gaps between consecutive release call
sites have median 12 but mean 43.3, with **7.23% exceeding 127 bytes**. Quoting
that as "7% of sites need a rel32" would have been a tidy answer to a different
question: those large gaps fall BETWEEN sweeps, with unrelated code in between,
and the `je` never spans them. **The stride between sites and the distance the
branch jumps are different quantities that coincide only inside a dense run.**
The 7.23% existed before the disassembly did, and the disassembly is what
stopped it.

**Site count corroborated a third time while they were in there:** 43,436 by
objdump against 43,508 by `-S`, 0.17% apart — the same pair of
differently-failing instruments that agreed to 0.07% on the sharing-off control.

So the only thing left unmeasured about the size cost is the ungated build
itself, and if it comes in materially above 2.98% the cause is something other
than branch width. Build it, then read the artefact — but the branch is no
longer a candidate explanation.

**Both seats that measured this are idle from here** (owner dropped the fleet to
two working seats with Track P the priority). Nothing above is half-done and
nothing is waiting on either of us: the sharing is landed on all six backends,
the threshold question is settled against building a gate, and the emitter for
the nil-test is unstarted. **Unstaffed, not blocked.**

## v408 CARRIES IT — it had been inert for five days (recorded 2026-09-12, frankuser)

Not a change to this ticket's work, a note about its REACH, because CLAUDE.md asks
for exactly this before anyone closes a compiler fix that `lib/**` depends on.

`50e25f5f0` landed **2026-09-07 04:23**. Pin **v407** was cut **2026-09-06
21:59** — six and a half hours earlier. So the -31.9% was real, measured, titled
and ticketed, and **every `$(PXX_STABLE)` consumer kept building with the old
emitter for the next five days and twenty-one hours**, until pin v408
(`9186a7d58`, binary `808076de24be`, 2026-09-12).

Measured from the committed pin bytes, not from a build log — the R E segment is
the whole of the delta:

                    v407 (51901941e)   v408 (9186a7d58)    delta
    R E  FileSiz    0xa89000           0x747000            -3,416,064  (-31%)
    RW   FileSiz    0x08253c           0x08972c               +24,560
    BSS  MemSiz     0x505f154          0x530f934           +2.8 MB
    strings         16,426             17,250                   +824

**Code fell while data, BSS and string count all ROSE**, which is what separates
this from a dropped section or a truncated write — the direction nobody checks,
since `bug-a-the-compiler-prints-ok-with-exact-byte-counts-for-an-output-it-failed-to-write`
makes a short write look like a clean one.

The tonnage differs from this ticket's own `11594364 -> 7895676` because 248
commits touched `compiler/` between the two pins and added code back. The -31%
measured pin-to-pin is therefore a LOWER bound on what the thunk delivered, not
a restatement of it.

Found by frankB, which is the part worth recording: it noticed a 29% shrink in
the pinned binary while the builtin sources in the same commit GREW by ~1,600
lines, could not attribute it from `readelf` (neither binary carries section
headers), and handed it over rather than either ignoring a favourable delta or
guessing at a cause. An unattributed improvement is the direction CLAUDE.md says
goes unchecked because it flatters whoever is holding it.

---

## 2026-09-22 (frankb-8e) — COST (1)'s CHEAP HALF IS BUILT ON x86-64: 4.367 -> 1.886 ns/slot, 56.8%, and the size bill came in at LESS THAN HALF what was predicted

The inline nil-test at the release call site, **ungated**, as the 2026-09-07
recommendation asked for. `EmitManagedLocalCleanup`'s `SXR_STR` arm only —
the scalar `AnsiString` local, which is the arm the 3.772 decomposition was
measured on. The variant, object, interface and array arms are untouched and
are a separate question (see *what this does not do*, below).

### What it emits

```
  mov  rax, [rbp+off]
  test rax, rax          <- 3 bytes
  je   .skip             <- 2 bytes, displacement 5 on every site
  call AnsiStrRelease    <- 5 bytes
.skip:
```

`EmitAcquireHeapLock`'s pattern verbatim, including the assert: the `je` is
**patched from the emitted length, never hand-counted**, and the call is
asserted to be exactly 5 bytes. That assert is not decoration — its own
neighbour's comment records that `jnz +10` over a store that grew to 7 bytes
is how the I/O unlock once landed a byte past its `ret`.

### The number, and it is within a point of the prediction

frank-subcoord's 2026-09-06 shape, reproduced deliberately rather than
reinvented so the rows line up: **N = 4 against N = 532 AnsiString locals,
exactly one assigned, 2,000,000 calls, min of 5 interleaved.** One source,
built by BOTH compilers — the subject is the code the compiler emits, not one
binary timed twice.

| leg | t(N=4) | t(N=532) | marginal |
| --- | --- | --- | --- |
| control | 0.233440 s | 4.845080 s | **4.367 ns/slot/call** |
| nil-test | 0.234876 s | 2.226693 s | **1.886 ns/slot/call** |

**56.8% off the per-slot cost. The ticket predicted 55.8%** (3.772 -> 1.667,
from the calibrated C model). The prediction was made from a model and holds
against the built emitter to within one point.

**The N=4 row is the control and it is flat** — 0.2334 against 0.2349, i.e.
where there are almost no slots to skip, the test costs nothing measurable.
A saving that showed up at N=4 as well would have meant the instrument was
measuring something other than the sweep.

**CARRY BOTH ABSOLUTE ROWS, DO NOT REPLACE ONE WITH THE OTHER.** My control
marginal is 4.367 where 2026-09-06 measured 3.821 on the same box. That is not
a regression and not a refutation: this run was taken with Track T tooling
live (load 6-9) and that one on an idle box. **The RATIO is what transfers
between box states; the absolute ns/slot is a property of the day.** Anyone
re-running should expect their own absolute and should compare the ratio.

### Size: +1.39%, against +2.98% predicted

`compiler/pascal26`, x86-64, same tree, one variable:

| | artefact | binary |
| --- | --- | --- |
| control (`ac7926db7`) | 8,541,420 | `38692871f17e` |
| nil-test | 8,660,348 | `0301d450c73b` |
| | **+118,928, +1.39%** | |

The 2026-09-07 recommendation was to build it ungated and **keep the
frame-size threshold in reserve only if the built artefact's cost came in
materially above 2.98%.** It came in at **less than half** of that. So the
threshold is not built, and the condition that would have justified building
it is now measured and not met. `T = 400` can be retired as a design option
rather than left as an open choice.

### Whole-program: 5.4%, and the spread is reported because the box was not quiet

Both compilers compiling the same `compiler/compiler.pas`, min of 7
interleaved: control **22.211 s**, nil-test **21.013 s**.

Per-round deltas: +13.1, +2.1, **-6.9**, +6.0, +4.5, +6.1, +2.4 percent. **Six
of seven rounds favour the nil-test and one runs the other way**, and both
legs drift upward together as the box loads. Min-of-N absorbs that, which is
why it is the statistic, but a 5.4% whole-program figure with one round of the
opposite sign is not a number to quote to three digits. **The per-slot row
above is the sharp one; this one is the honest end-to-end check that the size
cost does not eat the win.** It does not.

### Correctness

- **self-host fixedpoint: converged in 2 rounds.** Two rather than one is
  expected and is the evidence, not a warning: the emitter changed, so round
  one's output differs from the seed and round two is what proves closure.
- **Leaks, differentially, on five fixtures** — `allocs`/`frees`/`live`
  **identical on every row** between control and nil-test, *including the three
  fixtures named for leaking*. Those are the control that matters: their known
  leaks are unchanged, so the pass neither fixed nor worsened anything, which
  is exactly what "skip the call when the slot is nil" must do.
  This assertion class is not optional here and the reason is on this ticket
  already: a sweep that stops running does not corrupt, it just never gives
  memory back, and every output check still passes.
  Run BEFORE as well as after, on the same corpus: `live=5` afterwards alone is
  flat for an unknown reason.
- Three frontends probed by hand beyond the quick tier: `.npy` (`"a" * 3` ->
  `aaa 3`), `.c` (`c-ok 42`), `.pas` (`Concat` -> `abcd`).
- `tools/gate.sh quick`: **GREEN**, read from the log.

### A GUARD I WROTE THAT COULD NOT HAVE FAILED, recorded because it printed a scary word

The A/B script gated on both output binaries being self-reproducing and
printed `niltest: NOT self-reproducing`. **That row is meaningless and the
binary is fine.** The tree held the CONTROL sources during the A/B — that is
what made it a one-input, two-compiler comparison — so self-reproduction was
available to the control *by construction* and unavailable to the other leg
whatever it did. An assertion written from a prediction about what the run
would look like pins the prediction. The real fixedpoint evidence is `make`'s
own `converged after 2 round(s)` on the nil-test tree.

### What this does NOT do, stated so nobody reads it as more than it is

- **Cost (1) is not fixed.** The full sweep still RUNS on every return; this
  removes the cost of *asking* about a slot, not the asking. Per-path liveness
  is still unstarted and is still a question about compiler-minted temps
  (~98% of swept slots), not about user locals.
- **The prologue nil-init store is untouched** — 0.526 ns/slot, 14%, on all
  seven targets. Neither fix (1) nor (2) nor this reaches it.
- **x86-64 only.** The other five register backends emit their sweep through
  `EmitManagedLocalCleanupForTarget` and each needs its own arm, one per
  commit, with the other five byte-identical as the blast-radius bound — the
  method the thunk landing established.
- **`SXR_STR` only.** `SXR_VAR`, `SXR_OBJ`, the interface arm and the array
  element walk all still call unconditionally. Whether they are worth the same
  treatment is a measurement nobody has taken: the 3.772 decomposition is a
  string-slot number and does not transfer to a `PXXArrayReleaseImmediate`
  call that does real work.
- **NO FRAME-TIME CLAIM.** This is reported against its own baseline. Its share
  of a lekkerzeilen `roofs` frame is unmeasured — the 14.0% refcount row in
  `PROFILE-2026-09-21.md` is a `rijn` measurement and nobody has decomposed a
  roofs frame. `umbrella-lekkerzeilen-runs-at-15-fps` is **not met** and this
  does not move it toward met. Reporting a fraction of an 18x (or 9.4x) target
  would be arithmetically defensible and would tell the owner something true
  while leaving him expecting 15 fps.

## 2026-09-22 (frankb-8e) — i386 JOINS, and the blast-radius control is the whole method

Second backend, one commit, the method the thunk landing established: **the
five targets not being converted must come out byte-identical.**

| target | before -> after |
| --- | --- |
| x86-64 | IDENTICAL |
| arm32 | IDENTICAL |
| aarch64 | IDENTICAL |
| riscv32 | IDENTICAL |
| xtensa (`--platform=posix`) | IDENTICAL |
| **i386** | **changed, as intended** |

One fixture through all six, `sha256` before and `cmp` after. That control is
the reason this can be done one arm at a time without a full tier per step: if
a sixth object moves, the step is wrong rather than interesting.

### It is not a copy of the x86-64 arm, and the difference is the branch span

i386 passes the handle on the STACK, so the sequence is `push` / `call` /
`add esp, 4` and the nil test skips **twelve bytes** rather than five. So the
test costs **4 bytes per site here against 5 on x86-64** — `test eax,eax` is
2 bytes on i386 against 3 on x86-64 (no REX), and the jump is 2 either way.

**The twelve is never written down.** `PatchRel8` measures the real span, and
`CheckRel8` turns a span that outgrows a signed byte into a compile-time
refusal — which is exactly what `rel8.inc` was carved out to guarantee, after
a `jns` that grew to 181 bytes stored as -75 and faulted mid-instruction.

### Measured

- **Size**: `code=` 109001 -> 109065 on the six-frame fixture, **+64 bytes =
  16 sites x 4**, which is the per-site cost arriving exactly. The ELF file
  size is unchanged at 115064 because the segment padding absorbs it — **do
  not read artefact size on a small i386 program; read `code=`.**
- **Behaviour**: `cross=3` under `qemu-i386`, before and after.
- **Leaks, differentially, five fixtures under qemu-i386**: `allocs`/`frees`/
  `live` **identical on every row**, including the three named for leaking.
- `tools/gate.sh quick`: GREEN.
- Self-host fixedpoint: converged in 1 round — **one rather than two, and that
  is correct here**: the x86-64 emitter did not change, so the compiler's own
  bytes do not move and the seed is already the fixedpoint. The x86-64 step
  needed two for the opposite reason. A round count is a fact about which
  emitter moved, not a quality signal.

### NOT re-measured, deliberately

No ns/slot figure for i386. Every i386 binary in this tree runs under qemu, and
a qemu timing is a statement about the emulator's dispatch, not about the
hardware this would run on. The structural argument transfers — the callee's
first act is still a nil test, and the caller still pays a full call/ret to
reach it — and the number does not. Quoting a qemu-derived ns/slot beside the
x86-64 4.367 -> 1.886 would put two incomparable rows in one table.

### THE REMAINING FOUR ARE NOT ALL THE SAME DECISION, and xtensa/riscv32 need a size question answered first

arm32 and aarch64 are hosted-shaped and the trade is the same one x86-64 made.
**xtensa and riscv32 are the ESP targets, where image size is a tracked
constraint with its own open tickets**, and "+4-5 bytes per release site" is a
trade nobody has priced there. The x86-64 decision to go ungated rests on
+1.39% of an 8.5 MB artefact; that argument does not transfer to an image
measured in tens of kilobytes.

**So the next step for those two is a MEASUREMENT, not an emitter**: build a
representative bare-profile image and count its release sites first. If the
count is small the question dissolves; if it is not, the frame-size threshold
that x86-64 correctly retired may be the right answer *there* — and that would
be a target-specific decision with a measurement behind it, not the revival of
a retired global option.

## 2026-09-22 (frankb-8e) — arm32 JOINS, and clobbering the flags is free FOR AN ABI REASON

Third backend, one commit, same blast-radius control.

| target | before -> after |
| --- | --- |
| x86-64 | IDENTICAL |
| i386 | IDENTICAL |
| aarch64 | IDENTICAL |
| riscv32 | IDENTICAL |
| xtensa (`--platform=posix`) | IDENTICAL |
| **arm32** | **changed, as intended** |

### The flags clobber is settled by AAPCS, not by looking at the surrounding code

`cmp r0, #0` destroys the condition flags, and on a RISC target that is the
question this arm raises and x86-64/i386 did not have to answer twice. **The
answer is the ABI and it needs no inspection of what is around the site: the
sequence this branches over CONTAINS A CALL, and AAPCS does not preserve the
condition flags across one.** So anything the `cmp` could damage is already
damaged on the path that does NOT take the branch — which means it cannot have
been live across this point in the first place.

Worth writing down because it is not locally obvious: the nil path is exactly
the path that SKIPS the call, so "a call happens here anyway" reads as false
at a glance. It is true of the path that would have observed the difference.

### The branch span is not hand-counted, and that is the load-bearing part

It is three instructions today — `push {r1,r2,r3}` / `bl` / `pop {r1,r2,r3}` —
but `EmitCallProc` may emit a literal-pool form for a far target, and a
hardcoded `beq +2` would then land **inside** the sequence it was meant to
skip. The displacement is `PatchCodeRefSlot`'s own arm32 expression character
for character:

```pascal
Patch32(jzPatch, $0A000000 or ((((CodeLen - jzPatch) div 4) - 2) and $00ffffff));
```

so there is ONE spelling of this architecture's PC-reads-8-ahead arithmetic in
the tree rather than a second that drifts out of step with it. That is this
file's own sibling-spelling rule applied at write time instead of at
regression time.

### Measured

- **Size**: `code=` 240056 -> 240184 on the six-frame fixture, **+128 bytes =
  16 sites x 8** — `cmp` 4 + `beq` 4, arriving exactly. arm32 is the most
  expensive of the three so far (x86-64 5, i386 4) because fixed-width
  encoding has no cheap form of either instruction.
- **Behaviour**: `cross=3` under `qemu-arm`, before and after.
- **Leaks, differentially, four fixtures under qemu-arm**: `allocs`/`frees`/
  `live` **identical on every row**, including the two named for leaking.
- `tools/gate.sh quick`: GREEN.
- Self-host fixedpoint: converged in 1 round — correct, the x86-64 emitter did
  not move.

### THE CONTROL FOR THIS STEP IS AN EARLIER BINARY, and that is sound rather than convenient

The pre-arm32 compiler no longer exists in the tree, so the differential
control is the **x86-64-only** build saved during that step. Its arm32 output
is provably the pre state — **because the i386 step established by `cmp` that
arm32 came out byte-identical across it.** The blast-radius control from the
previous commit is what makes this commit's control legitimate; without it the
saved binary would be an assumption about a target nobody had checked.

### NOT re-measured, deliberately

No ns/slot figure, same reason as i386: arm32 runs under qemu here and a qemu
timing measures the emulator's dispatch. The structural argument transfers and
the number does not.

## THE NON-STRING ARMS ARE A TAIL, AND THE TICKET ALREADY HELD THE NUMBER

The "extend to `SXR_VAR`/`SXR_OBJ`/interface/array" question above can be
closed from data already in this file rather than by a new census.
`compiler/defs.inc`'s `TTypeKind` puts **tk 23 = `tyAnsiString`** (tk 22 is
`tyVariant`). The 2026-09-07 decomposition counted ParseFactorCore's swept
population as *"10 named vs 609 unnamed tk=23 syms"* — i.e. **the 98% figure
that motivated this whole ticket was already a count of ANSISTRING slots.**

So `SXR_STR`, which is the only arm these three commits touch, covers ~98% of
the swept population in the worst sweep in the compiler, and the other arms
are a ~2% tail. That does not make them wrong to do — a `PXXArrayRelease`
call does real work and its nil path may be worth more per site — but it
retires the idea that the string arm is a partial fix waiting on the others.
**It is the fix; the others are an increment.** Anyone picking them up should
re-derive the tk number before quoting this paragraph.

## 2026-09-22 (frankb-8e) — aarch64 JOINS, and the blast-radius table spent one run measuring nothing

Fourth backend, one commit. aarch64 is the cheapest arm so far and the only
one that raises no flags question at all.

| target | before -> after |
| --- | --- |
| x86_64 | IDENTICAL |
| i386 | IDENTICAL |
| arm32 | IDENTICAL |
| riscv32 | IDENTICAL |
| xtensa (`--platform=posix`) | IDENTICAL |
| **aarch64** | **CHANGED, as intended** |

### CBZ makes this the one arm with no ABI argument to make

x86-64 (`test`), i386 (`test`) and arm32 (`cmp`) all destroy condition flags
and all three need the same argument to license it — the skipped sequence
contains a call, and no ABI preserves flags across one, so nothing the test
could damage was live. **aarch64 needs none of it: `CBZ` tests and branches in
one instruction and does not write NZCV.** It is also the cheapest site:

| target | bytes per release site | why |
| --- | --- | --- |
| aarch64 | **4** | one `cbz`, no separate compare |
| i386 | 4 | `test eax,eax` (2, no REX) + `jz` (2) |
| x86-64 | 5 | `test rax,rax` (3, REX) + `jz` (2) |
| arm32 | 8 | `cmp` (4) + `beq` (4), fixed-width, no cheap form |

The patch expression is `exception_emit.inc:443`'s `cbz x0` pair character for
character (`$B4000000 or ((((CodeLen - jzPatch) div 4) and $7ffff) shl 5)`),
for the same reason the arm32 arm copied `PatchCodeRefSlot`: one spelling of
an architecture's branch arithmetic in the tree, not a second that drifts.

### Measured

- **Size**: `code=` 165200 -> 165264 on the six-frame fixture, **+64 bytes =
  16 sites x 4**.
- **The instruction is the one intended, decoded from the image**: the post
  build has **16 more `cbz x0,#+8` immediately followed by a `BL`** than the
  pre build (30 vs 14). `imm19 = 2` is the whole check — the branch clears
  itself and the `bl` and lands on the next slot, which is what a hand-written
  displacement would have got wrong the day `EmitCallProc` emits a far form.
- **The opcode count alone would NOT have shown this**: `cbz x0,#+8` occurs
  **92 times in the PRE image** (RTL code). The population already contains
  the pattern, so the readout has to be the delta *and* the followed-by-BL
  subset; a bare `grep -c` for the encoding would have answered 108 and meant
  nothing. Three independent arrivals at 16 (site count, +64 bytes, +16 pairs).
- **Behaviour**: `cross=3` under `qemu-aarch64`, before and after.
- **Leaks, differentially, FIVE fixtures under `qemu-aarch64`**:
  `allocs`/`frees`/`live`/`bytes`/`reuse` identical on **every field of every
  row**, including the three named for leaking.
- `tools/gate.sh quick`: GREEN.
- Self-host fixedpoint: converged in 1 round — correct, the x86-64 emitter did
  not move.

### THE FIRST RUN OF THIS TABLE WAS SIX COPIES OF ONE NATIVE BINARY

Worth more than the arm it was checking. The loop was written as

```
pascal26 cross.pas out.bin --target=$t
```

and **pxx reads the output positionally as `ParamStr(i+1)` and IGNORES every
argument after it** — silently, exit 0, with an `ok:` line. All six legs built
x86-64. `sha256sum` of the six "pre" images: **one distinct value.**

The table printed:

```
x86-64 IDENTICAL   i386 IDENTICAL   arm32 IDENTICAL
aarch64 IDENTICAL  riscv32 IDENTICAL   xtensa IDENTICAL
```

which is **five of the six rows I wanted to see**. The only row that could
expose it is the one that must CHANGE — so *the converted target's row is not
a result, it is this instrument's positive control*, and a blast-radius check
without it cannot fail. That is this file's own guard rule arriving in the
method I have been calling the whole point of doing one backend per commit.

**Second instance in the same session, same shape**: `--target=x86-64` (hyphen)
is `unknown option` — the spelling is `x86_64`. That leg failed loudly, and
because the loop wrote nothing, the `cmp` compared **two leftover files from
the broken run** and reported IDENTICAL. A `cmp` between two stale artefacts
is indistinguishable from a `cmp` between two fresh ones.

**Re-measured retroactively, and the CLAIMS were true**: building `cross.pas`
for `x86_64` with each landed compiler gives `19c98a5cc05f` (pre-x86-64
control) then `4409ff4b6238` for the x86-64, arm32 and aarch64 builds alike.
So the x86_64 row in the i386 and arm32 sections is correct — it was just not
established by the command that ran there. **A true claim and a void
instrument, which is the pair that never gets caught, because nothing about
the output looks wrong.**

Two things this changes going forward, both cheap:
1. **Assert the converted target CHANGED** before reading the five IDENTICAL
   rows. One line, and it is the only line that can fail.
2. **Assert every leg BUILT** (`|| echo FAIL`, and branch on it) and that the
   N pre-images are N distinct shas. A `cmp` is a comparison whose
   preconditions were never established.

## 2026-09-22 (frankb-8e) — THE ESP SIZE QUESTION IS ANSWERED, AND THE ANSWER IS THAT IT IS NOT A BLOCKER

The i386 and arm32 sections both say the next step for riscv32 and xtensa is a
**measurement, not an emitter**, because "+4 bytes per release site" had never
been priced where image size is tracked. Here it is.

### The instrument is the change itself, because the two cheaper ones were void

**A disassembly scan was tried first and discarded.** Decoding RISC-V `JAL`
out of the image and matching the target against `PXXStrDecRef` from the
`.map` answered **0 sites** — and its positive control answered **0 too**:
270 `JAL` words found, **none landing on any named symbol at all**, against
28 symbols in the map. A scan that cannot find a single known call is not
reporting zero, it is reporting nothing. (Two independent reasons, either
sufficient: far calls are `auipc`+`jalr`, and the map names only exports.)
**The "0 sites" it produced is exactly the answer the size argument wanted,
which is why it got a control at all.**

**What worked: emit a NOP at each `SXR_STR` site, build, read `code=`,
divide.** No branch arithmetic to get wrong, no symbol resolution, and the
delta *is* the count. Scratch only — inserted, measured, reverted.

### Measured, with the positive control stated first

| build | riscv32 | xtensa |
| --- | --- | --- |
| **positive control** — `cross.pas`, hosted, probe vs no-probe | +64 B / 4 = **16 sites** | +28 B / 2 = **14 sites** |
| `cross.pas`, `--esp-profile=bare` | +20 B / 4 = **5 sites** | +12 B / 2 = **6 sites** |
| `test_esp_bare_managed.pas`, bare | **0 sites** | **0 sites** |
| `test_esp_bare_assert.pas`, bare | **0 sites** | **0 sites** |
| `test_esp_stack_args.pas`, bare | **0 sites** | **0 sites** |

The 16 on hosted riscv32 is the same 16 the x86-64, i386, arm32 and aarch64
arms each found in that fixture — five instruments, five targets, one number.

**The three bare fixtures in the tree have ZERO string release sites**, so on
every bare program that exists today the cost of this change is **zero bytes**.
That is a fact about the fixtures and not a licence, which is why the row that
decides it is `cross.pas`.

### The price, and the density bound that makes it safe

`cross.pas` under bare is 5 sites in a **12,400 B** image on riscv32 and 6 in
**10,140 B** on xtensa. At 4 B/site that is **0.16%** and **0.18%**.

| program | sites per 1000 B of code | cost of the test |
| --- | --- | --- |
| `compiler.pas`, x86-64, thunked | **5.90** | 2.95% of code (measured artefact: +1.39%) |
| `cross.pas`, bare riscv32 | 0.40 | 0.16% |
| `cross.pas`, hosted riscv32 | 0.06 | 0.02% |

**`compiler.pas` is the density BOUND, not a comparison** — it is the most
managed-local-dense program in the tree by a wide margin, and the x86-64
decision to go ungated was taken at that density. A bare ESP image is **15x
less site-dense**, because the bare RTL contributes essentially none of them:
the sites come from the application's own string locals, so an ESP program
pays in proportion to how much it uses strings and nothing for having linked
an RTL. **No program can be denser than the densest one we have, and at that
density the bill was already accepted.**

**So the ESP-specific gate is not needed and the frame-size threshold stays
retired.** The hold was correct — the number did not exist and the hosted
argument did not transfer — and the measurement now says the hosted answer
happens to be the conservative one.

**What would reopen this:** a real ESP application, not a fixture, whose site
density approaches `compiler.pas`'s 5.90/1000 B. Nothing in the tree is close,
and the honest limit on the row above is that `cross.pas` is fifteen lines —
it prices the MECHANISM at a known density, it does not predict an app.

## 2026-09-22 (frankb-8e) — riscv32 JOINS, and I ran the blast radius against a binary the tree said nothing about

Fifth backend. RISC-V compares and branches in one instruction and has **no
condition codes at all**, so like aarch64's `CBZ` there is nothing to clobber
and no ABI argument to make — only x86-64, i386 and arm32 need one.

| target | before -> after |
| --- | --- |
| **riscv32** | **CHANGED — read first, it is the positive control** |
| x86_64 | IDENTICAL |
| i386 | IDENTICAL |
| arm32 | IDENTICAL |
| aarch64 | IDENTICAL |
| xtensa (`--platform=posix`) | IDENTICAL |

All six legs asserted BUILT; the six pre-images asserted **6 distinct shas**.
Both assertions are new this commit and both come from the previous section.

### The encoder is reused because it carries the refusal

`EncodeRISCVBEQ` already holds `RISCVRelCheck(offset, -4096, 4094)`, so a call
that outgrows a B-type immediate is a **compile-time refusal**, not a truncated
offset. That is not hypothetical here: `IR_JUMP_IF_FALSE`'s own comment records
a lone `beq` silently truncating and landing inside unrelated code — *"chess
perft counted 164"* — which is why that site emits `bne`-skip + `jal` instead.
A release site spans one call, so `beq` is right; the guard is what makes it
safe to keep being right.

### Measured, and it matched a prediction made before the emitter existed

| | predicted by the NOP probe | delivered by the emitter |
| --- | --- | --- |
| hosted riscv32, `cross.pas` | 16 sites | `code=` 267884 -> 267948 = **+64 = 16 x 4** |
| bare riscv32, `cross.pas` | 5 sites | `code=` 12400 -> 12420 = **+20 = 5 x 4** |

The pricing section above counted sites by emitting a NOP and dividing. The
emitter then delivered exactly those counts at 4 B each. **A prediction made
by one instrument and confirmed by a different one**, which is worth more than
either number alone.

- **Behaviour**: `cross=3` under `qemu-riscv32`, before and after.
- **Leaks, five fixtures under `qemu-riscv32`**: identical on **every progress
  line**, not merely the final row — the census prints a running
  `allocs/frees/live` and all ~400 lines match per fixture.
- `tools/gate.sh quick`: GREEN.

### THE CONTROL BINARY WAS THE SCRATCH EXPERIMENT, AND ONLY THE BLAST RADIUS SAW IT

The first run of this table said **`xtensa CHANGED`** — a target this commit
does not touch. It was not a breach. **`cp compiler/pascal26 <control>` had
copied the NOP-probe build**: I reverted the probe SOURCE with `git checkout`,
committed, and never rebuilt, so `git status` was clean and
`compiler/pascal26` was still the experiment. The xtensa row moved because the
*control* had probe NOPs in it, and the riscv32 row was contaminated the same
way — **its number would have been the probe's NOPs plus my branch, reported
as my branch.**

CLAUDE.md names this exactly — *"a clean tree is not evidence about the
binary"* — and lists five routes to a stale one. **This is a sixth: reverting
an experiment's source without rebuilding.** It is nastier than a stale pull
because the tree is not merely old, it is *correct*, and the binary is a
deliberate experiment that no longer has any source backing it. Nothing in
`git status`, `git diff` or the stamp can see it: the stamp said
`sources match it` about sources that did match — **of the NEXT build.**

**What caught it was the row that had no business moving.** A single-target
before/after would have read the contamination as the change. That is the
second thing the five IDENTICAL rows have now caught that the converted row
could not, and it is the opposite direction from the previous section: there
the instrument was dead and printed agreement, here it was live and printed a
disagreement that was real and not mine.

**Discharge, added to the two from the previous section**: after reverting any
experimental source, **rebuild before copying the binary anywhere**, and print
`sha256sum` of the control beside the number it produced. The control here was
`b47aec0b26be` when it should have been `2c5b821bbf05`, and one printed sha
would have said so before the first `cmp` ran.

## 2026-09-22 (frankb-8e) — xtensa JOINS, ALL SIX ARE DONE, and the NOP probe that priced this was WRONG on this target

Sixth and last backend. `BEQZ` needs no scratch and no flags — xtensa has no
condition codes either — and at **3 bytes it is the cheapest site of the six**.

| target | before -> after |
| --- | --- |
| **xtensa** | **CHANGED — the positive control** |
| x86_64 / i386 / arm32 / aarch64 / riscv32 | IDENTICAL |

Six legs asserted BUILT, six distinct pre-image shas, control sha printed and
checked (`e5a13a7cfa8a`) before the first `cmp` — the three discharges from
the two sections above, all fired.

### The encoding came from the assembler, not from the ISA document

`BEQZ` is BRI12, not BRI8 — no `t` field, so a 12-bit displacement.
`xtensa-esp32s3-elf-as` assembles `beqz a2, .+9` to `16 52 00` = `$005216`:
op0=6, n:m=1, s=2, imm12=5 = 9−0−4. Two instances at different PCs both give
`imm12 = target − pc − 4`, the same +4 bias `EncodeXtensaBranch` already
applies. `EncodeXtensaBEQZ` lives beside its siblings in `xtensaenc.inc` and
carries `XtensaRelCheck(offset−4, −2048, 2047)`, because that file exists over
an esp32s3 image whose entry `j` wrapped and landed mid-instruction.

### THE PRICING PROBE WAS WRONG ON XTENSA, IN BOTH DIRECTIONS, AND IT LOOKED RIGHT

The section above priced this change by emitting a NOP at each site and
dividing the `code=` delta. **On riscv32 that was exact** — it predicted 16
hosted and 5 bare, and the emitter delivered `+64 = 16 × 4` and `+20 = 5 × 4`.

**On xtensa it was wrong both times.** Counted with the real disassembler:

| | NOP probe said | actually |
| --- | --- | --- |
| hosted xtensa, `cross.pas` | 14 | **16** |
| bare xtensa, `cross.pas` | 6 | **5** |

**The cause is that the probe assumes a fixed-width ISA.** `nop.n` is 2 bytes
in a stream of 3-byte instructions, so inserting *n* of them moves alignment
padding by an amount that is not a function of *n*: measured, hosted lost 4
bytes of padding and bare gained 2. The real emitter shows the same noise —
`code=` 217068 → 217108 is **+40 for 16 × 3 = 48**, and 10140 → 10156 is
**+16 for 5 × 3 = 15**. **Neither delta divides by the instruction width, so
byte arithmetic cannot count sites on this target at all.**

**Why it survived:** it produced *plausible near-misses*, not absurdities —
14 against 16, 6 against 5. A number that is nearly right is the one nobody
re-derives. What exposed it was that **every other target found exactly 16 in
this fixture**, five instruments agreeing, and xtensa alone dissenting by two.

**The correction does not move the decision, and it moves it the safe way:**
bare xtensa is **5** sites × 3 B = 15 B on a 10,140 B image = **0.15%**, where
the pricing section claimed 0.18%. It was pessimistic, not optimistic. The
`608e0f53c` table's riscv32 rows stand as measured; **its two xtensa rows are
superseded by the disassembler count and both rows are kept here** rather than
one being overwritten, because they measured different things — one counted
bytes, one counted instructions.

**Generalised, and the variable-width ISA is the MECHANISM rather than the
class** (frankz-e5's sharpening, and it is better than how I first wrote it):
the class is **the error was small enough to look like a measurement.** 14
against 16 is not an absurdity that announces itself; it is a plausible
reading, and a number that is nearly right is the one nobody re-derives. A
NOP-delta site count happens to be valid only on a fixed-width ISA — that is
the local rule — but near-miss-shaped error is what makes any instrument
survive.

**AND THE THING TO ARRANGE, NOT MERELY TO AVOID:** what exposed it was
**five instruments agreeing and one dissenting by two**, which was only
available because this fixture is built for six targets. **A single-target
measurement of the same kind has no dissent to notice** — the near-miss just
stands as the answer. The redundancy was there for the blast-radius bound and
paid a second time as an oracle; that is a reason to prefer a measurement
that runs on every target even when the question is about one.

### VERIFIED BY RUNNING IT — and the comment that said that was impossible was mine, for an hour

I wrote *"the one target nothing here can run"* into the emitter, and into the
encoder, as the reason the verification had to be byte inspection.
**`tools/esp_run_bare.sh` boots a bare image under Espressif qemu on both
chips and has all session.** Both comments are corrected in this commit. The
claim was never measured; it came from `--list-targets` saying xtensa does not
run on this host, **which is true about a raw ELF and false about the bare
profile under the vendor emulator.** An instrument answering correctly about
something adjacent, believed about the thing.

**TWO THINGS MADE IT WORSE THAN AN ORDINARY MISREAD, and the second is why it
is recorded here rather than shrugged off.** It went into **COMMENTS**, which
outlive the session and get obeyed without a re-measure — the durable half of
the damage was never the wrong belief, it was the wrong belief written where
the next reader inherits it. And it was a claim that something **CANNOT** be
done, which **produces no signal when believed**: nobody tries, nothing fails,
and the belief holds indefinitely. That is this file's own *"a stale warning
decays like a LOCK, silently, in the direction of doing nothing"*, arriving in
a comment I wrote myself an hour earlier.

### The suite avoided the shape, exactly as it did before 2026-09-20

**All three bare fixtures in the tree emit ZERO string release sites** — the
`SXR_STR` arm, the one every backend's nil test touches, had no bare coverage
at all. That is the same finding the managed-record rows above record for
`PXXRecordRelease`, in the same file, one fixture later.

**This is a RECURRENCE in one place, which is the test that promotes
something** — the same hole, in the same Makefile block, one fixture earlier,
for a different release arm. A suite that avoids a shape certifies its
absence, and this block has now done it twice.

`test/test_esp_bare_string_locals.pas` is new and wired into the bare target
beside its sibling. It contains **both sides of the branch deliberately**:
four assigned locals (falls through, release runs), four never-assigned (nil,
branch taken), and a mixed frame with **the live one LAST** — so it cannot
pass with the branch inverted, nor with a sweep that stops at the first nil.
12 `beqz a2` sites on bare xtensa against 0 in all three older fixtures.

- **Runs**: bare xtensa (esp32s3) and bare riscv32 (esp32c3) under qemu both
  print `acc=1100 / strlocals ok`, byte-identical to the x86-64 oracle, under
  the control compiler and the new one alike. 1100 is independently derivable
  from the source: (20 + 0 + 2) × 50.
- **Disassembled**: all 16 hosted sites are `beqz a2, X` where X is exactly
  the instruction after a `call0` to one callee — the branch clears itself and
  the call and lands on the next slot.
- `tools/gate.sh quick`: GREEN — **and it is the THIRD run that is quoted.**
  The first went green too, and I had edited two comments in
  `ir_codegen.inc` while it was running. The binary came out byte-identical
  (`d59755743109` both sides — comments do not move code), so the green was
  almost certainly sound; it is re-run anyway from a settled tree, because
  *"no row is trustworthy on the strength of the rows around it"* and a green
  whose tree moved under it is not a green anyone can quote later. A third run
  follows the removal of a dead `xtensa_beqz` wrapper (see below), and that
  one is the verdict here.

### A WRAPPER WRITTEN FOR SYMMETRY WAS DEAD ON ARRIVAL, AND THE BINARY PROVES IT WAS CARRIED

Every other branch in `xtensaenc.inc` comes as an `Encode…` / `xtensa_…`
pair, so I wrote both. **`xtensa_beqz` had exactly one occurrence in the
tree: its own definition.** This branch is always *patched* after the span it
skips has been emitted, so the only caller wants the WORD, not an emit —
`EncodeXtensaAddmi` is the in-file precedent for an encoder with no wrapper.

It is removed, and **the compiler binary changed when it went**
(`d59755743109` -> `38c84a7325ea`), which is the interesting part: it was not
elided, it was being emitted and carried. The compiler's *output* is
unaffected — all six targets byte-identical across the removal, and the bare
xtensa fixture still prints `acc=1100`. **Dead code written for symmetry with
its neighbours is the kind a reviewer reads past**, because it looks exactly
like the four things above it.

### ALL SIX BACKENDS NOW CARRY IT

| target | B/site | nil test | flags argument needed |
| --- | --- | --- | --- |
| xtensa | **3** | `beqz a2` | none — no condition codes |
| aarch64 | 4 | `cbz x0` | none — CBZ does not write NZCV |
| riscv32 | 4 | `beq a0, x0` | none — no condition codes |
| i386 | 4 | `test eax,eax` + `jz` | System V: skipped span contains a call |
| x86-64 | 5 | `test rax,rax` + `jz` | System V: same |
| arm32 | 8 | `cmp r0,#0` + `beq` | AAPCS: same |

**Three of the six needed an ABI argument and three needed none**, and the
split is exactly whether the architecture has condition codes. The measured
runtime win remains the x86-64 one — **4.367 → 1.886 ns/slot, 56.8% against a
55.8% prediction** — and no other target has a ns/slot figure because every
one of them runs under emulation here.
