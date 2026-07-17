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

## Triage progress (2026-07-17)

A nested interface as-cast bug `(x as IC) as IA` was found and **fixed separately**
(`a457f01b`, [[bug-pascal-nested-interface-as-cast]]) while investigating this — but the
seeds here **still crash/diverge**, so that was a different bug. Sharpened hypothesis for
what remains: the exit checksum does MANY `Mix((iwX as IY).Method(...))` calls, each
creating an **as-cast temp interface**. If the temp's AddRef/Release is off (double- or
missing-release), the object refcount drifts across those calls, and the final
`iwX := nil` releases underflow → double-free → SIGSEGV at exit; the wrong-value
(`pxx-vs-fpc`) variant would be an object finalized too early. Look at as-cast interface
temp refcount lifetime next (not the base-pointer, which `a457f01b` handled). Still needs
source delta-debug on the seed to confirm.

**Hypotheses tested minimally and DISPROVEN (narrows the search):**
- Simple as-cast temp refcount drift: a loop of 5 `(a as IB).Gb` calls destroys the
  object exactly once at `a := nil` (correct) — simple refcounting is fine.
- Basic single/nested interface `as`-cast: single works; nested was a *separate* bug
  (fixed `a457f01b`). Multi-interface flat class + managed field + ctor/dtor + release:
  all correct.
- Ansistring finalization, class methods: ruled out (crash survives `--strs 0`/`--clsm 0`).

So the trigger is NOT the isolated interface primitives — it emerges from the fuller
generated graph (deep hierarchy + many objects + properties finalizing together). Only
source-level delta-debug on the fixed 1469-line seed will isolate it.

**Ledger note (Track T):** the `pxx-vs-fpc_trace-length` signature COLLIDES with a
previously-fixed bug of the same coarse "trace-length" kind — do not mark this
interface divergence via that signature (it reads as already-fixed). This is exactly
[[feature-pasmith-divergence-signature-granularity]]; track this bug via THIS ticket,
not the ledger signature.

## Acceptance

- The seed compiles and runs to completion (matches the FPC checksum
  `9420765320240807970`), no SIGSEGV, all -O levels.
- A shrunk `test/test_*.pas` regression for the isolated construct.
- Gate: `make test` + self-host byte-identical + cross.

## Related — SAME ROOT (verified), and it points at the mechanism

`pxx-vs-fpc_trace-length` (32 hits same run, seed 53002) — pxx output *differs* from FPC,
no crash. **Verified NOT a generator false-positive:** the diverging exit checksum hashes
the RETURN VALUE of interface method calls via an `as`-cast —
`Mix((iw0 as IPas1).Ic1(...))`, `Mix((iw1 as IPas2).Ic2(...))` — not a raw interface
pointer. Both per-statement traces agree (21=21); only the exit checksum differs. Ic*(a)
returns `a + fi` (a field), so pxx computing a **different value** means
`(iwX as IOther).Method()` on a **multi-interface object** reaches the wrong `Self` /
field after the interface-to-interface cast. That is exactly the mechanism that, pushed
harder, corrupts the stack and SIGSEGVs above.

So the headline is: **interface-to-interface `as`-cast on an object implementing multiple
interfaces resolves the wrong object base** (each interface sits at a different IMT
offset; the cast must adjust the `Self` pointer, and doesn't correctly in the general
case). A minimal 3-interface `(iw1 as IPas2).Ic2()` DID return the right value, so the
break needs the fuller graph (deep hierarchy / multiple objects) — source-delta-debug
either seed. Fix once isolated: correct the base-pointer adjustment in the
interface-to-interface QueryInterface/`as` lowering. Cross-check
[[project_interface_single_pointer_abi_b337]] (interface value = one pointer) and
[[project_com_interface_default_and_lifetime]].
