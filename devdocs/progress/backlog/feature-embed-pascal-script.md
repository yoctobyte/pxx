# RemObjects Pascal Script — compile under pxx (embeddable scripting)

- **Type:** feature / investigation (real-world compat target + feature)
- **Status:** backlog
- **Owner:** — (**Track B** — libraries; uses `$(PXX_STABLE)`, never rebuilds the
  compiler. Compiler gaps it surfaces → Track A tickets.)
- **Opened:** 2026-06-26
- **Upstream:** `github.com/remobjects/pascalscript` — pure Object Pascal,
  compiles into the exe (no external runtime files). Bytecode interpreter for an
  Object-Pascal subset. Delphi **and** FPC supported upstream.
- **License:** custom zlib-style + **mandatory attribution** (a visible
  "made using RemObjects Pascal Script" + where-to-find line in aboutbox/docs).
  Commercial OK, redistribution OK, **no copyleft** — clean to vendor. Keep the
  attribution line if we ship it.
- **Relation:** sibling of [[feature-synapse-compile-check]] (same "compile a real
  third-party Object Pascal codebase, file the gaps" loop). Likely consumer of
  [[feature-mimic-fpc]] / `{$mode delphi}` + [[feature-mode-delphi-remaining]].
  Gentler cousin of [[feature-embed-dwscript-rtti]] (the RTTI stress test).

## Why this is a good test case (the actual motivation)

Two wins at once:
1. **Compiler conformance.** A self-contained, FPC-clean, mid-size Object Pascal
   codebase (lexer + compiler + bytecode runtime + import glue). Compiling it on
   the pinned stable is a heavyweight real-world test that exercises the dialect
   far past our own RTL — like Synapse, but a different shape (interpreter, not
   networking). Lowest-friction of the Pascal scripting engines, so it goes first.
2. **A feature for free.** Once it builds, frank2 apps gain an embedded
   Object-Pascal scripting engine. We are *not* rolling our own — purely reusing.

## Approach

- Vendor the `Source/` units (or point `pxx -Fu` at a clone) under `{$mode delphi}`
  + `--mimic-fpc`.
- Start with the core: lexer/parser/compiler (`uPSCompiler`, `uPSUtils`) +
  runtime (`uPSRuntime`), the minimal set to compile+run a `writeln('hi')` script.
- Defer the optional importers (DB, classes, Lazarus) until the core runs.
- Each compile failure that is a genuine dialect/codegen gap → a Track A ticket
  with the exact `pascal26:` error; library-surface gaps → RTL work here.
- A smoke test (`test/lib_pascalscript`?) that compiles a tiny script string and
  asserts its output, wired into `make lib-test`.

## Done when

`$(PXX_STABLE)` builds the Pascal Script core, and a frank2 host program runs a
small script end-to-end (compile → execute → observe output) under a smoke.
Stretch: host↔script binding of a hand-registered function.

## License compliance (we honour it)

If we ship a demo or test app built on Pascal Script, we **follow the license and
give the attribution** — a visible "made using RemObjects Pascal Script" line (and
where to find it) in the app's aboutbox / docs / README, and we keep the upstream
notice in any vendored source. Fair trade for a free engine; bake the credit line
into the demo from the start, not as an afterthought.

## Open questions

- How much of Pascal Script leans on Delphi-only RTTI vs manual registration
  (manual `RegisterMethod`/`AddFunction` is the plain path — start there, avoid
  RTTI until [[feature-embed-dwscript-rtti]] tackles auto-bind).
- Which `{$mode delphi}` / mimic-fpc corners it hits first (per-unit mode reset,
  interface delegation, variants).
