---
track: A
prio: 35
type: bug
blocked-by: []
status: done
owner: claude-AN
---

# path-form `uses './x.c'` collides with the enclosing unit's OWN name

Found implementing M1 of `feature-nilpy-cpyext-c-api-from-source` (measured
with `--debug`, not guessed — see the comment atop
`test/nilpy_units/hello_ext.pas`).

`ParseUsesUnitBody` (`compiler/parser.inc:27045` on) keys its "already
compiled" guard off `InternStr(lo)`, where for a **path-form** reference
(`uses './sub/unit.c'`) `lo` is `LowerCase(GetFileBaseName(name))` —
i.e. the file's base name with the extension stripped
(`compiler/parser.inc:27068-27077`). That is the *same* key space a bare unit
name resolves to.

Consequence: a unit named `hello_ext` (from `hello_ext.pas`) that itself does
`uses './hello_ext.c'` — a C source sharing the unit's own base name — hits
the guard at `compiler/parser.inc:27093-27098`: `CompiledUnits` already
contains `strIdx('hello_ext')` (registered for the enclosing unit itself,
before its interface/uses clause is even parsed), so the `.c` file's
`ParseUsesUnitBody` call returns immediately at the `isCompiled` check and its
body is **never loaded**. Any function declared in that C file that's called
from elsewhere ends up registered only as an unresolved extern (confirmed via
`--debug`: `Proc N: PyInit_hello_ext at CodePos -1`), producing a working
*compile* but a runtime `symbol lookup error: undefined symbol: ...` — no
compile-time diagnostic at all.

This is silent and surprising: nothing about the path-form syntax
(`'./hello_ext.c'`) suggests it shares a namespace with plain unit-name
references, and the miss produces no error — just a dangling extern that only
misbehaves at link/run time for a dynamically-resolved symbol, or would
presumably hard segfault for a statically-resolved one.

## Reproduction

- `unit hello_ext;` interface: `uses pxxcio, './hello_ext.c';` where
  `hello_ext.c` (same base name as the unit) defines a function called from
  elsewhere in the unit.
- Compile any program importing `hello_ext`; the C file's definitions never
  load. `--debug` shows `CodePos -1` for a symbol that should have a body.

## Workaround used (Track N, this ticket)

Renamed the C module source so its base name does not collide with the
Pascal/NilPy unit name (`hello_ext.c` → `hello_ext_module.c` in
`test/nilpy_units/`). Fine for one file; does not fix the general hazard for
any bridge unit that (reasonably) wants a same-named C companion file.

## Suggested fix direction (Track A, not attempted here)

Path-form C/H references probably want their own key space distinct from
Pascal/NilPy unit names — e.g. key on the full normalized path rather than
bare base name, or at minimum exclude `.c`/`.h` path-form loads from the
plain-unit-name `CompiledUnits` table entirely (a C source is never itself
importable by bare name the way a `.pas` unit is, so there is no legitimate
reason for the two spaces to share keys). Whichever direction is chosen, the
miss should probably also raise a diagnostic instead of silently no-op'ing
when a `.c`/`.h` load is skipped as "already compiled" but no such file was
ever actually loaded under that path.

## Log
- 2026-08-02 — resolved, commit 5303d2741.
