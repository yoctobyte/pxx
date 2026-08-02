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

## Resolved 2026-08-02 — commit 5303d2741

Took the suggested direction: the already-compiled guard for a path-form
`.c`/`.h` keys on the PATH TEXT (`@cpath:<lowercased path>`) rather than the
stripped base name. `strIdx` is deliberately left alone — it still tags the
symbols the load registers (`CurrentUnitIdx`), so qualified access by base name
behaves exactly as before, and a genuine repeat of the same `uses './x.c'` still
dedupes.

**cpyext M1 is unblocked.** `test/nilpy_units/hello_ext.pas` was left in its
platonic shape on purpose — module source named after the module, as any real
CPython extension's is — with `make test-nilpy` printing a SKIP line rather than
renaming around the bug. That was the right call: the skip is now a real
assertion (`test_cpyext_hello` prints 42) and it needed no source change at all.

Verified alongside: the M2 / M3 / MarkupSafe cpyext tests and
`test_relpath_uses.pas` (the other path-form user) stay green. `gate.sh quick`
GREEN, self-host fixedpoint byte-identical.

## A NARROWER residual, measured — same family, not the same bug

One arrangement still fails, and it is worth writing down because it looks like
the original if you meet it: a unit whose `uses './collide.c'` shares its base
name AND which also carries an **explicit** `function collide_answer: Integer;
cdecl; external;` declaration. Then the runtime `undefined symbol` returns.
Without that declaration — which is what `hello_ext` does, and what an ordinary
`interface function` gives you — it works.

The cause is the other half of the shared key space: `CurrentUnitIdx` for the C
load is still `strIdx`, i.e. the ENCLOSING unit's index when the names collide,
so the C definition binds to the extern already declared in that same unit
instead of supplying its body. Naming the C file differently avoids it, as does
dropping the redundant `external` declaration.

**Deliberately not fixed here.** The clean answer is to give the C load its own
`CurrentUnitIdx` too, but that changes how every path-form C unit's symbols are
tagged — including the four cpyext units that work today — for a case with no
current user. Left as a known edge with a repro rather than a speculative change
under the self-host gate. If it acquires a user, that is the fix.

## Not done: the diagnostic

The ticket also asks that a skipped `.c`/`.h` load raise a diagnostic instead of
silently no-op'ing. Not implemented — with the key spaces separated the skip can
now only mean "this exact path was already loaded", which is correct rather than
suspicious, so the warning would fire on the legitimate case and not on any known
wrong one.
