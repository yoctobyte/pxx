---
track: C
prio: 40
type: bug
blocked-by: []
summary: "The C driver calls EmitIoLockStubsForTarget directly instead of the shared EmitProgramRuntimeStubsForTarget, so a C program still ships with no signal runtime. Every other frontend was moved over on 2026-08-21; C was left alone because cparser.inc is Track C's file-lane. One line."
status: backlog
owner: ""
---

# The C driver misses the shared runtime finalisation step

`compiler/cparser.inc:9535` calls `EmitIoLockStubsForTarget;`. That is now half
of a step: `EmitProgramRuntimeStubsForTarget` (`ir_codegen.inc`) emits the
signal runtime **and** the I/O lock stubs, and is what every other frontend
driver calls — Pascal, NilPy, Rust, Zig, BASIC, Erlang, Ada, Whitespace.

Until it does, a C program has no signal runtime: `BSS_SIG_*` stays unallocated
(all four offsets aliased onto BSS[0]) and `--no-signals` is a no-op because
there is nothing to opt out of.

## The fix

```pascal
EmitProgramRuntimeStubsForTarget;   { was: EmitIoLockStubsForTarget }
```

## Why Track A did not just do it

`cparser.inc` is Track C's file-lane and A must not edit it concurrently — the
same rule that keeps `lexer.inc` safe. Filed from
`bug-a-only-the-pascal-driver-emits-the-signal-runtime`, which did the other
eight drivers.

## Also worth a look while you are there

The C driver has its own per-target `_start` entry stub
(`cparser.inc:9312-9330` and the parallel riscv32/xtensa arms) with argc/argv
loading and the initializer/finalizer calls. `EmitProgramEntryForTarget`
(`ir_codegen.inc`) is the shared entry stub the other drivers now use; it does
not yet cover C's shape. Whether C's stub should grow into it, or the shared one
should grow an argc/argv+initializers mode, is row 2 of
`refactor-a-the-missing-layer-between-frontends-and-backends` — a Track C call
to make, not an A one.

## Gate

C tests green + self-host byte-identical. A C binary gains ~400 bytes and
`--no-signals` removes them again.
