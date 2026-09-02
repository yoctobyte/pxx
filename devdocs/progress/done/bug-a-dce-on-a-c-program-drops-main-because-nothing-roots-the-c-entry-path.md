---
slug: bug-a-dce-on-a-c-program-drops-main-because-nothing-roots-the-c-entry-path
track: A
prio: 50
type: bug
status: done
created: 2026-09-02
found-by: frankC
owner: frankC
blocked-by: []
summary: "FIXED. CPatchStubCall emits the C entry stub's call to `main` as a forward with a zero displacement -- `main` has no Procs[] row yet -- and patches it later with an ABSOLUTE body address, never through CallFix, so the call graph genuinely contained no caller for main and DCE deleted it: 43 of 792 bodies live and a SIGSEGV. Fixed as a table (RecordEntryRoot, called by CPatchStubCall itself) rather than a special case. A CodeRef would NOT have sufficed -- a range merely KEPT is never WALKED, so main would have survived with everything it calls deleted underneath it. DCE is now on for the C frontend: full.c -O3 307320B -> 77944B, same output, and 458 C tests agree between -O2 and -O3 with the harness's own positive control reporting DIFF."
---

# DCE on a C program drops `main`

Measured 2026-09-02 at `6a084d569`, x86-64, by lifting the `not
IsPascalFrontend` refusal in `dce.inc` and nothing else.

```
$ cat tiny.c
#include <stdio.h>
static int f(int n){ return n+1; }
int main(void){ printf("%d\n", f(41)); return 0; }

$ pxx -O3 --dce-report tiny.c tiny
dce: bodies 792  live 43 (16093B)  dead 743 (280852B)  dropping 743 (280852B)
dce: code 298542B -> 17690B
$ ./tiny
Segmentation fault
```

## The 43 survivors name the cause

`--proc-map` on the result lists them, and every one is a **Pascal runtime**
entry: `PXXAlloc`, `PXXStrConcat`, `TInterfacedObject._AddRef`,
`__pxx_run_finalizers`, `__pxx_setjmp`, `PXXSysWrite`, ... **Not one C
function**, `main` included. At `-O2` the same program emits 792 procs and
`main` is among them, so it exists and is simply never marked.

Those 43 are precisely what `DceRun`'s unconditional roots produce —
`MethodFixups` (RTTI/VMT slots), `ProcAddrFix`, `InitProcs`/`FiniProcs`,
`FiniRunnerProc`. So the reachability walk starts, runs, and finds the C
program is not attached to it anywhere.

## It is the ENTRY, not the call graph

The distinguishing measurement: a C **object** is correct.

```
pxx --emit-obj      ch.c -> 365368 B   prints "44 42"
pxx --emit-obj --dce ch.c -> 275272 B  prints "44 42"
```

An object is rooted at `ObjProcIsExported`, which lands `cfa` and `cfb`, and
everything they reach — including `static int helper`, `snprintf` and the crtl
bulk under them — survives correctly. **So the C call graph IS in `CallFix`.**
What is missing is the one root an executable has and an object does not: its
entry.

For Pascal that root is free. The program body is raw code at offset 0, owned
by no `Procs[]` row, so `DceOwnerOf` returns -1 for every call it makes and
`DceRun` marks each as a root by definition. C's `main` is an ordinary
`Procs[]` entry, and whatever calls it is not producing an unowned `CallFix`
site — that is the thing to go look at, and the 25% (not 77%) cut on the object
above suggests the C entry stub may not be shaped like the Pascal one at all.

## Why this is filed rather than fixed

The fix is probably one root, and "probably one root" is exactly the claim that
needs a measurement rather than a patch: a wrong root here does not crash, it
deletes a function somebody needed and the program fails somewhere else. The
verification this wants is a C corpus at `-O2` vs `-O3` — Track T's optdiff
tier — not a single repro, and that is more than the sitting that found it had.

The consumer is real: `feature-a-every-emit-obj-object-links-its-own-full-copy-of-crtl-so-n-objects-cost-n-runtimes`
banked busybox at **13.7MB across 41 translation units**, all of it C, and
`--emit-obj` DCE (landed `6a084d569`) does not move that number while this
refusal stands. Both halves are worth having: the object half is already
correct here and is what busybox needs.

## 2026-09-02 (frankC) — FIXED. The root was one hand-patched call, and it named itself

`CPatchStubCall` (cparser.inc). The C entry stub emits its call to `main` as a
forward with a zero displacement, because `main` has no `Procs[]` row yet, and
patches it later with **an absolute body address** — never through `CallFix`.
So the call graph contains no edge for it and never could; the pass was reading
a graph in which `main` genuinely has no callers. Same for the pre-main
`__pxx_run_initializers` shell, patched the same way two lines below.

The fix is a table, not a special case: `RecordEntryRoot(procIdx)`, called by
`CPatchStubCall` itself, so any future hand-patched stub call is rooted without
anyone remembering the rule. `DceRun` marks them beside `InitProcs`/`FiniProcs`.

**A `CodeRef` would NOT have been enough**, and the distinction is worth
keeping: `RecordCodeRefAt` keeps a code offset's BYTES alive and re-aims the
displacement — right for a stub nobody owns, and wrong here, because a range
that is merely *kept* is never *walked*. `main` would have survived with every
routine it calls deleted underneath it. Both are needed and they are different
mechanisms: the rel32 SITE also moves when the pass compacts, so
`CPatchStubCall`'s rel32 arm records a `CodeRef` too.

### Measured after

    full.c   -O2 307320 B   -O3 77944 B     both print "hello 5"
    tiny.c   792 bodies -> 71 live, correct output (was 43 live, SIGSEGV)

### And what the corpus sweep turned up, which was not this bug

544 C tests, `-O2` against `-O3`. The one real difference was
`c_crtl_signal_and_wait` row 18, and it is not a DCE defect: the row read
`ru.ru_maxrss > 0` on a `struct rusage` **nobody had written**, so it was
testing uninitialised stack. It agreed with glibc when the file was diffed
against gcc — both sides were reading their own garbage — and enabling `--dce`
moved the frame and flipped it to 0.

`ru_maxrss` is also simply the wrong field: measured against the gcc oracle on
this kernel, a child that loops and `_exit`s reports **0 from both compilers**,
and a child that writes 8MB gets **8416 from pxx**. `wait4`'s rusage works. The
row now poisons `ru` and asserts the kernel wrote through the pointer, which is
what its comment always claimed to be testing and is true for any child.
