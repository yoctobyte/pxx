---
slug: bug-a-wasm32-emits-a-separate-function-per-compileast-call-so-a-proc-built-in-two-calls-loses-a-body
title: "wasm32 emits a separate function per CompileAST call, so a proc built in two calls silently loses one"
track: A
prio: 70
type: bug
status: backlog
created: 2026-09-04
found-by: frankA (while taking the wasm32 C entry stub)
owner: ""
blocked-by: []
summary: "MEASURED 2026-09-04, WRONG ANSWER ON A RUNNING PROGRAM, and it is live in Pascal today. A frontend builds one proc body with MORE THAN ONE CompileAST call -- an `out` parameter's finalize, a default-value assign, a generator step, then the user's statements. On every register target those append into one byte range and ARE one function. On wasm32 each CompileAST runs a full WasmBodyBegin/WasmBodyEnd cycle against the SAME slot, so the last one OVERWRITES the earlier ones and their code is gone. `procedure Fill(out s: string)` prints [XY] on native, i386, arm32, aarch64 and riscv32 and [KEEPXY] on wasm32 -- the out-parameter clear is dropped and no diagnostic is produced. With THREE calls the same mechanism refuses outright (`duplicate export`), so the bug has a silent arm and a loud one and the silent one is the common case. It is also what blocks bug-c-no-c-program-entry-stub-for-wasm32: C's `main` is built in three calls (pending global inits, deferred aggregate inits, body)."
---

# One proc, N calls, N wasm functions — and only the last one survives

The backend already solved this for TOP-LEVEL code and the note is in the source
(`ir_codegen_wasm32.inc:557`, "THE PROGRAM BODY ARRIVES IN PIECES"): chunks get
their own slots and `main` is synthesised as a call to each in order. **The same
thing happens inside a PROC and there is no equivalent there.**

## Repro — silent arm, five oracles against one

```pascal
program outp;
procedure Fill(out s: string);
begin
  s := s + 'X';
  s := s + 'Y';
end;
var a: string;
begin
  a := 'KEEP';
  Fill(a);
  writeln('[', a, ']');
end.
```

```
native   [XY]        i386   [XY]      arm32 [XY]
aarch64  [XY]        riscv32 [XY]
wasm32   [KEEPXY]    <-- the out-parameter clear never ran
```

`out` means the callee's view starts empty, so every other target clears it. On
wasm32 `pasparser_proc.inc`'s `CompileAST(valNode)` (the AN_MANAGED_INIT
finalize) produced a complete wasm function for `Fill`'s slot, and then the
body's own `CompileAST(seqNode)` produced a second one for the SAME slot, which
replaced it.

Instrumented at `IREmitMachineCode` and at the wasm body-end export:

```
PROBE emitbody proc=137 Fill          PROBE bodyend nm=Fill slot=128 curproc=137
PROBE emitbody proc=137 Fill          PROBE bodyend nm=Fill slot=128 curproc=137
```

Two entries, two bodies, one slot. On x86-64 the same program enters
`IREmitMachineCode` twice as well and no proc is duplicated in the output,
because there a body is a range of bytes and the two calls simply append.

## Repro — loud arm, no C anywhere

Add a second `out` parameter and the count goes to three:

```pascal
procedure Fill(out a: string; out b: string);
```

```
pascal26:6: error: wasm: duplicate export "Fill$128" — the SAME slot (128) is
being exported twice, so a body was lowered more than once; this is not a
naming collision
```

**Two `out` parameters is not an exotic program.** Anything reaching three
in-proc `CompileAST` calls refuses to compile for wasm32 today.

## Why this is not just a wasm32 curiosity

It is the wall behind `bug-c-no-c-program-entry-stub-for-wasm32-so-no-c-program-can-target-it`.
C's `main` is built in three calls — `CompilePendingGlobalInits`,
`CEmitDeferredCAggInits`, then `CompileAST(node)` for the body
(`cparser.inc:13660-13665`) — so the first C program ever compiled for wasm32
hits the loud arm immediately. Fixing the entry stub without fixing this gets a
C program that builds and drops its global initialisers.

## Shape of a fix

The chunk mechanism is the precedent and the argument for it is already written
at `ir_codegen_wasm32.inc:557`: give each call its own slot and synthesise the
proc as calls to them in order. Ordering is load-bearing here in a way it is not
for top-level chunks — the finalize must precede the user body — but the
existing synthesiser already calls chunks in order.

The alternative is to keep ONE body open across calls and close it at the proc
boundary, which needs a hook wasm32 does not currently take: it never calls
`EmitProcEpilog` (see `EmitManagedLocalCleanupForTarget`'s wasm32 exit).

**Do not fix this by making the frontends emit one call.** There are at least
seven in-proc `CompileAST` sites in `pasparser_proc.inc` alone plus three in
`cparser.inc`, they exist for good reasons, and every other backend is correct
as written. The backend is the one making an assumption the frontends never
promised.

## What a fix must be tested against

Both arms above, on wasm32 AND on the five register targets (the register ones
are the control: they must not move). The silent arm is the one that needs the
value assertion -- `[XY]`, not "it compiled" -- because that is precisely what
an exit-code or compile-success check cannot see.
