---
slug: bug-c-two-same-named-file-scope-static-variables-share-one-syms-row-and-alias
track: C
prio: 45
type: bug
blocked-by: []
status: backlog
found: 2026-09-05
found-by: frankC
owner: unassigned
summary: "The VARIABLE arm of the file-scope-static collision. Two same-named file-scope `static` variables in two C modules share one Syms[] row, so they are ONE variable: reading module A's gives B's value and writing A's changes B's. There is no SymCModule at all — the attribution ProcCModule gives functions has no data-side twin. Measured against gcc compiling the same sources as three translation units: pxx prints `1 2 / 2 2 / 3 70 / 4 70` where gcc prints `1 1 / 2 2 / 3 70 / 4 2`. Zero instances in crtl today (no cross-module duplicate static variable name exists), so nothing in tree is wrong because of it — but it is a SILENT WRONG VALUE, a worse class than the function arm, which was fixed separately."
---

# Two same-named file-scope static variables share one Syms row, and alias

## The sibling of the function arm

`feature-c-two-same-named-file-scope-statics-share-one-procs-row-so-neither-can-have-a-symbol`
fixed the FUNCTION arm: a `static` function now gets a Procs row per (module,
name), and C name resolution prefers the asking module's own body. This is the
same defect one namespace over, and it is worse.

Functions were saved by an accident of the fixup machinery — each call site
keeps a `CallFixTarget` snapshot and stays BAKED, so calls reached the right
body even while sharing a row. **Variables have no such snapshot.** One row
means one address means one variable.

## Measured

`test/fixtures/`-style probe, two modules each with `static int v` initialised
to 1 and 2, plus accessors. Oracle is gcc compiling the three files as three
translation units, which is the semantics pxx's single-buffer module
attribution emulates:

```
        pxx (one buffer)      gcc -DSEPARATE_TU (three TUs)
  1     2                     1        <- module A reads B's value
  2     2                     2
  3     70                    70       <- set_a(70)
  4     70                    2        <- ...changed module B's v
```

Rows 1 and 4 are the finding. Row 4 is the sharper of the two: a write through
module A's `v` is observable through module B's `v`, which is aliasing across
what C guarantees are two distinct objects with internal linkage.

Probe sources are in the scratchpad of the session that found this, not in
`test/` — a test belongs with the fix, and adding a red row would land a known
failure in `test-core`.

## Why it is not urgent

**Zero instances in crtl.** Every file-scope `static` variable name in
`lib/crtl/src/*.c` is unique across modules (checked by name across all
modules, 2026-09-05), so no crtl module aliases another's state today. The
reachable population is a user's unity build, or a future crtl module that
reuses a name — and the second is a live hazard precisely because nothing warns.

Note the function arm's diagnostic does not cover this: the duplicate-definition
warning is about bodies, and two same-named statics in ONE module warn while
two in different modules deliberately do not. A variable collision is silent in
both cases.

## The shape of the fix, and why it is bigger than the function arm

The function arm needed three call sites changed (`CFindProcFromModule` at the
call path, the address-decay path and the redeclaration path) because C
function names resolve through `FindProc` in few places. **Variables resolve
through `FindSym`, which cparser.inc calls 28 times**, and it is a hot path.

What is needed:

1. `SymCModule : array of Integer` in `defs.inc`, the data-side twin of
   `ProcCModule`, `-1` for "not a C module". Set it where linkage is already
   decided — `CRecordGlobalLinkage` is the single choke point both declaration
   paths were routed through for exactly this kind of reason, so it is the
   right place and the two cannot drift.
2. A rung in the declaration path: a `static` declaration whose found symbol is
   a static **defined in another module** must not seize that row. Mirror
   `RUNG S` in `ParseCSubroutine`, including its deliberate narrowness — both
   sides `static`, both in the current unit, the existing row's module known.
3. A module-preferring lookup for C. The 28 `FindSym` sites are the cost; the
   function arm's `CFindProcFromModule` is the model, including its fast-out
   (a name whose found row already matches the asking module never walks).

**Do not change `FindSym` itself**, for the reason `CFindProcFromModule`
records about `FindProc`: it serves Pascal and NilPy too, and a C-module
preference has no meaning there.

## Check before designing

`SymCStaticLink`, `SymObjDataExternOnly`, `SymObjDataScope`, `SymObjRuntimeCopy`
and `SymAllocSize` are all per-row, so today the second module's attributes
silently overwrite the first's — the same side effect the function arm had.
A reader should not assume the current values are right for the first symbol.
