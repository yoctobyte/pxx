---
track: A
prio: 45
type: bug
blocked-by: []
summary: "The signal runtime (SIGSEGV/SIGFPE hook, restorer, sethook, install stubs) is emitted only by the Pascal driver in parser.inc. Every other frontend -- C, NilPy, Rust, Zig, Basic, Ada, Lua, the asm frontend -- produces a binary with no signal runtime, so a hardware fault there is an unhandled signal instead of a runtime error. Same shape as the I/O-lock gap that was already found and fixed."
---

# Only the Pascal driver emits the signal runtime

## The finding

`parser.inc`'s Pascal driver used to carry five inline arch tests choosing which
`EmitSignalRuntime*` to emit. Those have now been normalised into
`EmitSignalRuntimeForTarget` (`ir_codegen.inc`, next to `EmitIoLockStubsForTarget`)
by `91ca417b3` — but **the call site did not move**. Only the Pascal driver calls
the dispatcher, so only Pascal programs get a signal runtime.

This is the *same defect* the I/O lock had, and the comment recording that fix sits
three lines below the code this ticket is about:

    { --threadsafe statement-atomic I/O lock stubs. The per-arch choice used to be
      spelled out here, in the Pascal driver only, which is precisely why the
      other eight frontends shipped without it. }

The per-arch choice being spelled out in one driver is the *symptom*; the cause is
that there is no shared "finish the runtime" step every frontend driver must run.
Two mechanisms now serve that one concept (`EmitIoLockStubsForTarget`, called by
everyone; `EmitSignalRuntimeForTarget`, called by one). Per
`devdocs/dev/root-cause-over-microfix.md`, two is a smell — the fix worth doing is
probably a single per-target runtime-finalisation entry point that both live
behind, not a second round of "add the missing call to eight drivers".

## Why it was NOT fixed in 91ca417b3

Moving the *choice* is a pure refactor with no emitted-byte change. Making eight
more frontends emit a ~200-byte runtime they do not emit today is a **behaviour
change** across every non-Pascal target, and it belongs in its own commit with its
own gate rather than riding along in a build-configuration ticket.

## Acceptance

- A C, NilPy, and Zig program that dereferences nil reports a runtime error rather
  than dying on an unhandled SIGSEGV — matching the Pascal arm.
- `--no-signals` still opts out for all of them.
- Whatever shape the fix takes, it must not leave a third mechanism: prefer one
  finalisation step the drivers share.

## Provenance

Found 2026-08-19 by frank3 while building `PXX_NO_I386`
([[feature-a-build-a-reduced-compiler-by-selecting-frontends-and-targets]]) — the
omission define forced the arch tests into the open, which is exactly the coupling
measurement that ticket exists to take.
