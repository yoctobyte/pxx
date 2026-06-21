# Dotted / namespace unit names in `uses`

- **Type:** feature (Track A compiler / unit resolver)
- **Status:** done
- **Owner:** Track A
- **Opened:** 2026-06-21 (Synapse POSIX profile smoke)
- **Relation:** unblocks `feature-networking` / Synapse Delphi-`Posix.*` path;
  companion to `feature-dynamic-include-paths-config`

## Problem

PXX currently treats a dotted `uses` entry as only its first identifier. Synapse's
Delphi-POSIX path uses units such as:

- `Posix.SysSocket`
- `Posix.SysSelect`
- `Posix.SysTime`
- `Posix.NetinetIn`
- `Posix.StrOpts`
- `Posix.Errno`
- later: `Posix.Base`, `Posix.Unistd`, `Posix.ArpaInet`, `Posix.NetDB`
- `System.Generics.Collections`, `System.Generics.Defaults` in `blcksock`

With the manual Synapse POSIX profile (`SYNAPSE_PROFILE=posix`), the pinned
stable compiler fails before any `Posix.*` shim can be tested:

```text
pascal26:2316: error: uses: unit source not found: posix ()
```

That is a compiler resolver/parser gap, not a library workaround target.

## Required behavior

- Parse the full dotted name in a `uses` clause as one logical unit name.
- Preserve the dotted name for qualified references such as
  `Posix.SysSocket.Socket` and `System.Generics.Collections`.
- Define and document the source-file lookup rule for dotted units. A practical
  implementation should support at least one stable mapping from search roots,
  for example `Posix/SysSocket.pas` and/or `Posix.SysSocket.pas`.
- Keep existing non-dotted unit lookup behavior unchanged.

## Non-goals

- Do not add Synapse-specific path hacks.
- Do not require PAL/network code to flatten names into fake units such as
  `posixsyssocket`.
- Do not implement the `Posix.*` socket shims in this compiler ticket.

## Acceptance

- A focused test with `uses Posix.SysSocket;` resolves a local stub unit and can
  reference an exported symbol through `Posix.SysSocket.SymbolName`.
- A focused test with `uses System.Generics.Collections;` resolves the full
  dotted unit name rather than looking for only `system`.
- Re-running
  `SYNAPSE_PROFILE=posix test/manual/try_synapse_compile.sh` no longer reports
  `uses: unit source not found: posix` or `uses: unit source not found: system`
  for failures caused by dotted-name truncation.

## Log

- 2026-06-21 — filed from Track B Synapse smoke. The PAL/network layer already
  has socket primitives; Synapse's Delphi-POSIX path now needs compiler support
  for real Delphi namespace unit names before library shims can be useful.
- 2026-06-21 — DONE. Three parser changes (parser.inc):
  1. `ReadDottedUsesName` reads `ident('.'ident)*` in every `uses` clause
     (program / unit interface / unit implementation) and in the `unit X.Y;`
     header, so the full dotted name reaches the resolver. `ParseUsesUnit` already
     looks up the lowercased name in each search root, so a 2-part `Posix.SysSocket`
     maps to `posix.syssocket.pas` — the stable flat-filename mapping — with no
     resolver change.
  2. `ConsumeUnitQualifier` rewritten to match the LONGEST dotted compiled-unit
     prefix that still leaves a trailing `.member`, so `Posix.SysSocket.Symbol`
     resolves `Posix.SysSocket` as the unit (not `Posix`), leaving the parser on
     `Symbol`. Non-dotted `Unit.Member` and `record.field` are unchanged (it
     consumes nothing unless the prefix is a compiled unit).
  3. `unit Posix.SysSocket;` headers accepted (dotted name read; symbols still
     registered under `CurrentUnitIdx` = the interned dotted name).
  - Acceptance 1 (`uses Posix.SysSocket;` + `Posix.SysSocket.AF_INET` /
    `.SockTag`): PASS. Acceptance 2 (`uses System.Generics.Collections;`): PASS
    (3-part unit resolves; its `ListTag` callable). Regression test
    `test/dotted/test_dotted_uses.pas` (+ stub units `posix.syssocket.pas`,
    `system.generics.collections.pas`) in `make test-core`, prints `2/42/7`.
  - Acceptance 3 (Synapse smoke): PASS — truncated `unit source not found: posix`
    / `system` errors gone. Synapse now advances to *full-dotted* misses
    (`posix.base`, `system.ansistrings`) = the library/shim work (out of scope per
    non-goals), proving dotted-name resolution works end to end.
  - File mapping is flat (`Posix.SysSocket` → `posix.syssocket.pas`, lowercased);
    a `Posix/SysSocket.pas` subdir mapping was not added (the ticket asked for "at
    least one stable mapping"). Gate green: self-host + threadsafe byte-identical.
