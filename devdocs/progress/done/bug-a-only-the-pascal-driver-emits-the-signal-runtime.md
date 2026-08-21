---
track: A
prio: 45
type: bug
blocked-by: []
summary: "The signal runtime (SIGSEGV/SIGFPE hook, restorer, sethook, install stubs) is emitted only by the Pascal driver in parser.inc. Every other frontend -- C, NilPy, Rust, Zig, Basic, Ada, Lua, the asm frontend -- produces a binary with no signal runtime, so a hardware fault there is an unhandled signal instead of a runtime error. Same shape as the I/O-lock gap that was already found and fixed."
status: done
owner: claude-A
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

## Resolution (2026-08-21)

Fixed as the ticket asked — **one shared finalisation step, not a second round
of "add the missing call to eight drivers"**.

### What was built

`EmitProgramRuntimeStubsForTarget` (`ir_codegen.inc`) is THE finish-the-runtime
step: signal runtime + `--threadsafe` I/O lock stubs, called once per program by
every frontend driver, after the entry stub and before user code. A future
per-target runtime stub goes in there, never in a driver. Two supporting pieces:

- **`EnsureSignalBss`** — the `BSS_SIG_*` block, allocated next to the only code
  that reads it. This was a live second bug hiding behind the first: only the
  Pascal driver allocated it, so in every other frontend `BSS_SIG_HOOKS`,
  `_CODE`, `_ADDR` and `_CTX` were all 0 — aliased onto the same eight bytes,
  exactly the failure mode `EmitIoLockStubsForTarget`'s own comment records for
  `BSS_IO_OWNER` / `BSS_IO_DEPTH`. Idempotent, and allocated even under
  `--no-signals` because the signal-info builtins still lower to those slots.
- **`EmitDefaultSignalInstallForTarget`** — the SIGINT/SIGTERM install at
  program start, six more arch arms that were also Pascal-driver-only. The stubs
  alone are inert; this is the call that makes Ctrl-C graceful.

`EmitSignalRuntimeForTarget`'s NOTE ("only the Pascal driver calls this at all")
is replaced by the rule: reach it through the finalisation step, and do not add
a tenth private copy.

### Measured

| frontend | before | after |
| --- | --- | --- |
| NilPy | no signal runtime; `--no-signals` was a no-op | runtime + default install; **+406 bytes**, and `--no-signals` removes them |
| Rust | same | runtime; **+386 bytes**, `--no-signals` removes them |
| Zig / BASIC / Erlang / Ada / Whitespace | same | runtime, same shape |
| Pascal | unchanged | **byte-identical**: 25 tests × 5 targets = 120 binaries `cmp`-equal across the lift |

Rust and Zig: all 14 tests, output identical line for line. NilPy arm32
differential: broke=0, 36/52 unchanged. Self-host fixedpoint + `tools/gate.sh
quick` GREEN.

### Deliberately not done

- **The C driver** still calls `EmitIoLockStubsForTarget` directly. `cparser.inc`
  is Track C's file-lane and this is Track A; filed as
  `bug-c-driver-misses-the-shared-runtime-finalisation-step` — a one-line change
  in that lane.
- **The default signal INSTALL** reaches Pascal and NilPy only. Those two use the
  jump-to-main-body entry model, so the install sits at the top of the body,
  after the stubs exist. Rust, Zig, BASIC, Erlang, Ada and Whitespace emit
  `call main` *inside* the entry stub, before `SigInstallAddr` is known, so
  there is no point in their code stream where the call can go without
  restructuring their entry. They get the runtime (so a hook can be set) but not
  the default SIGINT/SIGTERM install. Noted in the code at the NilPy call site.
- The ticket's acceptance line "a nil deref reports a runtime error rather than
  an unhandled SIGSEGV" is **not** what this ticket could deliver: no frontend
  does that today, Pascal included. That is
  `bug-a-a-memory-fault-is-a-raw-sigsegv-not-runtime-error-216`, and it is a
  separate mechanism (a SIGSEGV hook that raises 216) layered on top of the
  runtime this ticket makes universally present.

## Log
- 2026-08-21 — resolved, commit c681ee686.
