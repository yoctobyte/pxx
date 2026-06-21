# Dotted / namespace unit names in `uses`

- **Type:** feature (Track A compiler / unit resolver)
- **Status:** backlog
- **Owner:** —
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
