---
track: U
prio: 40
type: decide
status: resolved
resolved: 2026-08-01
---

## DECIDED 2026-08-01 — capture everything (naive transitive capture), not option 2

**User's call.** Neither option 1 nor 2 as literally written: capture ALL of
the parent's locals into every sibling nested def, unconditionally, using
the existing by-value lift-capture machinery (`LiftCap*`,
`compiler/parser.inc`) — not narrowed to only-used names, and not the
constants-only global-hoist of option 2 (which leaves a gap for a sibling
capturing a *mutable* enclosing variable). This is a naive, unoptimized
version of option 1's transitive capture: correct by construction (a strict
superset of what's needed), no call-graph fixpoint analysis required, some
wasted by-value copies for names a given sibling doesn't read.

Any later optimization (the ticket's literal option 1, precise fixpoint) is
strictly **subtractive** on top of this — prove a name is never read
(directly or via a transitive sibling call) and drop it from that copy. It
can only shrink the capture set, never needs to, and can land as a separate
perf pass whenever it's worth it, not before. Simple and safe over clever.

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
