---
prio: 45  # auto
---

# Register-based internal calling convention (args in registers, not stack slots)

- **Type:** feature (codegen — ABI-wide) — Track A
- **Status:** backlog
- **Opened:** 2026-07-03 (pin-time optimization campaign)
- **Umbrella:** the -O2 tier of [[feature-optimization-levels]]; split out
  because it is ABI-WIDE (every call site + every prologue must flip
  together) rather than a local pass.

## Motivation

PXX's internal convention on x86-64 today: every argument is pushed to the
stack, popped into rdi/rsi/... just before the call, and the callee's
prologue immediately SPILLS every register argument back into frame slots.
Each argument round-trips memory twice; the callee then reloads from the
frame on every use. FPC's register convention + register allocator is a big
chunk of the measured 2.04x generated-code gap (benchmark-compiler-runtime,
2026-07-03: FPC-built pascal26 compiles the compiler in 5.1s vs self-built
10.4s, identical source).

## Shape

- Keep the EXTERNAL SysV convention for cdecl/external as-is.
- Internal calls: first N integer/pointer args stay in registers end-to-end;
  the callee spills ONLY args whose address is taken (var-param source,
  @-taken, or referenced by nested/lifted routines) or that live across a
  call.
- This is a whole-program flag-day per target: land behind `-O2` (or a
  dedicated `--regcall`) so -O0 keeps the byte-identical debuggable model.
  Self-host gate becomes: pxx(-O0) byte-identical as today; pxx(-O2) built
  compiler passes full make test and fixedpoints against itself.
- Do x86-64 first (host, biggest pin-time payoff); cross targets follow the
  same IR-level liveness info later.

## Prerequisites

- Simple per-routine liveness/addr-taken analysis over the IR (also feeds
  [[feature-inline-routines]] eligibility and future register allocation).
- The -O flag plumbing from [[feature-optimization-levels]].

## Acceptance

Self-compile wall time drops measurably with -O2 (record in
benchmark-compiler-runtime); full make test green under a -O2-built
compiler; -O0 self-host byte-identical unchanged.

## Design worked out 2026-07-03 (arc scoped, not yet implemented)

**Current model (x86-64, mapped):** confirmed 2 memory round-trips + per-use
reload:
- Caller (ir_codegen.inc 3443-3523): eval each arg -> `push rax`; then pop into
  rdi/rsi/rdx/rcx/r8/r9 (round-trip 1).
- Callee prologue param spill (parser.inc 14480-14578): `mov [rbp+off], rdi/...`
  spills all 6 reg args to frame slots (round-trip 2).
- Param reads: `EmitLoadVar` skParam (symtab.inc ~2169) = `mov rax,[rbp+off]`
  every use.
- Param frame offsets: `AllocParam` (symtab.inc 1909-1979), `Syms[].Offset` neg.
- TParam (defs.inc 653-659): SymIdx/IsRef/IsArray/TypeKind/Name.
  TProc (661-671): Params[0..31], ParamCount, RetSymIdx, FramePatch.

**Chosen approach — callee-side register RESIDENCY via callee-saved regs.**
Park each non-pinned scalar param in a callee-saved register for the whole body
instead of a frame slot: kills the spill (round-trip 2) AND every per-use
reload. Caller stays UNCHANGED (still passes in rdi/rsi via push/pop) — half the
theoretical win, but far lower risk and self-contained. Callee-saved regs
survive calls by SysV ABI, so a resident param needs NO cross-call spill (the
key simplifier).

**Register budget (audited this session):**
- `r14`, `r15`: ZERO x86-64 uses anywhere in emitted code (grep: only arm32
  comments). Trivially safe — 2 param registers with no audit. **Phase-1 scope.**
- `rbx`, `r12`, `r13`: used ONLY inside self-contained runtime helpers
  (symtab.inc float/int formatters, heap alloc) that already `push`/`pop` them
  (callee-saved discipline honored). Reusable for params AFTER a full audit that
  EVERY such helper saves/restores them. **Phase-2 expansion.**

**The invariant that makes it safe:** every routine (and helper) that USES a
callee-saved reg must push it in prologue / pop in epilogue. Then: our helpers
preserve them (verified push/pop), external SysV callees preserve them (ABI),
and regcall routines preserve them (new prologue/epilogue). So a param in r14
survives any call. -O0/-O1 keep the current spill model untouched (gate
OptLevel>=2).

**Pinned (must stay in frame, never register-resident):** IsRef (var/out/const
by-ref), IsArray, float/record/set/variant types, any param whose address is
taken (an IR_LEA / IR_SLOTADDR in the body references its SymIdx), and params
captured by a nested/lifted routine (parser.inc 12505-12595). Everything else
(plain int/ptr/char/bool/enum scalar) is register-eligible.

## Phasing (each lands + self-host-gates independently, all behind -O2)

0. **Addr-taken analysis (prereq, no codegen change).** Per body at CompileAST:
   for each param of CurProc, eligible = scalar int/ptr, not IsRef/IsArray, and
   no IR_LEA/IR_SLOTADDR references its SymIdx. Verify by instrumenting counts
   over a self-compile = MEASURE the opportunity (how many params are eligible)
   before committing. (Also unblocks [[feature-opt-store-reload-elimination]].)
   NOTE: a first instrumentation attempt this session printed 0 — CurProc
   validity/timing at the probe site needs checking; the analysis itself is
   sound, the probe placement was off. Fix before trusting the number.
1. **r14/r15 residency (x86-64, -O2).** Assign up to 2 eligible params to
   r14/r15. Prologue: `push r14/r15` + `mov r14, rdi` (from the SysV incoming
   reg) instead of the frame spill. EmitLoadVar/EmitStoreVar skParam: emit
   `mov rax, r14` when resident. Epilogue: `pop r15/r14`. Gate every site
   OptLevel>=2 + a per-Sym "resident register" field (or a side table).
2. **Expand to rbx/r12/r13** after auditing the helpers save them (5 resident
   params total).
3. **Caller-side direct-eval** (optional, harder) — eval args straight into
   arg regs without the push/pop, reclaiming round-trip 1. Needs care (nested
   arg eval clobbers). Lower priority; measure whether phase 1-2 already closes
   most of the gap first.
4. Cross targets (aarch64 first) reuse the same eligibility analysis later —
   only if the host win justifies it (per user: x86-64 is the priority; cross
   optional).

## Risk / why it's a careful multi-session arc

The stack-machine codegen funnels everything through rax; residency works ONLY
because callee-saved regs are never used as scratch in normal codegen (verified
for r14/r15; helper-audited for rbx/r12/r13). Any emitted sequence that
clobbers a resident reg without saving = silent param corruption. So phase 1
must land minimally (r14/r15 only), full `make test` under a -O2-built compiler,
-O2 self-host fixedpoint, before expanding. -O0 byte-identity stays the anchor.

## Phase 0 MEASURED (2026-07-04) — opportunity confirmed large

`--measure-regcall` flag added (compiler.pas + `RegcallMeasureBody` in
ir_codegen.inc, called from CompileAST after IRLowerAST; flag-gated, zero
codegen effect). Eligibility = scalar int/ptr (`RegcallScalarType`: tyInteger,
tyBoolean, tyChar, tyClass, tyInt8..tyNativeUInt, tyPointer), not IsRef, not
IsArray, and no IR_LEA/IR_SLOTADDR in-body references its SymIdx.

Measured on the compiler self-compile (`--measure-regcall compiler/compiler.pas`):

| Metric | Value | % of params |
|---|---|---|
| bodies with params | 1262 | — |
| total params | 2625 | — |
| eligible | 2084 | **79%** |
| capture @ 2 regs (r14/r15, phase 1) | 1595 | **61%** |
| capture @ 5 regs (+rbx/r12/r13, phase 2) | 2053 | **78%** |
| eligible param loads+stores (reload traffic removed) | 7234 | — |
| addr-taken rejects | 0 | — |

- The prior false-zero was a probe-placement bug; this probe verified correct on
  a crafted `Bump(var x)` case (detects the 1 addr-taken param, keeps the
  by-value sibling eligible).
- **0 addr-taken is real**: the compiler source never passes a scalar value param
  by-address — so phase 1 can skip the addr-taken keep-in-frame path for the
  self-host workload (still implement it for correctness on arbitrary input).
- Phase 1 (2 regs) alone captures 61% of ALL params and removes most of the 7234
  reload memory ops. Phase 2 (5 regs) reaches 78% — diminishing return, so land
  phase 1 first and re-benchmark before expanding.

## Phase 1 DONE (2026-07-04) — r14/r15 residency behind -O2, x86-64

Implemented as a self-contained codegen change (NO parser reorder). Key
realization: the early prologue spill already writes each param's frame slot, so
a *deferred* `mov r14,[rbp+off]`-style reload — emitted in CompileAST after the
body IR is lowered (residency known), before IREmitMachineCode — reads a correct
value regardless of arg-register liveness. And nested routines *reject* capturing
enclosing params (parser.inc ~12525), so a param frame slot is never touched by a
nested routine → no capture hazard.

Design: frame slot stays authoritative (early spill + store dual-write via
`RegcallRefreshResident`, which reloads through EmitLoadVar to reuse the canonical
size/sign extension). The register is a pure read cache → any non-EmitLoadVar
reader and the excluded addr-taken cases stay correct; callee-saved regs survive
calls by ABI so there is no cross-call spill. r14/r15 caller values saved to a
reserved frame slot at body entry (FrameSize bump), restored in EmitProcEpilog
(every return path, early Exit included).

Files: `RegcallAssignResidency` + CompileAST hook (ir_codegen.inc);
`ResidentRegOf`/`RegcallRefreshResident` + EmitLoadVar/EmitLoadVarRcx/EmitStoreVar
resident hooks + epilogue restore (symtab.inc); `RcResident*` globals (defs.inc);
`--measure-regcall` (phase 0). Gated OptLevel>=2 + x86-64; excludes
generator/stackless routines and bodies with inline asm.

Gates: -O0 self-host byte-identical (unchanged); -O2 self-compile fixedpoint
byte-identical; -O2 differential corpus green; make test green + green under an
-O2-built compiler. `make test-opt` extended to gate -O2 differential + -O2
self-fixedpoint permanently.

Measured: self-compile **1.34x faster** (6.53s→4.87s, hyperfine, identical
output) and compiler code **12.2% smaller** (4.08MB→3.58MB) — from just 2
params/body. Closes a real chunk of FPC's ~2x lead.

**Pin policy — FLIPPED to -O2 (2026-07-04, user-approved).** Pins are now
-O2-built (regcall + inline). -O2 output is byte-identical-transparent (an
-O2-built compiler emits the same -O0 output as before), so B/C/D see identical
compiled output and just get a faster compiler. Pinned via
`make PXXFLAGS=-O2 stabilize && make pin`.

Status: **phase 0 + phase 1 DONE.** Next candidates (optional, measure first):
phase 2 (expand to rbx/r12/r13 after auditing helpers save them — reaches 78%
capture vs phase 1's 61%; diminishing return, re-benchmark first); phase 3
(caller-side direct-eval into arg regs); phase 4 (cross targets).
