# cJSON integration suite (`make test-cjson`)

Rung-1 end-to-end probe for the pxx **C frontend** (see
`devdocs/developer/c-torture-candidates.md` and `plan-c-frontend-test-ladder.md`):
compile the real [cJSON](https://github.com/DaveGamble/cJSON) 1.7.18 library
libc-free against `lib/crtl` and **round-trip** each fixture — `cJSON_Parse` then
`cJSON_PrintUnformatted` — checking stdout against a committed `*.expected`.

The round-trip is the free oracle: it exercises the parser, object/array structs,
heap (`malloc`/`realloc`/`free`), pointers, recursive descent, and the number/
string print path — ground the `test/c*_b*.c` micro-tests cannot reach.

## Distinct from the base gate

**NOT** part of `make test`. The base gate carries no 3rd-party dependency.
`make test-cjson` **skips gracefully** when the cJSON tree is absent, so it never
blocks a normal build.

## Layout

- `runner.c` — committed. Amalgamates `lib/crtl` + `cJSON.c` and round-trips the
  document at `/tmp/pxx_cjson_input.json` (the Makefile copies each case there;
  C argv is not wired yet).
- `*.json` — committed fixtures (integer/string/bool/null/nested, plus
  `floats.json`/`floatarr.json` exercising the number print path).
- `*.expected` — committed canonical output, generated **independently** with
  stock `python3 -c "json.dumps(..., separators=(',',':'))"`, not by the runner
  itself (so the oracle is independent of the code under test).

## cJSON source (not committed)

cJSON lives under `library_candidates/cjson/src/` (gitignored — MIT, but kept out
of the base tree like the Lua source). To run the suite:

```sh
mkdir -p library_candidates/cjson/src
curl -L https://github.com/DaveGamble/cJSON/archive/refs/tags/v1.7.18.tar.gz | tar xz
cp cJSON-1.7.18/cJSON.c cJSON-1.7.18/cJSON.h cJSON-1.7.18/LICENSE library_candidates/cjson/src/
make test-cjson
```

Override the location with `make test-cjson CJSON_SRC=/path/to/cjson/src`.

## Current status — BLOCKED on a Track A codegen bug

The fixtures **do not pass yet**: `cJSON_Print*` returns `NULL` for every value
because of a silent miscompile of `buffer->buffer = hooks->allocate(...)` — an
`arr->field = call()` store where `arr` is a fixed array. Parsing works; printing
is dead. Filed as
`devdocs/progress/backlog/bug-c-arrow-on-array-store-of-call-result-clobbered.md`.
The harness goes green once that lands.

The float-number print path additionally needs crtl `sscanf` (cJSON re-parses its
own `%g` output to check round-trip precision); that was added to `lib/crtl`.
`floats.json`/`floatarr.json` are already committed and exercise it. They use
**only exact binary fractions** (0.5, 0.125, 19.5, …) where cJSON's `%1.15g`
serialization is unambiguous — verified to match both the `python3` compact
oracle and crtl's own `%1.15g` engine, and to round-trip at 15 sig digits (so
cJSON never bumps to the `%1.17g` fallback). Avoid non-exact decimals (0.1, 3.14)
and exponent-notation magnitudes until the print path is unblocked and the crtl
`%g` engine can be diffed against the oracle for those shapes.

## Adding a fixture

Drop `foo.json` here, generate `foo.expected` independently
(`python3 -c "import json;print(json.dumps(json.load(open('foo.json')),separators=(',',':'),ensure_ascii=False))" > foo.expected`),
commit both. Keep strings ASCII for now to avoid `\uXXXX`-escaping divergence
between cJSON and the oracle; avoid non-integer floats until the print path is
unblocked.
