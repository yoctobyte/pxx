---
summary: "SIGSEGV at program exit in interface-heavy generated program (pasmith --intfs 3); crash after all traced statements, all -O levels"
type: bug
prio: 55
---

# Interface-heavy program crashes at exit/finalization (SIGSEGV)

- **Type:** bug (Track A/P — interface refcount / finalization / dispatch; shared
  IR/runtime). Runtime crash, not a compile error.
- **Status:** backlog
- **Found:** 2026-07-17, pasmith run with **interfaces enabled** (`--intfs 3`) — a config
  not exercised in prior clean runs. Two NEW signatures appeared together:
  `pxx-crash_trace-length` (this) and a `pxx-vs-fpc_trace-length` cluster (32 hits, likely
  related — see below). Interfaces are the trigger: every prior no-interface run was clean.

## Symptom (from the differential oracle)

Canonical finding seed **53011** (also reproduces on 53075):
```
fpc-O0/-O2   9420765320240807970    (FPC runs to completion, prints the checksum)
pxx-O0/-O2/-O3   <crash>(rc=-11)    (SIGSEGV, every -O level)
traces agree up to the shorter one (21 vs 21 checkpoints)
```
pxx executes ALL 21 traced statements correctly (checksums match FPC through the last
checkpoint), then **crashes at program exit** — i.e. in global finalization, not in the
program logic. gdb shows a **corrupted stack** (return addresses `0x20`, `0x0`, …) →
stack smash or an indirect call through a bad pointer (interface IMT / vtable). pxx has
no gdb-readable symbols even with `-g`, so the faulting routine wasn't named.

## Repro

```
tools/pasmith.py --seed 53011 --vars 10 --funcs 3 --stmts 20 --depth 4 --classes 5 \
  --objs 4 --strs 3 --recs 2 --arrs 2 --enums 2 --excepts 3 --hier 5 --props 3 \
  --exdtor 3 --clsm 3 --intfs 3
```
1469 lines. Shape: one class implements THREE interfaces
(`TIfc = class(TInterfacedObject, IPas0, IPas1, IPas2)`) with a managed field
(`fs: ansistring`), a `Create(v)` ctor and a `Destroy` override; three interface vars
`iw0..iw2` each hold a separate instance; an interface-to-interface `(iw1 as IPas2)`
cast is used; all are set `nil` before exit.

## Minimization status (partial — NOT yet reduced)

A hand-written minimal capturing {3-interface class + managed field + ctor/dtor +
`as`-cast + `:= nil` release + scope-exit finalize} does **NOT** crash. So the trigger
needs more of the object graph.

Ruled OUT (crash survives removing each): `--strs 0` (ansistring finalization is NOT the
cause — kills the managed-field theory) and `--clsm 0` (class methods irrelevant).
Config-level bisection is unreliable here — each pasmith param change **regenerates a
different program**, so crash presence is program-specific, not a clean per-feature
signal (e.g. `--strs 0` alone still crashes, but `--strs 0 --clsm 0` together does not).
Correct next step is **source-level delta-debug** on the ONE fixed 1469-line program
(crash persists ⇔ exit 139) — reduce statements/decls while the SIGSEGV holds. Deferred:
lengthy, needs a fresh focused session; the seed reproduces byte-for-byte meanwhile.

## Suspected area

Interface finalization/release order at program exit with a class implementing multiple
interfaces (each interface pointer sits at a different IMT offset — releasing through the
wrong base, or double-releasing an `as`-cast QueryInterface temporary, would corrupt the
stack/heap). Cross-check [[project_com_interface_default_and_lifetime]] (COM refcount
default; by-value intf temp needs AddRef) and [[project_interface_single_pointer_abi_b337]].

## Acceptance

- The seed compiles and runs to completion (matches the FPC checksum
  `9420765320240807970`), no SIGSEGV, all -O levels.
- A shrunk `test/test_*.pas` regression for the isolated construct.
- Gate: `make test` + self-host byte-identical + cross.

## Related

`pxx-vs-fpc_trace-length` (32 hits same run) — pxx output *differs* from FPC on other
interface programs (not a crash). Likely the same interface-lifetime defect surfacing as
a wrong checksum rather than a crash; triage together.
