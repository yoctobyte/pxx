# examples/chess: PalBackendGetDents64 undefined (PAL backend not linked)

- **Type:** bug (library / PAL wiring — Track B)
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-21
- **Relation:** next `examples/chess` blocker after
  `feature-local-typed-constant` (done). Chess now parses past `chess.pas:846`.

## Problem

Building chess with the stable compiler:

```text
./compiler/pascal26 -Fulib/rtl -Fulib/pcl examples/chess/chess.pas /tmp/chess
pascal26:185: error: undefined variable (PalBackendGetDents64)
```

`lib/rtl/platform.pas:185` calls `PalBackendGetDents64`, whose body lives in
`lib/rtl/platform/posix/platform_backend.pas` (and an esp variant). The backend
unit is not on chess's `-Fu` search path / not pulled by `platform.pas`, so the
symbol resolves to nothing.

## Direction (Track B)

- Ensure the posix `platform_backend` unit is reachable from `platform.pas` when
  chess is built (add the `platform/posix` dir to the search path, or have
  `platform.pas` `uses` the backend unit so it travels with the source).
- This is a library/search-path wiring issue, not a compiler feature gap — the
  compiler resolved every earlier chess construct.

## Acceptance

- `examples/chess` advances past `platform.pas:185` (hits the next gap, if any).
