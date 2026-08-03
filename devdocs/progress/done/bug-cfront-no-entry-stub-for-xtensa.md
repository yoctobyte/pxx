---
track: C
prio: 40
type: bug
status: done
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

## FIXED (2026-08-03) — and the decision the gate asked for

**Decided: the object form is the target, not a standalone executable.** A
standalone xtensa executable is not a meaningful artifact — no OS, no syscall
ABI, and the ESP world links objects into an IDF image (the Pascal side has
worked exactly this way all along, `test_emit_obj.pas` → `.o` exporting
`app_main`). So xtensa gets no entry stub, by design, and the gate is the object.

The defect was not a missing stub but **an unconditional one**: the C driver ran
the program-entry-stub emitter even when producing a relocatable object, where
there is no ELF entry to fill and no reason to demand `main`. Two guards:

1. `EmitObjMode` skips the entry stub and, with it, the `main function not
   found` check and the call-patch. This is also the "smaller, separate
   question" the ticket noted on riscv32 — an object exporting only `app_main`
   is legitimate and no longer rejected.
2. The setjmp/longjmp/fenv runtime stubs, previously emitted for every C
   compile, are skipped on xtensa, which has no implementation for them (the
   windowed ABI makes the register-save stub its own piece of work). Emitting
   them unconditionally meant `EmitCSetjmpStubs: unsupported target` for every C
   program on xtensa — including the overwhelming majority that never touch
   setjmp. A TU that really does call setjmp now leaves `__pxx_setjmp`
   undefined and names it, instead of failing for everyone.

Measured — `test/cxtensa_obj.c` on both ESP ISAs:

| | xtensa | riscv32 |
| --- | --- | --- |
| before | `error: C program entry stub not implemented` | `error: main function not found` |
| after | REL object, Xtensa machine, GLOBAL `app_main`, UND `ext_notify`, R_XTENSA_32 relocs | REL object, GLOBAL `app_main` |

The test's `#if LONG_MAX != 2147483647L` / `#if INT_MAX != ...` guards are the
compile-time proof that `<limits.h>`'s target width reaches xtensa — the exact
coverage this ticket was opened to get. Wired into the Makefile beside the
Pascal `test_emit_obj` object checks.

**Still open, deliberately out of scope** (worth their own tickets if wanted):
setjmp/longjmp and fenv on xtensa; running the crtl differential tests on
xtensa, which needs an emulator or hardware, not a compiler change.

## Log
- 2026-08-03 — resolved, commit PENDING.
