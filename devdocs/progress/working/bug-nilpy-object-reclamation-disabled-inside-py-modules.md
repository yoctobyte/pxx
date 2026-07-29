---
track: N
prio: 65
type: bug
---

# NilPy object reclamation is switched off inside an imported `.py` module

Found 2026-07-29 while fixing
[[bug-nilpy-settings-editor-segfaults-on-bound-method-field]], whose whole cause
was one gate of this shape being wrong.

Seven NilPy-only rules are gated on `isNilPy and (CurrentUnitIdx < 0)`:

```
compiler/symtab.inc:5703   scope-exit PXXObjRelease for a class local
compiler/parser.inc:7810   zero-init of a NilPy class local
compiler/ir.inc:1979       (argument path)
compiler/ir.inc:6188       release-on-rebind, scalar over a class binding
compiler/ir.inc:6207       retain/release on a class-to-class rebind
compiler/ir.inc:6255       field-store ARC
compiler/ir.inc:6825       (call-result path)
```

`CurrentUnitIdx < 0` means **the main program only**. A class defined in an
imported `.py` module is NilPy user code just as much, but compiles with
`CurrentUnitIdx >= 0`, so none of these fire for it.

The set is at least self-consistent — no zero-init AND no release, so nothing
reads stale stack bytes — which is why this is a leak and not a crash: objects
created by a module's classes are never reclaimed, while the identical class in
the main file is. songformatter is exactly this shape (every class lives in an
imported module), so it gets no reclamation at all.

## Why it is filed rather than fixed

Flipping all seven to `((CurrentUnitIdx < 0) or PyExprMode)` — the discriminator
that fixed the bound-method gate, since `ParsePyUnit` sets `PyExprMode` for a
module body and Pascal RTL units never have it — is a one-line change each, but
it turns reclamation ON for a body of code that has never run with it. That
wants its own measurement (RSS slope on a module-heavy program, per
[[project_leak_vs_arena_artifact_diagnosis]]), not a drive-by edit at the end of
an unrelated fix.

They must also move TOGETHER: zero-init without release leaks, release without
zero-init frees garbage.

## Gate

`make test-nilpy` + a module-heavy `.npy` measured for RSS slope before and
after, plus the existing reclamation tests.

## RESOLVED @ 2026-07-29 — one predicate, `NilPyUserCode` (symtab.inc)

All nine sites (the seven above plus `ir.inc:8389` exception-slot nil-init and
`ir_codegen.inc:6899` prologue zero-init, both found by re-grepping) now call
one function instead of repeating the condition:

```pascal
function NilPyUserCode: Boolean;
begin
  NilPyUserCode := isNilPy and ((CurrentUnitIdx < 0) or PyExprMode);
end;
```

One predicate rather than nine copies is the point: the set MUST move together,
and nine copies is exactly how they drifted apart in the first place. The
bound-method gate at `parser.inc:5584`, which already carried the `or
PyExprMode` form by hand, now reads from it too.

### What it fixed beyond the leak

The missing return-ownership retain was not only a leak — it produced WRONG
VALUES. A module function returning an object handed the caller a reference
that the callee's scope exit had already dropped:

```python
# kalib2.py
def run2(chords: list[str], cb: Callable[[str], list[str]]) -> list[str]:
    return cb(chords[0])
```

returned `[]` where CPython gives `['C', 'C']`. That, plus
[[bug-nilpy-import-name-forces-function-object-abi]] (fixed first, commit
242b96878), is the whole of songformatter's cross-module `Callable` wall. Seven
cross-module shapes now match CPython exactly.

### Measured, as the ticket required (RSS slope, 20k vs 320k iterations)

| program | before | after |
| --- | --- | --- |
| module: `x = Node(i)` in a loop | flat | flat |
| main program: same | flat | flat |
| module: `y = make(i)`, make returns an object | 0.94 → 10.3 MB | 2.5 → 35.1 MB |
| main program: same | 2.6 → 35.4 MB | 2.6 → 35.4 MB |

Read that honestly: module code now behaves EXACTLY like main-program code, which
is what the ticket asked for — but the main-program path has a pre-existing leak
of its own, so on that one shape the module version gets worse before it gets
better. It was previously "cheaper" only by doing no reclamation at all, which is
also what made it return freed objects. The residual is filed and reproduces on
the main-program path with the pre-fix compiler, so it is not a regression from
this change:

- [[bug-nilpy-returning-a-construction-leaks-one-ref]] — `return Node(...)`
  takes a +1 that no scope exit balances; `x = Node(...); return x` is flat.
- [[bug-nilpy-method-returning-a-fresh-string-leaks]] — a method returning a
  fresh managed string leaks ~32 B/call; the same body as a plain def does not.

### Gate

`tools/gate.sh full` GREEN: `make test-nilpy`, self-host fixedpoint
(byte-identical), `testmgr --tier quick`, `make test`.
