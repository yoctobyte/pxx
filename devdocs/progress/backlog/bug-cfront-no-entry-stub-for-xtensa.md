---
track: C
prio: 40
type: bug
---

# No C program entry stub for xtensa — no C compiles for that target at all

- **Type:** bug / gap (C frontend) — **Track C**
- **Found:** 2026-08-02, checking whether the day's `limits.h` 32-bit fix reached
  the ESP ISAs.

## Measured

```
--target=xtensa           int main(void){return 0;}
  -> pascal26:1: error: C program entry stub not implemented for this target yet
--target=xtensa --platform=esp   int app_main(void){return 0;}
  -> same error
```

So it is not a program-vs-object distinction: **the C frontend emits nothing for
xtensa**, in either shape.

riscv32 is different and works — it compiles C and only objects that the object
path wants a `main` (`pascal26:1332: main function not found` for a TU exporting
only `app_main`), which is a smaller, separate question.

## Why it matters now

The user has made **xtensa the primary ESP target** (S2/S3 hardware). Two
consequences:

1. `lib/crtl` exists to let real C compile as-is, and it cannot be exercised on
   xtensa at all. Every crtl test added on 2026-08-02 (`cmath_constants`,
   `cstring_batch`, `cerrno_strings`, `cstrtol_range`, `ctime_localtime`,
   `cscanf_math`, `cdup`, `cfileops`, `cstat_fields`, `cproc_ids`, `cisatty`)
   is cross-checked on i386/aarch64/arm32 — **xtensa is a blind spot**.
2. The 32-bit correctness work those tests pin (notably `limits.h`'s
   target-width `LONG_MAX`, which was 64-bit on every target until that day) is
   verified on riscv32 but unverifiable on xtensa.

Not currently *blocking* ESP work: the ESP examples provide `app_main` from
Pascal, and IDF supplies the C side. This is about C-on-xtensa coverage, not the
Pascal path.

## Gate

`int main(void){return 0;}` compiles for `--target=xtensa`, and the crtl
differential tests listed above run on xtensa the way they already do on
i386/aarch64/arm32. If a standalone xtensa executable is not meaningful, the
object form (`--platform=esp`, exporting `app_main`) is the right target for the
gate instead — decide which, and say so in the ticket.
