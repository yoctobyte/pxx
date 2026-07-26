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

## Update (2026-07-26) — the blocker is the SUBCLASS, not the INI parsing

Surveyed `settings.py`'s actual use: `ConfigParser()`, `read`, `write(file)`,
`has_section`, `add_section`, `has_option`, `get`, `set`, `sections`,
`items(section)` — a small, dull surface.

The hard part is line 57:

```python
class CasePreservingConfigParser(configparser.ConfigParser):
    def optionxform(self, optionstr):
        return optionstr
```

Two things NilPy cannot do yet:
1. A **dotted base class** — `class X(module.Class)` — where the base comes from
   an imported unit.
2. **Subclassing with an override**, which is
   [[bug-pascal-subclass-inherited-members]]: inherited fields and methods are
   invisible unqualified, the inherited constructor resolves to the wrong Create,
   and the inherited default property loses subscript assignment.

So this ticket is now BLOCKED-BY that bug in practice. A workaround exists and
should be resisted: make the unit's ConfigParser preserve option case by default
(CPython lowercases), which is what the subclass is FOR — but that only helps this
one program, and the subclass would still have to parse.

Order of work: fix the subclass bug, then this becomes the dull INI unit it looks
like.
