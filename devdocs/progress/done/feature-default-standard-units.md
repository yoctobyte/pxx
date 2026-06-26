# Default standard units: `System` + `textfile`

- **Type:** feature (compiler / RTL loading)
- **Status:** done
- **Track:** A
- **Owner:** —
- **Opened:** 2026-06-21
- **Relation:** follows `feature-textfile-keyword-io-dispatch` and
  `bug-implicit-textfile-unit-method-local`; needed by `examples/adventure`.
  Also sets the expected home for `System` helpers such as `Inc`.

## Problem

The current implicit textfile import is a token-scan special case. It works for a
simple program with a program-level `var f: Text`, but it misses method-local
`Text` declarations inside units:

```pascal
procedure TGame.SaveTo(const path: AnsiString);
var f: Text;
begin
  Assign(f, path); Rewrite(f);
```

```text
pascal26:563: error: undefined variable (Assign)
```

This is the wrong shape long-term. Classic Pascal expects a standard surface:
`System` is always in scope, and text-file I/O is close enough to that surface
that making users write `uses textfile` everywhere is awkward. At the same time,
the compiler must still be buildable by FPC, and the self-host compiler should
not be forced through unstable RTL while that surface is still moving.

## Direction

- Introduce a default standard unit set, initially `System` and `textfile`.
- Load default standard units uniformly for programs and units before user
  declarations are resolved.
- Keep implementations in RTL units. Do not move `Text`/`Assign`/`Inc` into
  compiler builtins just to make them visible.
- Preserve zero-cost unused code: a trivial program that does not use text-file
  I/O must not emit textfile routines or pull platform file I/O into the binary.
- Keep `textfile` parse-safe on all targets: platform/PAL calls must stay inside
  referenced routines, with no mandatory unit initialization.
- Add an escape hatch for bootstrap and constrained targets while the default
  RTL surface stabilizes. Prefer a command-line switch for build scripts, such
  as `--no-default-rtl` or `--no-implicit-system`; a source directive such as
  `{$PXXDEFAULTUNITS OFF}` can be added if source-level control is useful.
- When the escape hatch is active, code must explicitly import the units it
  needs, or rely only on true compiler builtins.

## Acceptance

- A minimal program can use `Inc` from `System` without an explicit `uses`.
- A unit method with local `var f: Text` can call `Assign`/`Rewrite`/
  `WriteLn(f, ...)` without explicit `uses textfile`.
- `examples/adventure` gets past `engine.pas:563` without adding an explicit
  `uses textfile` workaround.
- `make bootstrap` / compiler self-build has a documented opt-out path until
  `System` and `textfile` are stable enough to compile the compiler itself under
  default units.
- `test/hello.pas` remains the same size as the current baseline, 29,086 bytes,
  or any size increase is explained and tracked as a dead-code/lazy-emission
  follow-up before this broadens further.
- Existing explicit `uses textfile` tests continue to pass.

## Log

- 2026-06-21 - Opened after confirming the implicit textfile scanner catches a
  simple program but misses `Text` in a unit method-local var section. Design
  preference: default-load `System` and `textfile`, with an opt-out for compiler
  self-build while RTL stability catches up.
- 2026-06-21 - Baseline guard: `test/hello.pas` compiles to 29,086 bytes with
  both pinned v26 and rebuilt live `compiler/pascal26`; use this as the first
  check that unused default units stay free.
- 2026-06-21 - DONE (commit d5c7498, Track A). `textfile` (+ its `builtin`
  numeric-format backing) is now loaded by default on every non-ESP target,
  uniformly for programs and units, replacing the `: Text` token scan. The posix
  PAL backend dir is auto-added to the unit search path (ExeDir-anchored +
  CWD-relative) so `pxx foo.pas` resolves `platform_backend` with no `-Fu`.
  Opt-out: `--no-default-rtl` flag **or** `{$define PXX_NODEFAULTRTL}` in source;
  the compiler defines the latter so every self-build path (bootstrap,
  cross-bootstrap, stabilize) opts out with no per-site Makefile flag, and the
  self-host fixedpoint stays byte-identical. Acceptance: unit method-local
  `var f: Text` resolves Assign/Rewrite/WriteLn with no `uses`/`-Fu`;
  `examples/adventure` clears the engine.pas:563 blocker (now stops at :604, the
  separate nested-proc bug). `Inc`/`System` part: `Inc` was already a true
  compiler builtin (works with no `uses`), so no `System` RTL unit was needed for
  the acceptance — left as a no-op; revisit if/when real `System` helpers land.
  **Two latent compiler bugs surfaced and fixed in the same commit** (would crash
  any program that pulled a >8-byte managed record): (1) whole array-of-record
  idents mis-routed through the record-by-value temp path in IRLowerCallArg →
  corrupted SetLength target; (2) managed value-records leaked into the
  `__rttireg` class registry via EmitLayoutRTTI's UClsRTTIOff.
  **Size guard NOT met / accepted tradeoff:** `test/hello.pas` grows 29,086 →
  ~42,661 bytes (textfile+builtin in every program, no DCE). User chose the
  simpler "always include" over chasing the token scan. Tracked as
  `feature-lazy-standard-unit-emission` (dead-code / routine-level lazy emission)
  before the default surface broadens further.
