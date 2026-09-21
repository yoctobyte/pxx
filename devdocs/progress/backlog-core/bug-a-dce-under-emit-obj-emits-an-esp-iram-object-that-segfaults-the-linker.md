---
slug: bug-a-dce-under-emit-obj-emits-an-esp-iram-object-that-segfaults-the-linker
track: A
type: bug
prio: 60
status: backlog
created: 2026-09-21
found-by: frankb-8e
owner: ""
blocked-by: []
summary: >
  `--dce --emit-obj --platform=esp` on a source with an IRAM-attributed routine
  emits an object that makes GNU ld ITSELF crash: `collect2: fatal error: ld
  terminated with signal 11 [Segmentation fault], core dumped`. The object is
  malformed, so this is ours and not the linker's. BOTH ESP targets, riscv32 and
  xtensa, identically. The `ro` and `--no-ro-data` variants of the same fixture
  link cleanly on both with the same pass on, so it is the IRAM path
  specifically and not ESP or `--emit-obj` in general. PRE-EXISTING, not a
  regression: pin v415's binary reproduces it byte-for-byte, and it reproduces
  with an EXPLICIT `--dce`, so it is a shipping path rather than a consequence
  of any default. It is the reason `--emit-obj` still does not default the pass
  on: the i386 blocker that stopped that on 2026-09-19 was fixed 2026-09-21 and
  this was the next wall, found the same evening by turning the default on and
  running the tier. The symbol-surface measurement usually quoted in favour of
  the default (zero GLOBAL defined symbols lost, relocations roughly halved,
  x86-64/riscv32/xtensa) was taken on objects with NO IRAM section and says
  nothing about this case.
---

# `--dce --emit-obj` emits an ESP IRAM object that segfaults the linker

## Repro

    ./compiler/pascal26 --dce -Fulib/rtl --emit-obj --target=riscv32 \
        --platform=esp test/esp_obj_rodata_iram.pas /tmp/o.o
    tools/emit_obj_stub_shim.sh /tmp/o.o > /tmp/o.c
    riscv32-esp-elf-gcc -fno-builtin -nostartfiles -Wl,-e,main /tmp/o.c /tmp/o.o -o /tmp/o.elf
    # collect2: fatal error: ld terminated with signal 11 [Segmentation fault]

Drop `--dce` and it links. This is the `iram` arm of `test-emit-obj`'s
`.rodata` block, which runs **without** `--dce` today, which is why nothing saw
it.

## The matrix, measured 2026-09-21 at `497489e8a723`

Two targets x three variants of the same fixture x the pass on and off. The
variants are the tier's own: `ro` is `test/esp_obj_rodata.pas`, `ctl` is the
same source with `--no-ro-data`, `iram` is `test/esp_obj_rodata_iram.pas`.

| target | variant | `--dce` | `--no-dce` |
| --- | --- | --- | --- |
| riscv32 | ro | link ok | link ok |
| riscv32 | ctl | link ok | link ok |
| riscv32 | **iram** | **ld SEGFAULT** | link ok |
| xtensa | ro | link ok | link ok |
| xtensa | ctl | link ok | link ok |
| xtensa | **iram** | **ld SEGFAULT** | link ok |

**Four clean rows per target are the control.** They hold the pass, the
platform, the writer and the shim fixed and vary only the IRAM section, so
"`--dce` breaks ESP objects" is refuted by the same run that finds this.

## Not a regression, and not caused by the fix that uncovered it

    pin v415  (binary 94fddf62ee6a)   ld SEGFAULT
    pin v416  (binary fddc21e7e661)   ld SEGFAULT   riscv32 AND xtensa
    HEAD      (497489e8a723)          ld SEGFAULT

**Two pins, and the second is the CURRENT one.** v415 was the pin when this was
found; v416 landed the same evening and was re-measured against rather than
letting the v415 row go unquotable. Both reproduce on both ESP targets, so the
pin that ships today carries this.

Pin v415 predates `30898eef7` (the ProcAddrFix/DynCall compaction fix), so this
is older than that work and independent of it. It also reproduces with an
explicit `--dce`, so no default is implicated.

## Where to look first

`dce.inc` already treats IRAM as a distinct population — `IramCallFix` is its
own fixup table and `CodePosToIramOff` decides, per site, whether a relocation
belongs to `.rela.text` or `.rela.iram1.text` (elfwriter.inc, around the
`ProcAddrFixCount` loops near 3030 and 3157). A code offset that moves under
compaction while its IRAM mapping does not is the shape to suspect. Note
`CodePosToIramOff` is asked about a **post-compaction** `CodePos` in those
loops.

**A linker segfault means the ELF is malformed, so read the object before
reading the pass**: `readelf -SW`, `readelf -rW` and a relocation whose offset
falls outside its own section are the cheap first checks, and they say which
table is wrong without any theory about why.

## Why it matters beyond the tier

It is the standing blocker for defaulting `--dce` on under `--emit-obj`, which
is item (1) of
`bug-a-emit-obj-retains-pxxassert-so-one-ansistring-in-it-imports-the-whole-esp-pal`.
IRAM is not exotic on ESP — it is where anything latency-sensitive or
flash-cache-independent has to live — so this is a real path, not a fixture
curiosity.

## Positive control when a fix lands

The `iram` row must link on BOTH targets with `--dce`, **and** the four `ro`
and `ctl` rows must still link, so a fix that disables the IRAM path or the
pass wholesale is caught. Wire the `iram` variant into `test-emit-obj` with
`--dce` at that point; it runs without the pass today.
