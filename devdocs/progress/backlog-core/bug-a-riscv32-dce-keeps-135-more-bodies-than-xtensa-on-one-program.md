---
track: A
prio: 25
type: bug
status: open
found: 2026-09-19
found-by: frankS
blocked-by: []
summary: "On one NilPy program (test/test_dce_nilpy_esp_kept_body.npy, --platform=esp) --dce leaves riscv32 with 870 live bodies / 2,065,508 B of code and xtensa with 735 / 1,721,263 B -- 135 bodies and ~344 KB more on riscv32, from the same source and the same live set to begin with. The measured asymmetry upstream of that is stub targets: before the kept-body fix landed, --dce-report named 71 bodies `kept (holds a stub target)` on riscv32 and ZERO on xtensa, and those 71 are now roots (correctly -- something jumps into them), dragging their callees live with them. So the question is not DCE's: it is why riscv32 codegen puts a CodeRef target INSIDE 71 procedure bodies where xtensa puts none. A stub target inside a body is a root by construction, so every one of them is a body no program can ever drop. PRICED 2026-09-20 by `--dce-why`: on the nilpy-c3 demo riscv32 has **143 stub targets of which 139 land inside a body**, rooting **819,480 B across 128 bodies** as `holds a stub target` -- 39.6% of its live code -- while xtensa has 4 stub targets, NONE inside a body, and 0 B rooted that way. The counting is not the open part; the open part is whether xtensa is smaller because its stubs land between bodies or because it emits a code-offset call WITHOUT recording a CodeRef, which would make its smaller live set a pass running blind rather than a win."
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
