---
prio: 50
---

# {$I file} misses are silent, and includes only resolve next to the source file

- **Type:** bug (Pascal frontend — include expansion) — **Track P** (the
  expansion pass lives in shared `elfwriter.inc` / lexer plumbing, so A's gate)
- **Status:** done
- **Opened:** 2026-07-11, found on the New-ZenGL Pascal ladder
  ([[feature-game-library-candidate-suite]] slice C).

## Symptom

Two related gaps in `{$I name}` / `{$include name}` handling (the pre-lex
expansion pass in `compiler/elfwriter.inc`, `LoadFileCI` site ~line 2949):

1. **Silent miss.** When the include file cannot be found, the directive is
   dropped without any diagnostic. Defines the include would set never happen,
   so compilation continues with silently different configuration — the worst
   failure mode. Repro:

   ```pascal
   program t;
   {$I does_not_exist.cfg}
   begin end.
   ```
   compiles "ok" today. FPC: `Fatal: Can't open include file`.

2. **No include search path.** Includes resolve relative to the including
   file's directory only. ZenGL keeps `zgl_config.cfg` in `headers/` while the
   units live in `src/`/`srcGL/` (FPC builds pass `-Fi<dir>`; Lazarus projects
   set include paths). PXX has no `-Fi` equivalent, so every zgl unit's
   `{$I zgl_config.cfg}` silently vanishes (see gap 1).

## Where hit

All of `library_candidates/zengl/Zengl_SRC/src/*.pas` (`{$I zgl_config.cfg}`
from `headers/`). Any FPC/Lazarus project with an include directory will hit
the same.

## Acceptance

- A missing include is a compile error naming the file (matching FPC).
- `-Fi<dir>` (accept `-I<dir>` too) adds include search directories; search
  order = including file's dir, then -Fi dirs in order. `-Fu` dirs may
  reasonably be searched as a fallback (FPC does for some cases; decide and
  document).
- ZenGL units find `zgl_config.cfg` via `-Fi.../headers`; a test covers the
  error and the search order.

## Log
- 2026-07-12 — resolved, commit HEAD.
