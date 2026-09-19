---
track: A
prio: 25
type: bug
status: open
found: 2026-09-19
found-by: frankS
blocked-by: []
summary: "On one NilPy program (test/test_dce_nilpy_esp_kept_body.npy, --platform=esp) --dce leaves riscv32 with 870 live bodies / 2,065,508 B of code and xtensa with 735 / 1,721,263 B -- 135 bodies and ~344 KB more on riscv32, from the same source and the same live set to begin with. The measured asymmetry upstream of that is stub targets: before the kept-body fix landed, --dce-report named 71 bodies `kept (holds a stub target)` on riscv32 and ZERO on xtensa, and those 71 are now roots (correctly -- something jumps into them), dragging their callees live with them. So the question is not DCE's: it is why riscv32 codegen puts a CodeRef target INSIDE 71 procedure bodies where xtensa puts none. A stub target inside a body is a root by construction, so every one of them is a body no program can ever drop."
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
