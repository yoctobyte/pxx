---
slug: bug-a-dce-on-a-c-program-drops-main-because-nothing-roots-the-c-entry-path
track: A
prio: 50
type: bug
status: backlog
created: 2026-09-02
found-by: frankC
owner: ""
blocked-by: []
summary: "DCE's `only the Pascal frontend is wired up so far` refusal is HONEST, and this is what it is hiding: lift it for C and a `-O3` C executable keeps 43 of 792 bodies, none of them a C function -- `main` itself is dropped and the program SIGSEGVs. The 43 survivors are exactly the Pascal runtime's own roots (RTTI method slots, the explicit stub roots), so the C entry path contributes no root at all. Not a call-graph gap: C OBJECTS are correct, because ObjProcIsExported roots them. It is the executable's entry that nothing names."
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
