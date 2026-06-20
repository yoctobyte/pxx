# Text file I/O: `Assign`/`Rewrite`/`Reset`/`WriteLn(f,…)`/`CloseFile` missing

- **Type:** library / RTL (Track B)
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-20 (next `examples/adventure` blocker after call-result
  member access landed)
- **Relation:** the current `examples/adventure` blocker (`engine.pas:563`).
  Not a compiler bug — a missing RTL surface.

## Symptom

`examples/adventure/engine.pas:563` (`TGame.SaveTo`):

```pascal
var f: Text;
begin
  Assign(f, path); Rewrite(f);
  WriteLn(f, 'room=' + Player.RoomId);
  …
```

```text
pascal26:563: error: undefined variable (Assign)
```

The classic Pascal text-file API over a `Text` (file) handle is not provided:
`Assign`/`AssignFile`, `Rewrite`, `Reset`, `Append`, `WriteLn(f, …)` /
`Write(f, …)`, `ReadLn(f, …)`, `Eof(f)`, `Close`/`CloseFile`. SaveTo/LoadFrom in
adventure need write + read.

## Notes / direction

- The compiler already has raw sys-file builtins (`tkSysOpen`/`tkSysRead`/
  `tkSysWrite` and the loadfile path) — a `Text`-handle RTL unit can wrap those
  (open/creat + write/read + close) with a small buffered record type, FPC
  naming. Keep it our-own-RTL (see strategy memory), no real FPC RTL.
- `WriteLn(f, …)` / `Write(f, …)` need the file-handle first-argument form of
  the existing Write/WriteLn lowering (currently console-only). That part may
  need a small compiler touch (recognise a file-handle first arg) — confirm
  whether it can be pure-library via an overload or needs the writer to accept a
  handle. If a compiler hook is required, split a Track-A sub-ticket.

## Acceptance

- A program that `Assign`/`Rewrite`/`WriteLn(f,…)`/`Close` then `Reset`/
  `ReadLn(f,…)`/`Close` round-trips text through a file.
- `examples/adventure` SaveTo/LoadFrom compile; adventure gets past
  `engine.pas:563`.

## Log
- 2026-06-20 — Opened. Surfaced after `feature-member-access-on-call-result`
  unblocked `engine.pas:446`/`462`; the next adventure line (`563`,
  `Assign(f, path)`) needs text-file RTL.
- 2026-06-20 — Added to `make library-suite-discovery` as `demo_adventure`.
  Current pinned v18 output remains `undefined variable (Assign)`. This is the
  first consumer for the new PAL byte-handle layer: implement classic text-file
  RTL on `PalOpen`/`PalRead`/`PalWrite`/`PalClose`, splitting a Track A ticket
  only if the file-handle `WriteLn(f, ...)` surface needs compiler lowering.
