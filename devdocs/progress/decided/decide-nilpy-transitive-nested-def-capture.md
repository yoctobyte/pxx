---
track: U
prio: 40
type: decide
status: moot
resolved: 2026-08-01
---

## MOOT 2026-08-01 — already fixed, verified directly

Before acting on a "capture everything" decision, tested the ticket's exact
repro (`FAM_RO`/`FAM_WO`/`FAM_RW`/`FAM_BIN`, the `create` param, sibling
call) against current master: it compiles and runs correctly, output
matches CPython (`r`/`w+`/`rb`). [[bug-nilpy-nested-def-capture-sets-are-not-final]]
(resolved 2026-07-30, commit `8cae8770b`) already implemented full
fixpoint-based transitive capture — the ticket's own literal "option 1" —
for exactly this shape (a lambda/nested-def calling a sibling that captures
a name neither of them reads directly). This ticket's premise was stale by
the time it was worked tonight.

An earlier pass through this ticket (same session) resolved it as "capture
everything, naive version of option 1" without checking whether the bug
still reproduced first — exactly the "measure before concluding" mistake
this project's own debugging discipline warns against. Caught and corrected
before any code changed. No action needed; closing as moot.

# decide: NilPy transitive capture for sibling nested-def calls

## The fork

uforth's `build_base_vm()` has function-level constants (`FAM_RO=1`, `FAM_WO`,
`FAM_RW`, `FAM_BIN`) and two sibling nested defs:

```python
def build_base_vm():
    FAM_RO = 1; FAM_WO = 2; FAM_RW = 3; FAM_BIN = 0x10
    def _file_open_mode(fam, create):
        if fam == FAM_RO: ...          # captures FAM_RO/WO/RW
    def _open_file_common(vm, path, fam, create):
        f = open(path, _file_open_mode(fam, create))   # calls the sibling
```

pxx flattens nested defs into top-level procs with the captured enclosing
locals appended as trailing by-value params, filled at each CALL site by
`FindSym`. But `_open_file_common` calls `_file_open_mode`, which captures
`FAM_RO` — and `FAM_RO` is NOT in `_open_file_common`'s own scope (it is a
local of the COMMON PARENT `build_base_vm`). So the capture fill fails:
`nested def captures FAM_RO, which is not in scope at this call`.

CPython resolves this by closure chaining: `_file_open_mode` closes over
build_base_vm's `FAM_RO` at DEFINITION time, independent of who calls it.

## Options

1. **Transitive capture** (recommended): when a nested def A calls sibling B
   and B captures name X not in A's scope, A transitively captures X too and
   forwards it. Requires a fixpoint over the call graph within one parent.
2. **Hoist function-level constants to module globals**: a nested def reading
   an all-caps enclosing constant binds it as a global-scoped value at def
   time (constants only, never mutated). Narrower, matches the corpus.
3. **Closure objects for every nested def** (the pyeval-closure model already
   used for value-position defs): snapshot the defining scope. Uniform but a
   bigger perf/representation change for the common direct-call case.

## Recommendation

Option 2 as an immediate unblock (uforth only needs the constant case), Option
1 as the correct general fix. Filed while driving uforth's filetest — the file
words (CREATE-FILE/OPEN-FILE) are otherwise implemented (TPyFile, raw
syscalls). Blocks the file-word conformance set only.
