---
track: C
prio: 60
type: bug
blocked-by: []
summary: "The C driver calls EmitIoLockStubsForTarget directly instead of the shared EmitProgramRuntimeStubsForTarget, so a C program still ships with no signal runtime. Every other frontend was moved over on 2026-08-21; C was left alone because cparser.inc is Track C's file-lane. One line."
status: done
owner: opus5-frank1
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

## Outcome

Already fixed, two days before I picked it up: `2cba0af20` (2026-08-24,
*"the Rust, Zig and BASIC drivers take the shared prologue; C gains the signal
runtime it never had"*) made the one-line change and left a fifteen-line comment
at `cparser.inc:9504` explaining it. The ticket was never moved.

Acceptance criterion verified at `5c5115038` — the ticket asks for "a C binary
gains ~400 bytes and `--no-signals` removes them again":

```c
int printf(const char *, ...);
int main(void) { printf("ok\n"); return 0; }
```

| build | code | bss |
| --- | --- | --- |
| default | 224876 | 59368 |
| `--no-signals` | 224490 | 59360 |

386 bytes of code and 8 of BSS, so the signal runtime is emitted and
`--no-signals` is no longer a no-op — which was the ticket's actual complaint.
Runs clean.

The "also worth a look" section — whether C's per-arch `_start` stub should
merge with `EmitProgramEntryForTarget` — is untouched and still open as row 2 of
[[refactor-a-the-missing-layer-between-frontends-and-backends]]. `2cba0af20`'s
comment says the same thing in the code: *"Merging those two conventions is its
own change; this is the step of the checklist that was simply missing."*

## Log
- 2026-08-26 — resolved, commit PENDING-COMMIT.
