---
track: A
prio: 25
type: bug
status: open
found: 2026-09-19
found-by: frankS
blocked-by: []
summary: "On one NilPy program (test/test_dce_nilpy_esp_kept_body.npy, --platform=esp) --dce leaves riscv32 with 870 live bodies / 2,065,508 B of code and xtensa with 735 / 1,721,263 B -- 135 bodies and ~344 KB more on riscv32, from the same source and the same live set to begin with. The measured asymmetry upstream of that is stub targets: before the kept-body fix landed, --dce-report named 71 bodies `kept (holds a stub target)` on riscv32 and ZERO on xtensa, and those 71 are now roots (correctly -- something jumps into them), dragging their callees live with them. So the question is not DCE's: it is why riscv32 codegen puts a CodeRef target INSIDE 71 procedure bodies where xtensa puts none. A stub target inside a body is a root by construction, so every one of them is a body no program can ever drop. PRICED 2026-09-20 by `--dce-why`: on the nilpy-c3 demo riscv32 has **143 stub targets of which 139 land inside a body**, rooting **819,480 B across 128 bodies** as `holds a stub target` -- 39.6% of its live code -- while xtensa has 4 stub targets, NONE inside a body, and 0 B rooted that way. ANSWERED 2026-09-20 (frankS) AND IT IS NOT A BLIND PASS: the in-body targets are MANAGED-LOCAL SWEEP THUNKS, which `EmitProcScopeExitCleanupForTarget` places after a body's second return (>=3 releasable slots) and calls through `EmitRiscv32CallToCode`/`EmitXtensaCallToCode` -- both of which record unconditionally on both arms. `TargetHasSweepThunk` excludes WINDOWED xtensa (sp is constant and a0 is the live return address, so a thunk has nowhere to put either), so the sweep is inlined at every return and no in-body target exists. Measured on `test/test_dce_sweep_thunk_abi.pas`, same ISA and source with one flag varied: riscv32 and **call0 xtensa** each report 1 in-body target, windowed reports 0 -- the asymmetry moves with the ABI and nothing else. So riscv32's 819,480 B is correct and both ISAs behave correctly. WHAT SURVIVES is an optimisation, not a bug: `DceRangeHoldsStub` roots a body for a stub target it OWNS, and since `DceOwnerOf` already knows the owner, an owned thunk could be treated as an intra-body reference -- which would make riscv32 match xtensa without disabling anything. Plus two latent items: `exception_emit.inc:710` records nothing where its riscv32 sibling at :510 does, and `IREmitCodeCall` falls through to an x86 `E8` on riscv32/xtensa instead of refusing. RE-LANED as correctness/optimisation; the SIZE half is answered 'working as designed' and this is NOT SRAM work."
---

# riscv32 DCE keeps 135 more bodies than xtensa on one program

Found while measuring `--dce` on both ESP chips for
`bug-a-dce-drops-a-called-body-on-the-riscv32-idf-profile`. It is a SIZE
question, not a correctness one: both images run, and both are correct.

## The numbers

Identical source, `--platform=esp --no-signals`, HEAD 2026-09-19:

```
riscv32   bodies 1921  live 870 (2062108B)  dead 1047   code 2988348B -> 2065508B
xtensa    bodies 1924  live 735 (1708063B)  dead 1185   code 2893079B -> 1721263B
```

Before the kept-body fix, with the SAME live set of 735 on both:

```
riscv32   71 x `dce: kept (holds a stub target)`
xtensa     0
```

## Where to look

`RecordCodeRef` (emit.inc) and `IREmitCodeCall`: which runtime stubs each
backend reaches by code offset rather than by proc index, and why riscv32's
land inside procedure bodies. `DceRangeHoldsStub` is what turns that into a
root, and that part is correct -- a body something jumps into cannot be
dropped.

**Do not "fix" this by dropping the root.** The asymmetry is the finding; the
root rule is what keeps the pass honest.

## 2026-09-20 (frankS) — the extra bodies are NAMED now, and they are 18% of the image

Same measurement as the pyeval rung: the live symbols of the two `--dce`
objects for `examples/esp32/nilpy-c3/main/main.npy`, diffed by NAME (a name is
ISA-neutral where a byte count is not).

```
riscv32 live symbols 840   xtensa 721
only in riscv32: 122 bodies, 381,416 B   <- 18.4% of riscv32's 2,074,812
only in xtensa :   3 bodies,   2,104 B
```

By unit: **87 from pylib.pas, 28 from pyeval.pas**, 2 pypal, 2 promocore, 3
unattributed. The largest are `PyDynMethL` (30,692), `PyClassRefNew` (11,420),
`PyBoundFnCallKw` (10,404), `pystr_encode_enc_err` (9,100), `sorted` (8,272),
`pyfloat_as_integer_ratio` (7,136), `pyvar_callv0` (7,040), `pyvar_callv1`
(6,344).

**`PyDynMethL`, `sorted`, `min`, `max`, `pymap_call`, `pyfilter_call` and the
`pyvar_callv*` family are exactly the names `--dce-report` printed as `kept
(holds a stub target)` on riscv32 before the kept-body fix landed** (71 of
them; xtensa printed none). So the 122 are that set plus what it drags live,
and the question is unchanged and now priced: **why does riscv32 put a CodeRef
stub target INSIDE these bodies where xtensa does not?** `IREmitCodeCall` is
shared code in `ir_codegen.inc`, so it is not a per-backend call site — the
difference is WHERE each backend's stub code lands relative to body ranges.

**The direction to rule out FIRST, because it inverts the conclusion:** if
xtensa emits a code-offset call without RECORDING a CodeRef, then xtensa's
smaller live set is not a win, it is a pass running blind — and a body it drops
could be one something jumps into. Establish which before treating riscv32's
extra 381 KB as waste. Neither backend file mentions `RecordCodeRef` directly;
both go through the shared helper, which is evidence for "where the stubs land"
and not yet proof.

## 2026-09-20 (frankS) — the root report prices it, and it does not answer the open half

`--dce-why` on `examples/esp32/nilpy-c3/main/main.npy`, both ISAs, same flags:

```
riscv32  stub targets 143, of which 139 land inside a body
         819,480 B / 128 bodies rooted `holds a stub target`  (39.6% of live)
xtensa   stub targets 4,   of which 0 land inside a body
         0 B rooted that way
```

Named, with the offset the target lands at inside the body:

```
BAddSigned +1280   BDivMod +4788   BShr +2896
PXXPromoFromStr +3544   SubSlowVV +2976   PXXPromoMod +2496
```

Those offsets are the useful new fact: a stub target 1,280 or 4,788 bytes into
a body is not a body ENTRY that a table happens to name — it is a jump into the
middle of compiled code, which is what `DceRangeHoldsStub` is right to treat as
un-droppable. **It also explains why this ISA's root report is less informative
than xtensa's**: this rule fires before the reachability walk, so on riscv32 the
FIRST reason for 128 bodies is the stub rule and the `@proc`/`PyBodyTramp` chain
that xtensa shows for the same code is invisible here. See
[[bug-a-a-static-nilpy-program-links-the-runtime-eval-interpreter]].

**The rule-out above is untouched by this** — the report counts CodeRefs, and a
call emitted without one is exactly what a CodeRef count cannot see. Do not read
"xtensa: 4" as "xtensa has 4"; read it as "xtensa RECORDS 4".

## 2026-09-20 (frankS) — ANSWERED, AND IT IS (a): THE PASS IS NOT RUNNING BLIND

The open half was binary and this closes it. **xtensa does not emit code-offset
calls without recording a CodeRef.** Its smaller live set is a consequence of
**`--xtensa-abi=windowed`**, not of the ISA and not of a blind pass.

### The mechanism

The only thing in the compiler that records a CodeRef whose target lands
*inside* a procedure body is the **managed-local sweep thunk**:

- `EmitProcScopeExitCleanupForTarget` inlines the sweep on the first return,
  and on the **second** return (with ≥ `SWEEP_THUNK_MIN_SLOTS` = 3 releasable
  slots) places an out-of-line thunk and calls it.
- The thunk is placed *after* that return, so its address is 1–5 KB into the
  body — which is exactly the `BAddSigned +1280`, `BDivMod +4788`,
  `BShr +2896` shape this ticket recorded.
- `EmitSweepThunkCall` routes riscv32 through `EmitRiscv32CallToCode` and
  xtensa through `EmitXtensaCallToCode`. **Both record, unconditionally, on
  both their short and long arms.**
- `TargetHasSweepThunk` (`ir_codegen.inc`) excludes windowed xtensa:
  `or ((TargetArch = TARGET_XTENSA) and (XtensaABI <> XTENSA_ABI_WINDOWED))`.
  The sweep is then inlined at **every** return, so there is no thunk, no call,
  no CodeRef, and no in-body target.

The exclusion is a real ABI constraint and not a gap: windowed keeps `sp`
constant so a thunk cannot adjust it, and `a0` is the live return address —
`call0` would clobber it and `call8` would rotate the window away from the
frame pointer the sweep addresses through.

### The measurement, which is what makes this an answer and not an argument

`test/test_dce_sweep_thunk_abi.pas` — three managed locals, two returns, wired
into `test-quick`. **Same ISA, same source, one flag:**

```
--target=riscv32                    stub targets 2, 1 inside a body   (F +760)
--target=xtensa --xtensa-abi=call0  stub targets 2, 1 inside a body   (F +604)
--target=xtensa --xtensa-abi=windowed  stub targets 1, 0 inside a body
```

**call0 xtensa behaves exactly like riscv32.** The asymmetry moves with the
ABI flag and with nothing else.

The obvious experiment — rebuild `nilpy-s3` with `--xtensa-abi=call0` and watch
the 344 KB gap close — **cannot be run on that program**: it answers
`target xtensa: addi immediate displacement 128 is outside the encodable range`
in `pyeval.pas`. The fixture is what carries the claim instead, and it varies
the ABI while holding ISA and source fixed rather than reducing the big
program, which is why it transfers.

### Consequences

1. **riscv32's 819,480 B / 128 bodies are correct, not waste.** Those bodies
   contain a thunk something calls, and `DceRangeHoldsStub` is right to keep
   them whole. Both ISAs are behaving correctly.
2. **Do not "fix" this by flipping the s3 demo to call0.** That would not make
   riscv32 smaller; it would make xtensa 344 KB bigger, and windowed is there
   for IDF interop.
3. **The real over-approximation is `DceRangeHoldsStub`'s GRANULARITY, and that
   is the residual worth having.** A sweep thunk is called by *its own body* —
   it is not an external entry point. The pass already knows the owner
   (`DceOwnerOf`), so a stub target whose owner is the calling body could be
   treated as an ordinary intra-body reference and the body dropped when the
   owner is dead. **That would make riscv32 match xtensa without disabling
   anything**, and it is the one change here that is a win rather than a
   trade. The ticket's own instruction stands: the root rule must stay for
   genuinely unowned targets.

### Two latent items found on the way, neither live

- `exception_emit.inc:710` emits `xtensa_call8(ExcLongJmpAddr - CodeLen)` raw
  and **unrecorded**, where its riscv32 sibling at `:510` goes through
  `EmitRiscv32CallToCode` and IS recorded. Harmless today — both endpoints are
  inside the runtime stub blob, which `EmitProgramPrologue` emits before any
  `BodyAddr` exists, so DCE never moves the distance between them. It is a
  policy divergence that would bite the moment anything in that blob became a
  body.
- `IREmitCodeCall` (`ir_codegen.inc`) has arms for arm32 and aarch64 and then
  an **unguarded x86 tail** — no riscv32 or xtensa arm. Safe today only because
  every caller reachable on those targets is behind an explicit `TargetArch`
  test. A new caller added to a shared `*ForTarget` routine would emit
  `E8 rel32` into an xtensa body. It should refuse rather than fall through.

**RE-LANE: this was filed as a SIZE ticket and the size half is now answered
"working as designed".** What survives is the granularity residual in (3),
which is an optimisation, and the two latent correctness items above. Not SRAM
work — see [[umbrella-an-esp32-image-is-as-small-as-it-can-be]], where code
removal is measured at zero SRAM from here.
