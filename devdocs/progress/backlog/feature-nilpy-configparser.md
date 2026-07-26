---
summary: "nilpy: configparser module (INI settings) — songformatter's settings.py imports it"
type: feature
track: N
prio: 45
---

# nilpy: `configparser`

- **Type:** feature (Nil-Python frontend, stdlib surface) — **Track N**
- **Status:** backlog
- **Opened:** 2026-07-26 — `settings.py` is songformatter's smallest module and
  this is its only wall ([[feature-demo-songformatter-pxx-target]]):
  `pascal26:1: error: uses: unit source not found: configparser`.

## Shape

Same trick as [[feature-nilpy-re-module]]: a unit NAMED `configparser` in
`lib/rtl`, presenting the Python API over an INI reader, so `import configparser`
resolves with no frontend change. Check [[bug-nilpy-stdlib-name-binds-pascal-unit]]
first — if that lands a `pylib/`-prefixed search path for Python shims, this unit
belongs there instead.

Surface songformatter uses: `ConfigParser()`, `read(path)`, `has_section`,
`add_section`, `has_option`, `get`, `set`, `sections`, `write(file)`, plus
subclassing to override `optionxform` (it keeps option-name case). The subclass is
the interesting part — it needs a virtual hook, not just a function table.

An INI reader/writer may exist in `lib/rtl` already (`lfm.pas` parses a related
format); check before writing a new one.

## Gate

`make test-nilpy` green with a `.npy` case round-tripping a settings file, diffed
against CPython, + `--tier quick` + self-host byte-identical.
