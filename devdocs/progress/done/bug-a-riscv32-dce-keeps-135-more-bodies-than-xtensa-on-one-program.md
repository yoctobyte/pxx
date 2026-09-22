---
track: A
prio: 25
type: bug
status: open
found: 2026-09-19
found-by: frankS
blocked-by: []
summary: "CLOSED 2026-09-22 (frankb-8e) -- ALL THREE SURVIVING ITEMS LANDED. The optimisation this ticket specified is done (372dd5113): DceRangeHoldsStub answered on GEOMETRY, and now asks whether anything OUTSIDE the range refers to the target. A sweep thunk sits inside its own body and is called from that body alone, so every qualifying body pinned ITSELF. examples/esp32/nilpy-c3 riscv32 --platform=esp --dce: 2,093,100 -> 931,552 B, -55.5%, which puts riscv32 BELOW windowed xtensa (847,167 B) instead of 344 KB above it. Sound for a LOCAL reason and not a reachability argument: live body -> not removed -> the thunk survives with it; dead body -> its only caller is dead. The two latent items went earlier the same day (5fccc890a, 73b1ade90) and THIS TICKET PRESCRIBED THE WRONG HELPER FOR ONE OF THEM -- EmitXtensaCallToCode is the CALL0 helper, the stub is entered with a2 = &jmpbuf and ends in RETW and the site loads a10, so CALL0 passes the argument in the wrong register and retw rotates no window back; EmitXtensaCall8ToCode is the one, and the site also hardcoded a beq displacement the helper may invalidate, so fixing it as written would have made a latent bug live. THE VERIFICATION IS THE PART WORTH READING. A 116-program riscv32-under-qemu differential returned 116 same / 0 differ AND IS WORTHLESS: the positive control (disabling the root entirely) returned 116 same / 0 differ too, and the root fired for NONE of the 116 -- the population could not contain the subject. So the verification is an INVARIANT instead of a corpus: the live set must be closed under the call graph, now checked on every target across CallFix, ProcAddrFix AND CodeRef, where only wasm had such a check. Checking only CallFix would have passed this very commit, since DceRangeHoldsStub decides CodeRef targets. Positive control fires by name via a one-line forced drop in DceMark. NOT ESTABLISHED, and said out loud: `Result := False` -- the most aggressive possible predicate -- leaves every measurable artefact byte-identical and passes all three arms, so both True arms are unexercised in this tree; that BOUNDS the risk (the landed version roots a strict superset of one measured safe) rather than leaving it open. AND `D_EXPF` IS NOT A DEFECT -- the first version of the closure check read Procs[].BodyAddr AFTER the loop that remaps it and fired on riscv32 and windowed xtensa; reverting my other change reproduced it identically, which is a sound control for "did my edit cause this" and blind to "is my instrument sound". Also corrected: dce.inc claimed ApplyCallFixups reports a dropped-and-called body by name. It does not -- CallFixTarget is a clamped snapshot -- and that false all-clear is why five targets had no closure check. ORIGINAL ANALYSIS BELOW, still correct: the in-body targets are sweep thunks, the riscv32/xtensa asymmetry is an ABI consequence via TargetHasSweepThunk, and the SIZE half was answered working-as-designed."
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

## 2026-09-22 (frankb-8e) — THE OPTIMISATION IS DONE, THE TWO LATENT ITEMS ARE DONE, AND THIS CLOSES

All three of this ticket's surviving items are landed. Taking them in the order
the summary lists them.

**The optimisation, exactly as this ticket specified it** (`372dd5113`).
`DceRangeHoldsStub` answered on GEOMETRY — any stub target inside a body rooted
that body. It now asks whether anything OUTSIDE the range refers to the target,
which is the question the root was always asking. A sweep thunk is placed inside
its own body and called from that body alone, so every qualifying body pinned
ITSELF.

| | before | after |
| --- | ---: | ---: |
| `examples/esp32/nilpy-c3` riscv32 `--platform=esp --dce` | 2,093,100 B | **931,552 B** |

**−55.5%**, and riscv32 now lands *below* windowed xtensa's 847,167 B rather
than 344 KB above it. Windowed xtensa is unaffected by construction
(`TargetHasSweepThunk` is false); x86-64 is unaffected in fact — 0 of 19 stub
targets land inside a body, so the sweep thunk it does emit is not reached by a
CodeRef there.

Sound for a LOCAL reason rather than a reachability argument, which is why it
needs no new analysis: the thunk lives INSIDE the range. Live body → not
removed → the thunk survives with it and `DceRun` re-aims the call like any
other CodeRef. Dead body → its only caller is dead → the thunk is dead too.

**The two latent items, fixed earlier the same day** (`5fccc890a`,
`73b1ade90`) — and the prescription for the first one named the wrong helper.
`EmitXtensaCallToCode` is the CALL0 helper; `ExcLongJmpAddr`'s windowed stub is
entered with `a2 = &jmpbuf` and ends in `RETW` and the site loads **a10**, so
CALL0 would pass the argument in the wrong register and `retw` with no window
rotated. `EmitXtensaCall8ToCode` is the one. It also had a half this ticket did
not see — `xtensa_beq(a2, a4, 9)` hardcoded a 3+3+3 byte count that the helper
is allowed to invalidate — so fixing it as written would have converted a
latent bug into a live one. Two further sites of the same family turned up in
the census afterwards.

## THE VERIFICATION IS THE PART WORTH READING, because the obvious one was void

**A 116-program riscv32-under-qemu differential of `--dce` against `--no-dce`
returned 116 same / 0 differ, and it is worthless.** The positive control —
disabling the stub root entirely — returned **116 same / 0 differ as well**, and
comparing the two sets of binaries shows the root fired for **NONE of the 116**.
The population could not contain the subject. A clean differential over a corpus
that does not exercise the change is not weak evidence, it is no evidence, and
it reads exactly like the strong kind.

**So the verification is an INVARIANT instead of a corpus** (`372dd5113`): the
live set must be closed under the call graph, checked on every target across all
three tables that can name a body — `CallFix`, `ProcAddrFix` and `CodeRef`.
Only wasm had such a check, and the asymmetry was an accident of its slot
INDEX being inexpressible for a dropped body; an ELF target expresses one
perfectly well, and `DceNewOff` CLAMPS an offset inside a removed range to that
range's start, so the reference does not go invalid — it becomes a confident
reference to whatever slid up. **Checking only `CallFix` would have passed this
very commit**, since `DceRangeHoldsStub` decides the fate of CodeRef targets.

**What is NOT established, stated here and in the source rather than left to be
found.** Replacing the predicate with `Result := False` — the most aggressive
version possible — leaves the nilpy-c3 object on both ISAs and
`--dce --emit-obj` **byte-identical** to the landed version, and passes all
three closure arms. So in this tree every in-body stub target is a
self-referenced sweep thunk and **both arms of the predicate that answer True
are unexercised**. That bounds the risk rather than leaving it open: the landed
version roots a strict superset of a version already measured safe.

**AND ONE INSTRUMENT FAILURE THAT NEARLY SHIPPED AS A BUG REPORT.** The first
version of the closure check read `Procs[].BodyAddr` AFTER the loop that remaps
it, comparing post-compaction offsets against pre-compaction ranges. It fired on
`D_EXPF`, on riscv32 **and** on windowed xtensa. I confirmed it was not my own
predicate change by reverting that and reproducing the identical message at the
identical code offset — which is a sound control for *"did my edit cause this"*
and structurally blind to *"is my instrument sound"*, the question actually in
doubt. Moving the check ahead of the remap: clean everywhere. **`D_EXPF` does
not exist as a defect.** Where a NEW instrument produces a finding, the
proposition in doubt is the instrument, and varying your own diff cannot reach
it.

**A FALSE SAFETY CLAIM IN dce.inc IS WHY THIS CHECK DID NOT EXIST.** The header
said a dropped body's `BodyAddr := -1` means *"ApplyCallFixups says so by name
instead of jumping into the hole"*. Measured false: with the guard removed and a
called body force-dropped, the compiler prints `ok:` and emits the binary.
`CallFixTarget` holds a resolved snapshot that `DceNewOff` clamps, so
`ApplyCallFixups` never consults the `-1`. Corrected in place — **a comment
explaining why a check is unnecessary is a guard with no positive control, and
it is read as the reason not to add one.**

Closing: every item in the summary is landed and the size half was already
answered "working as designed".
