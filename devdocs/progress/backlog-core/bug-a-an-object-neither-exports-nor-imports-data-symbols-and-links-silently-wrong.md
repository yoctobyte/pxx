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

## LAND BOTH HALVES TOGETHER — the intermediate state can be WORSE

frankA, 2026-09-01, from a same-shaped bug he had to revert that afternoon: a
descriptor field written as 0 made **both** the retain and release halves
decline, so it merely leaked; widening the field woke the release half alone
and turned the leak into a double free. Asymmetric repair of a symmetric defect.

Worked out for this one, because the risk is real and it is not symmetric:

- **Export half alone.** A *tentative* definition (`int x;`, no initialiser)
  in two TUs currently produces two silent local slots. Export them both as
  `GLOBAL OBJECT` and the linker now sees a duplicate definition and **fails a
  link that used to succeed** — a new loud failure where there was a quiet
  wrong answer. This is why the tentative-definition/`COMMON` question in the
  acceptance list is load-bearing rather than tidy.
- **Import half alone.** Every `extern int x;` becomes `UND` with nothing
  anywhere exporting it, so **every** existing object build fails to link.

Neither half is shippable on its own. Land them as one change.

## THE INSTRUMENT, AND ITS "BEFORE" — measured 2026-09-01, not remembered

frankA's other point, from the same afternoon: an object that links cleanly and
reads the wrong memory has a detection problem, because a probe that reads
values back can print OK against a live defect. His first useful instrument was
an allocation census, not an assertion. The equivalent here is a **symbol-table
diff against gcc for the same translation unit**, and it exists now so the
"before" is a recorded measurement:

```c
int defined_initialised = 7;      /* .data, GLOBAL OBJECT */
int defined_tentative;            /* tentative definition (C 6.9.2) */
static int file_local = 3;        /* must stay LOCAL */
extern int imported_elsewhere;    /* must become UND */
int a_function(void) { return defined_initialised + defined_tentative + file_local + imported_elsewhere; }
```

`readelf -sW`, OBJECT/NOTYPE/FUNC rows only, at compiler binary sha256
`73a9d172409b`:

```
gcc -c -O0                        pxx --emit-obj
FUNC    GLOBAL 1   a_function     FUNC GLOBAL 1 a_function
OBJECT  GLOBAL 3   defined_initialised          (nothing)
OBJECT  GLOBAL 4   defined_tentative            (nothing)
OBJECT  LOCAL  3   file_local                   (nothing)
NOTYPE  GLOBAL UND imported_elsewhere           (nothing)
```

Five rows to one. **The fix is done when those two columns match** — including
`file_local` staying `LOCAL`, which is the control that catches an export pass
that simply exports everything.

## Coordination

**Not frankA** — he confirmed on 2026-09-01 that he has not touched
`elfwriter.inc`; his day was `ir_codegen.inc`, `rtti_emit.inc`,
`builtinheap.pas` and `symtab.inc`. An earlier version of this section named
him, wrongly: I read the **lane tags** on the object-writer commits (`feat(A)`,
`fix(A,C)`) as agent names, which they are not.

What is true is about the FILE, measured: `compiler/elfwriter.inc` has ten
recent commits on `origin/master` — i386 PC-relative data loads, `R_386_PC32`,
`--emit-obj` initialisers, hardened PIE objects (`ca4197115`, `b64341130`,
`6ab85feb8`, `3dd98fe32`). It is actively moving. Ask on the channel who is in
it now rather than inferring an owner from a commit tag.
