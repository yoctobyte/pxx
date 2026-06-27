# C typedef alias to struct loses record id

- **Type:** bug (Track A+C — C parser typedef metadata)
- **Status:** done
- **Owner:** Codex
- **Found / Opened:** 2026-06-27, while switching `make test-lua` from stdin to
  `luaL_loadfile` after the crtl `fopen` bridge landed.

## Symptom

Lua's file-handle type is a two-step typedef:

```c
typedef struct luaL_Stream { FILE *f; lua_CFunction closef; } luaL_Stream;
typedef luaL_Stream LStream;
```

The second typedef (`typedef luaL_Stream LStream;`) kept only `tyRecord` and
dropped the original record id. Later `LStream *p; p->closef` therefore resolved
with `REC_NONE`, so field lookup collapsed to offset 0. Lua's close path loaded
the `FILE *f` slot as the callback and jumped through garbage during
`f:close()` / `lua_close`.

## Fix

Preserve typedef metadata when aliasing typedefs in `ParseCTypedef`:

- record aliases keep `CTypeBaseRec`;
- pointer aliases keep pointed-at type/record metadata even when the alias does
  not spell a fresh `*`;
- function-pointer typedef aliases keep their call signature.

## Log

- 2026-06-27 — Fixed in `compiler/cparser.inc`. Regression:
  `test/ctypedef_alias_fnptr_field_b89.c`. Broader proof: `make test-lua`
  now loads scripts via `luaL_loadfile`, and `test/lua/files.lua` covers Lua
  `io.open` read/write/seek/close over crtl stdio. Gate: `make test` green.
