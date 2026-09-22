---
slug: bug-a-dce-under-emit-obj-emits-an-esp-iram-object-that-segfaults-the-linker
track: A
type: bug
prio: 60
status: done
created: 2026-09-21
found-by: frankb-8e
owner: ""
blocked-by: []
summary: >
  FIXED 2026-09-22 (frankh-c0). ROOT CAUSE: `DceRun` never compacted
  `IramCallFix` -- it appeared EXACTLY ONCE in dce.inc, in the MARK phase that
  roots an iram callee, while every sibling array (Fixups, GlobFix, CallFix,
  ProcAddrFix, DynCall, CodeRef, Procs[].BodyAddr) was remapped. Entries kept
  their PRE-removal CodePos; elfwriter splits them by `CodePosToIramOff`, so a
  stale CodePos misses the iram map, falls into the `.rela.text` arm and is
  written at an offset from the OLD layout. Measured, riscv32: two entries at
  0x3fd68 and 0x3fe74 against a `.text` of 0x8788 -- both inside the pre-DCE
  0x3ff70 -- and the `.rela.iram1.text` relocation for the `PXXStrDecRef` call
  at iram offset 0x50 dropped entirely. ld applies the first out-of-range entry
  and dies. NOTHING DOWNSTREAM COULD SEE IT because elfwriter COUNTS these
  entries with the same predicate it WRITES them with, so `sh_size` is honest
  about a wrong set and `readelf -r` prints entries that look ordinary one at a
  time. Fifth instance of this family's one omission, found by grepping dce.inc
  for the sibling. VERIFIED: both ESP targets, `--dce --emit-obj
  --platform=esp`, 0 out-of-range relocations and link rc=0 under the real
  esp-elf gcc against rc=1 signal 11 before; self-host fixedpoint converges;
  gate quick GREEN. GUARDED, so instance six is caught rather than rediscovered:
  `reloc_resolve_check.py --check-object` asserts that every relocation points
  inside the section it relocates -- an invariant that holds BETWEEN two
  structures, which is why no per-entry assertion and no `readelf -r` could
  express it -- with `tools/reloc_structure_devtest.py` as its positive control
  and a row in `test-emit-obj`. The ORIGINAL framing below is kept and is still
  the reason this mattered. Note the residue it does NOT close: the -O2
  promotion still needs five Makefile control arms respelled `--no-dce` and a
  full tier.
  THIS WAS THE GATE ON A MEASURED -66% ACROSS EVERY PROGRAM, WHICH ITS OWN TITLE
  HID (frankh-c0, 2026-09-22). Promoting `--dce` from `-O3` to the default
  `-O2` takes nine real `examples/**` programs from 4,424,828 to 1,475,708 bytes
  (-66%; hello -66%, raytracer -64%, maze -72%) and the self-host fixedpoint
  still converges, two rounds, on a 4978-proc compiler. It cannot land because
  the `-O` rule is unconditional on output mode, so the promotion turns the pass
  on for `--emit-obj` BY THE BACK DOOR even though `--emit-obj` has no
  defaulting line of its own -- and then a plain no-flags ESP object build goes
  from linking to crashing the linker. Measured with the LINKER's own exit
  status: DEFAULT rc=1 `ld terminated with signal 11`, `--no-dce` rc=0, code
  34,696 B against 262,000 B. So this is not one broken path under one flag; it
  is the single thing standing between every pxx program and a two-thirds size
  cut, and `bug-a-a-pascal-hello-world-is-63kb-after-emission-size-dce` is wired
  `blocked-by:` this so the ranker carries it. A SECOND, SMALLER COST is banked
  in the body and is paperwork rather than a defect: five Makefile rows use the
  DEFAULT invocation as their "without the pass" control arm, which the
  promotion silently makes meaningless; they assert a STRICT shrink so they fail
  loudly rather than certifying nothing. Original report follows.
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

---

## 2026-09-22 (frankh-c0) — THIS IS NOT AN `--emit-obj` FOOTNOTE: IT IS THE GATE ON A MEASURED -66% ACROSS EVERY PROGRAM

**What I was doing.** Working the emitted-size/DCE group from its `next` entry
point and testing the one live question the 63KB-hello-world ticket leaves open
— *"whether the DEFAULT -O level should enable the pass."* The way to answer
that is to turn it on and run the tier, so I did.

**PROMISE, measured at `19768262e`, compiler `c24a11f2beb3`, plexus.** One-line
change, `OptLevel >= 3` to `>= 2` in `compiler.pas`:

```
program            --no-dce     default      delta
hello                 74192       25040       -66%
calcdemo             386456      112024       -71%
maze                 379140      104708       -72%
lispdemo             399188      124756       -68%
mathdemo             482012      187100       -61%
satdemo              394388      119956       -69%
console_2048         404716      126188       -68%
mandelbrot           414140      139708       -66%
raytracer           1490596      536228       -64%
                   --------    --------
TOTAL (9 programs)  4424828     1475708       -66%
```

Population: the nine `examples/**` programs that build unattended at HEAD.
`examples/parallel/collatz.pas` is excluded and is NOT a DCE failure — it needs
`--threadsafe` and fails identically under `--no-dce` and under the baseline
binary, which is the control that says so.

**AND THE SELF-HOST FIXEDPOINT CONVERGES WITH THE PASS ON BY DEFAULT** — two
rounds, `4ae692b547e5`, on the largest Pascal program we have (4978 procs). The
compiler itself only shrinks 1.9% (7910257 -> 7759281 code), which is the
expected shape: a hello world is ~99% unreachable RTL, a compiler uses most of
itself.

### THE WALL, MEASURED RATHER THAN REASONED

`--emit-obj` has no DCE-defaulting line of its own — that was tried and reverted
— **but it does not need one.** The `-O` rule is unconditional on output mode, so
promoting the pass to `-O2` turns it on for `--emit-obj` **by the back door**,
and a plain no-flags ESP object build goes from linking to crashing the linker:

```
pascal26 -Fulib/rtl --emit-obj --target=riscv32 --platform=esp \
         test/esp_obj_rodata_iram.pas o.o
riscv32-esp-elf-gcc -fno-builtin -nostartfiles -Wl,-e,main o.c o.o -o o.elf

  DEFAULT  link rc=1  collect2: fatal error: ld terminated with signal 11
  NODCE    link rc=0
```

`rc` is the LINKER's own exit status, not a `tail`'s — the first reading of this
took the rc of the pipeline's last stage and got `rc=0` for both arms, which is
the wrapper-versus-job error in miniature and is why the rows above were re-run.

The object sizes say the same thing from the other side: **34696 B of code under
the new default against 262000 B with `--no-dce` and 262000 B from the baseline
binary** — so the pass really is running on a path nobody asked it to run on.

### WHY THIS CHANGES THE RANKING AND NOT JUST THE RECORD

This ticket reads as one broken path on one platform under one flag. **It is the
single thing standing between every pxx program and a two-thirds size cut**, and
that is invisible from its own summary, which is why the summary now says it.
`bug-a-a-pascal-hello-world-is-63kb-after-emission-size-dce` is now wired
`blocked-by:` this, so the ranker carries that instead of a reader having to
notice it.

### WHAT THIS DOES NOT SHOW

The tree was reverted and rebuilt byte-identical to `c24a11f2beb3`, and **no
full tier was run at `-O2`-with-DCE.** So this names ONE wall, found by the
cheapest available probe; it does not establish that the wall is the only one.
The quick gate found a second thing first and it is paperwork rather than a
defect: `test_dce_riscv32_stub_calls` fails because its control arm is the
DEFAULT invocation, which under the promotion is no longer "without the pass"
(`235052 >= 235052`). **Five Makefile rows share that shape** — riscv32, i386,
xtensa, arm, and the NilPy ESP object row — and every one of them wants its off
arm respelled `--no-dce` when the promotion eventually lands. Note they fail
LOUDLY only because they assert a strict shrink; an `<=` would have passed while
measuring nothing.

**WHAT WOULD RETIRE THIS AS A BLOCKER:** the IRAM object linking cleanly, then
the five control arms respelled, then a full tier at `-O2` with the pass on,
green, with `skip_holes == 0`. That is the O-lane's PROOF gate and it is
satisfiable on plexus now that the corpora are installed.

## Log
- 2026-09-22 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
