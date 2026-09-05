---
slug: bug-a-wasm32-emits-a-separate-function-per-compileast-call-so-a-proc-built-in-two-calls-loses-a-body
title: "wasm32 emits a separate function per CompileAST call, so a proc built in two calls silently loses one"
track: A
prio: 70
type: bug
status: working
created: 2026-09-04
found-by: frankA (while taking the wasm32 C entry stub)
owner: frankwasm
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

## RETRACTED — the NilPy population below is NOT this bug (frankb-78, 2026-09-04)

**Everything in this section is wrong about THIS ticket and is kept only so the
retraction is legible.** Re-run at 6f86e8f48 (binary `fcc5ad9a29a6`) with the
rewrite counter: **none of the six shapes prints the line, including all four
that fail.** The counter is aimed and working — it fires on `procedure Fill(out
s: string)` naming `Fill`, and on `test/test_managed_var_param.pas` naming
`SetItOut`, same binary, same invocation. So this is a real negative, not a
silent instrument.

SECOND CORRECTION (same day): three of the four "failures" DO NOT FAIL at
6f86e8f48 at all — a default argument, two defaults and a constructor all print
the same value as every other target. They failed at b0275ecc1 and were fixed in
34179225a..6f86e8f48 before I wrote this. I re-ran the six shapes at the new
binary to read the counter and did NOT re-read the run outcomes, so a stale
result travelled beside a fresh one. Only the generator row still fails.

The causal story below — that these shapes call a body emitted as `unreachable`
— was INFERENCE from the census line and was never traced; those two bodies are
present in PASSING builds too. What survives, and is measured, is only this: the
rewrite counter prints for none of these shapes while firing on two Pascal
controls, so whatever they are, they are not this ticket. A passing
and a failing NilPy build print the IDENTICAL census line — `2 emitted as
unreachable` — naming `PyBindHostKwArgs` (value of type Int64 assigned to a
managed string) and `PyBoundFnCallvnMaskBody` (32-parameter limit). The failing
shapes CALL one of those two; the passing ones do not, and `wasm trap:
unreachable instruction executed` is exactly what an `unreachable` body
produces. A default argument and a constructor go through keyword-argument
binding and the bound-call path; a plain `def f(a)` does not.

Filed as its own ticket. **This ticket's trigger is not on NilPy's ordinary road
after all** — rank it as the Pascal-shaped bug the corpus census measures.

How the wrong claim was made, since it is the reusable part: the six rows were
measured correctly and attributed to this mechanism because they were measured
right after reading it, and the two controls made the pattern look like the
mechanism's signature. A value comparison can establish THAT a target diverges
and can never establish WHY. The counter was the first instrument that could
answer the why, and it said no.

## (retracted) The NilPy population, measured (frankb-78, 2026-09-04)

This reaches Nil-Python too, and it reaches shapes that are ordinary rather than
exotic. Measured at 34179225a with the value comparison, which is the only
instrument that can see it — four oracles against one, same as the Pascal row.

| NilPy shape | native / i386 / arm32 / aarch64 | wasm32 |
| --- | --- | --- |
| plain `def f(a): return a + 1` | `2` | `2` — SAME |
| `class C:` with only a method, no `__init__` | `5` | `5` — SAME |
| **`def f(a, b=7)` — one default argument** | `8` then `3` | **trap, rc=134** |
| **`def f(a=1, b=2)` — two defaults** | `3` | **trap, rc=134** |
| **`class C:` with a user-written `__init__`** | `3` | **trap, rc=134** |
| **a generator (`yield` in a `while`)** | `6` | **`Unhandled exception`, rc=1** |

The discriminators are in the table on purpose. `plain` and `cls_noctor` are the
control rows: a single-`CompileAST` proc is fine on wasm32, so this is not "the
wasm32 NilPy backend is broken" — it is specifically procs built in more than
one call. And `cls_nodefault` fails with NO default argument anywhere, so the
trigger is the constructor itself, not the defaults: a user-written `__init__`
gets a result-zero prepend pass of its own (`CompileAST(PyPrependResultZero(...))`,
pyparser.inc:35806) beside the body. Defaults and generator steps are further
callers of the same shape; pyparser.inc has ten `CompileAST(` sites.

**THE BUILD EXITS 0 AND PRINTS `ok:`.** It also prints gap notes on the way past
(`C.get — statement IR op 51`) and still succeeds, so a wasm32 NilPy result read
from "it compiled", an exit code, or a gap census is measuring a program that
may be missing code. That is this ticket's own point arriving from the NilPy
side, independently: it is why I am recording the four PASSING oracles rather
than only the failure.

Scope of the claim: these are six probes, not a corpus census, and I have not
established that every failing row above shares ONE cause — only that the two
single-call controls pass while four multi-call shapes do not. The generator row
fails differently (`Unhandled exception`, rc=1, not a trap), so treat it as
possibly separate until someone reads it.

Context: NilPy modules only started reaching the wasm32 backend at bce31c210
(the wasi PAL), so this population is newly observable rather than newly broken.
