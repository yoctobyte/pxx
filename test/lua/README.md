# Lua integration suite (`make test-lua`)

End-to-end check that the pxx **C frontend** compiles and runs real portable C:
the [Lua 5.4](https://www.lua.org/) interpreter, built libc-free against `lib/crtl`.
It exercises ground the `test/c*_b*.c` micro-tests cannot reach — full programs
using OOP/metatables, closures, coroutines, the string library, and the float
value model, with the runner itself and `files.lua` covering Lua's C stdio file
path. (Example payoff: `sizeof("self")` returning the pointer size silently broke
*all* colon-method OOP; no micro-test caught it, a real program did.)

## Distinct from the base gate

This suite is **NOT** part of `make test`. The base gate stays free of any
third-party dependency. `make test-lua` **skips gracefully** when the Lua tree is
absent, so it never blocks a normal build.

## Layout

- `runner.c` — committed. Amalgamates `lib/crtl` + the Lua core/stdlib and runs
  the program copied to `/tmp/pxx_lua_input.lua` via `luaL_loadfile`, exercising
  Lua's `fopen`/`fread` path. Diagnostic markers some Lua sources print go to
  stderr; the suite compares **stdout** only.
- `*.lua` — committed test programs.
- `*.expected` — committed reference stdout (matches stock Lua 5.4).

## Lua source (not committed)

The Lua C sources live under `library_candidates/lua/src/` (gitignored — Lua is
MIT, but kept out of the base tree). To run the suite, place a Lua 5.4 source tree
there, e.g.:

```sh
curl -L https://www.lua.org/ftp/lua-5.4.7.tar.gz | tar xz
mkdir -p library_candidates/lua && cp -r lua-5.4.7/src library_candidates/lua/
```

Then:

```sh
make test-lua
```

Override the location with `make test-lua LUA_SRC=/path/to/lua/src`.

## Adding a test

Drop `foo.lua` here, generate `foo.expected` with stock Lua (`lua foo.lua > foo.expected`),
commit both. Avoid `print(<boolean>)` until the boolean→string gap is fixed
(currently renders empty); use explicit string output instead.
