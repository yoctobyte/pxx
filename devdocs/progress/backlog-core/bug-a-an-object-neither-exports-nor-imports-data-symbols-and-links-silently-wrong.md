---
slug: bug-a-an-object-neither-exports-nor-imports-data-symbols-and-links-silently-wrong
track: A
prio: 75
type: bug
status: new
blocked-by: []
created: 2026-09-01
found-by: frankD
owner: ""
summary: "--emit-obj emits NO data symbols. A global defined in a .c gets no OBJECT symbol, and `extern int x;` is relocated into the object's OWN .bss instead of becoming an undefined import -- so two pxx objects sharing a global LINK CLEANLY and read different memory. Measured: gcc links the pair and prints 0 where 99 is correct. No diagnostic anywhere. Blocks separate compilation of any real C project (busybox's libbb/ptr_to_globals.c is one global pointer and cannot even be emitted)."
---

# An object neither exports nor imports data symbols, and links silently wrong

Found attempting busybox's own build model — 52 translation units compiled as
separate objects rather than as a unity — for
[[feature-c-corpus-busybox-multi-applet]]. Compiler binary sha256
`0e1ed8c673bc`, at commit `d86bb32fe`.

## The measurement

```c
/* extref.c */              /* extmain.c */
extern int somebody_elses_global;      int somebody_elses_global = 99;
int read_it(void) {                    int read_it(void);
  return somebody_elses_global;        int main(void){ printf("%d\n", read_it()); }
}
```

```
pascal26 --emit-obj extref.c extref.o      # succeeds, no warning
gcc -O2 extmain.c extref.o -o link         # succeeds, no warning
./link
0                                          # gcc-only build prints 99
```

Nothing anywhere reports a problem. This is the repo's expensive shape: no
crash, a plausible wrong value, far from the cause.

## What the object actually contains

```
$ readelf -sW extref.o | awk '$4=="OBJECT"'
                                        (nothing — not one OBJECT symbol)
$ readelf -rW extref.o | grep 18377
0000000000018377  R_X86_64_PC32   .bss + 9504
```

So the two halves are one missing concept:

- **A defined global is not exported.** `ObjPlanHostedSymbols`
  (`elfwriter.inc:2948`) walks `Procs` only; there is no data pass. Its
  `numExportProcs = 0` refusal is the visible consequence — busybox's
  `libbb/ptr_to_globals.c`, whose entire content is `struct globals
  *ptr_to_globals;`, is refused with *"this object would define no linkable
  symbol"*. That message is correct about the object and wrong about the
  program: a translation unit of pure data is ordinary C.
- **An extern global is not imported.** `extern int x;` becomes a *local
  tentative definition* in this object's own `.bss`, with a section-relative
  relocation. There is no undefined symbol for the linker to resolve, which is
  exactly why the link is silent.

The second half is the dangerous one. The first fails loudly; the second
produces a running program that reads the wrong memory.

## Why it has not bitten before

Every C program pxx has built has been a single translation unit, where a
global is just a local. `--emit-obj` exists for ESP-IDF and for the ABI-parity
links, and those pass and return values in registers — they never share a
variable. The first thing to share one was busybox.

## Acceptance

- A global defined in a `.c` appears as `OBJECT GLOBAL` in the object's
  `.symtab`, in `.data` or `.bss` with its real size.
- `extern int x;` with no definition in this TU becomes `UND` plus a symbol
  relocation, and a link against another object's definition reads THAT
  variable — the two-file case above must print `99`.
- The `numExportProcs = 0` refusal counts data symbols too, so a data-only TU
  emits. Keep the refusal for a genuinely empty object.
- `static` file-scope data stays LOCAL and must NOT become an export.
- A common one to get wrong: a tentative definition (`int x;` at file scope
  with no initialiser, C 6.9.2) is a definition here, not an import — the
  distinction from `extern int x;` is the whole bug.
- Both frontends, since Pascal `cdecl` units have the same exposure, and every
  target `--emit-obj` supports (x86-64, i386, xtensa, riscv32).

## Coordination

`elfwriter.inc`'s object writer is under active work by frankA/frankC (i386
PIE objects, SysV argument placement) as of 2026-08-31 — message them before
starting rather than after.
