
## 2026-09-22 (frankb-8e) — re-measured as instructed, and the headline bucket contains `main`

frankS's handover says *"Re-measure before quoting: the population is one program
on one ISA."* Done, same program, same ISA, at `fc53bd2bd`.

**THE RECORDED COMMAND DOES NOT BUILD AT HEAD.** The write-up above says
`--platform=esp --no-signals --dce`, xtensa windowed. At HEAD that fails twice
before it produces a number, and the second failure names its own remedy:

```
--target=xtensa --platform=esp --no-signals --dce --dce-why
  -> error: addi immediate displacement 128 is outside the encodable range   (Call0)
--target=xtensa --xtensa-abi=windowed --platform=esp --no-signals --dce --dce-why
  -> error: the forward call to PyUtf8CpAt at 475492 cannot reach its body at
     1081716 (CALL0/CALL8 reach +-512 KiB) ... Rebuild with --xtensa-long-calls
```

The command that reproduces is therefore

```
./compiler/pascal26 --target=xtensa --xtensa-abi=windowed --xtensa-long-calls \
  --platform=esp --no-signals --dce --dce-why \
  examples/esp32/nilpy-c3/main/main.npy <out>
```

Recorded here because a number whose command is not beside it is not
re-derivable, and this one is not re-derivable even by the same instrument on
the same file. I have NOT established whether the image crossed the ±512 KiB
forward-call threshold since `857dcdaac` or whether the flag was simply omitted
from the write-up; the error is a size threshold with a documented remedy, not
a defect, so I did not chase it.

### The table, both rows carried

| first reason | @`857dcdaac` (frankS) | @`fc53bd2bd` (me) |
| --- | ---: | ---: |
| called by | 639,962 B / 340 | 644,311 B / 340 |
| **vmt/rtti slot** | **172,637 B / 149** | **174,350 B / 149** |
| @proc taken in unowned code | 13,725 / 2 | 13,725 / 2 |
| called from unowned code | 1,006 / 5 | 1,006 / 5 |
| total live | 827,330 | 833,392 |

**Identical body counts in every bucket**, bytes up ~0.7%. That is two weeks of
code growth, not a structural change: the finding holds exactly as written.
`TPyFile.writelines` still heads the largest row, 95,157 B (was 94,665).

### And the bucket contains the program's entry point

The section above warns that attribution is FIRST-reason and that *"reading the
vmt total as 'what would be freed' is wrong in both directions."* Here is the
instance, which I think is worth more than the warning because nobody argues
with a row:

```
   8741B  PyUserObjGetattr <- pydynattr_get_v <- main <- [vmt/rtti slot]
   8289B  main <- [vmt/rtti slot]
   6884B  pydynattr_get_v <- main <- [vmt/rtti slot]
```

Confirmed directly: `--dce-why=main` answers `[match] 8289B main <- [vmt/rtti
slot]`. **`main` is in the 174,350 B bucket.** Those three rows alone are
23,914 B, 13.7% of it, and nobody is going to propose deleting the entry point.

So the headline number is **not** an upper bound on a saving and must never be
quoted as one. That is also the sharpest argument for the instrument this
section asks for, and it changes its shape: **a per-root SUBTREE TOTAL would
be wrong for the same reason.** Summing a subtree counts every body once per
root that reaches it, and `main`'s subtree is reachable from the entry point
regardless. The question anyone actually wants answered is

> if this root were removed, how many bytes stop being live?

which is a **differential**, not a sum: live-set WITH the root minus live-set
WITHOUT it. It over-counts nothing, it cannot be confused with a subtree, and
it answers `0` for a root like `main` that something else reaches anyway —
which is the correct answer and the one a subtree sum cannot give.
