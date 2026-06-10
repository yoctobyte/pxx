# `mimic FPC` compatibility mode

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-10 (user decision after Synapse directive-wall pass)

## Motivation

Real-world Pascal libraries branch-select on compiler identity: `{$IFDEF FPC}`
vs Delphi/Kylix version defines. PXX deliberately does **not** predefine `FPC`
(see the fpc-define landmine below), so jedi.inc-grade headers pick the wrong
platform path (Synapse selects Kylix → `uses libc`). Our identity stance is
sane — PXX is not FPC — but for consuming the existing FPC library ecosystem a
**deliberate, opt-in impersonation mode** is unavoidable. This ticket defines
it with its drawbacks on the table.

## Design

### Activation (opt-in only, never default)

- CLI: `--mimic-fpc`.
- Source directive: `{$MIMIC FPC}` near the top of the **program** being
  compiled (before `uses`). Equivalent to the flag; lets a project pin its own
  compatibility need without build-system cooperation.
- v1 scope is **whole-compile**: once active, every unit lexed in that compile
  sees the mimic define set. Per-unit / per-subtree scoping (mimic only the
  foreign library, keep the user's own units in PXX identity) is a possible
  v2; it requires save/restore of the define tables around `ParseUsesUnit`
  like CurUnitDir, plus a rule for what nested `uses` inherit.

### Define set (pin one FPC version, document it)

Mimic **FPC 3.2.2 on x86-64 Linux**:

| Define | Value |
|--------|-------|
| `FPC` | flag |
| `UNIX` | flag |
| `ENDIAN_LITTLE` | flag |
| `VER3`, `VER3_2`, `VER3_2_2` | flags |
| `FPC_FULLVERSION` | **30202** (valued) |

(`LINUX`, `CPU64`, `CPUX86_64` are already PXX defaults.) Keep the list small;
grow only when a concrete library probes a define we lack.

### Required evaluator work (the hidden structural cost)

jedi.inc's *active* FPC path immediately evaluates
`{$IF defined(FPC_FULLVERSION) and (FPC_FULLVERSION >= 20400)}`. The current
`EvalPasCondExprText` knows identifiers, `defined()`, `not/and/or`, parens —
no values. So this feature is **not** "add four defines"; it needs:

1. **Valued defines**: `PasDefine` tables grow a parallel integer-value array
   (flag defines value 0/absent). `{$DEFINE NAME:=value}` parsing can wait;
   only predefined values are needed for v1.
2. **Numeric `{$IF}` evaluation**: integer literals and `= <> < <= > >=`
   comparison operators in the conditional-expression evaluator (both copies
   of the state machine: lexer.inc `EvalPasCondExprText` is shared, but verify
   ExpandIncludes' simulated define state stays in sync).
3. **Float literals**: NOT needed — `(RTLVersion >= 14.2)` style appears only
   in Delphi branches, which stay inactive under mimic-FPC (and the
   inactive-branch eval skip from 440a9e0 already protects them). Reject with
   a clear error rather than silently mis-evaluating.

### `{$MODE}` handling

`{$MODE DELPHI}` / `{$MODE OBJFPC}` are currently unknown directives (skipped
when active). Keep ignoring them, but under mimic mode they must stay
**semantically inert**: PXX's dialect is what it is; mimic changes *visible
defines*, never parser semantics. A library that genuinely needs mode-specific
semantics will fail loudly at parse — that is the correct failure shape.

## Drawbacks (accepted with eyes open)

1. **It is a lie, and lies fail late.** Code that sees `FPC` will assume the
   FPC RTL (`SysUtils`, `Classes`, `sockets`, `termio`, `netdb`, exceptions,
   threading). We surface those gaps *after* branch selection, as missing-unit
   or missing-symbol errors deeper in the compile. Acceptable because the
   errors are loud and named; never claim FPC RTL compatibility.
2. **Self-host landmine stands.** The compiler's own source uses
   `{$ifdef FPC}` to mean "compiled by *real* FPC, not PXX" (`compiler.pas:1`
   is literally `{$mode objfpc}`). `--mimic-fpc` while self-compiling the
   compiler = broken bootstrap. Guards: never default-on; Makefile gates never
   pass it; consider a hard error if mimic is active and the main source
   defines `PXX`-bootstrap markers.
3. **`lib/rtl` must stay FPC-clean — new invariant.** Today no RTL unit uses
   `{$ifdef FPC}` (verified 2026-06-10). Under whole-compile mimic, RTL units
   lex with `FPC` defined, so any future `{$ifdef FPC}` in `lib/` would
   silently change meaning. Enforce with a grep check in `make test`.
4. **Version pinning is maintenance.** Mimicking 3.2.2 means libraries probing
   newer FPC features take old-version branches; bumping the pin can flip
   library behavior wholesale. One pin, documented, changed deliberately —
   never per-library.
5. **Auto-detection rejected.** Sniffing `{$MODE}` to auto-tag foreign units
   would mis-tag the compiler itself (drawback 2) and any dual-target user
   code. Activation stays explicit.
6. **Whole-compile scope blurs identity.** Under v1 the user's own program
   text also sees `FPC` defined. Fine for "compile this FPC library demo";
   wrong for mixed projects — that pressure is what justifies the scoped v2,
   not loosening v1.

## Work plan

1. Valued defines + numeric comparisons in the conditional evaluator
   (regression: `test/test_directive_if_numeric.pas`, no mimic needed).
2. `--mimic-fpc` flag + `{$MIMIC FPC}` directive installing the define set at
   lex-init; error on unknown mimic target (`{$MIMIC DELPHI}` reserved).
3. `lib/` FPC-clean grep gate in `make test`.
4. Re-run `test/manual/try_synapse_compile.sh`; record the next blocker class
   (expected: RTL availability — `synafpc`, `termio`, `sockets`, `netdb`,
   `Classes` surface) in feature-networking.
5. Docs: `docs/dialect.md` user note + architecture.md directive section.

## Acceptance

- `--mimic-fpc` compile of the Synapse smoke units gets past jedi.inc branch
  selection into the FPC/Linux path (failure, if any, is missing-RTL, not
  directive/branch errors).
- `make bootstrap` fixedpoint and full `make test` stay green with the feature
  merely present (mimic off).
- A test proves `FPC` is **not** defined in a default compile.

## Log

- 2026-06-10 — ticket opened; design + drawbacks locked with user ("our
  approach is sane, yet for compatibility it seems unavoidable").
